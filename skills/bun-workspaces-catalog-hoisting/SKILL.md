---
name: bun-workspaces-catalog-hoisting
description: >
  In a multi-workspace monorepo, hoist shared dependencies into Bun
  catalogs so version bumps are a single root edit and package families
  that must move together (Mastra, React renderer + types) are locked in
  structurally instead of by convention. Use when adding a new shared
  dep to 3+ workspaces, when auditing version drift, or after any
  framework upgrade that breaks because satellite packages hard-import
  newer core internals.
---

# Bun Workspaces Catalog Hoisting

## When This Skill Activates

- You're adding a new shared dependency to a 3rd (or 4th, or 23rd) workspace
- You're auditing a framework upgrade (Mastra, Next.js, React, Drizzle, Sentry, Clerk) that involves > 1 `package.json` file
- You hit "X is not exported by Y" deep in a bundler - and the cause is a satellite package hard-importing internals from a core package on a newer version than your hoisted one
- You're scanning the monorepo for hygiene wins and find the same dependency declared with 3+ different version ranges across workspaces
- You're moving from pnpm/yarn workspaces to bun and want to bring the catalog with you (or set it up for the first time)

## The Diagnostic Question

> "How many `package.json` files do I have to edit when I bump dep X?"

If the answer is more than one, you have catalog territory. If the answer is "three, because they all need to move together or the install breaks," you have **named-catalog** territory.

## Critical Rule

**Shared dependencies live in `workspaces.catalog` (or `workspaces.catalogs.NAME` for families). Workspaces reference them with `"X": "catalog:"` or `"X": "catalog:NAME"`. The literal version range appears in exactly one place - root `package.json`.**

## The Problem

Workspace monorepos make duplication cheap. Every app declares its own dependencies, and bun/pnpm/yarn hoist transitives - but the *declared* version range is per-workspace. Three things go wrong over time:

### 1. Silent drift

You scan one day and find `zod` declared as `^4.0.0` in `packages/services`, `^4.3.5` in nine apps, `^4.3.6` in two more, and `^4.4.3` in the latest one anyone touched. They all *currently* resolve to the same installed version, but the day someone tightens a sensitive workspace's range, the others either lock to old versions or silently float to new majors.

### 2. Family coupling failure

Some package families *must* move together. The Mastra AI framework is the worst offender we've seen: `@mastra/libsql@1.11.0` literally does `import { TABLE_FAVORITES } from '@mastra/core'`, where `TABLE_FAVORITES` only exists in `@mastra/core@1.35.0+`. Bumping libsql without bumping core fails the build with a missing-export error - but nothing in the satellite's `peerDependencies` warns you.

React has the same coupling on a smaller scale: `react` + `react-dom` + `@types/react` + `@types/react-dom` must all match or you get subtle hydration bugs and type errors at the boundary.

### 3. "Low-risk" bumps that aren't

The audit says: "we're 2 minors behind on `@mastra/core`, easy bump." The bump fails because:
- `@mastra/core@1.35.0` has a bundler regression on monorepo workspace re-exports
- `@mastra/libsql@1.11.0` requires the same 1.35.0 internal symbol
- You can have core@1.33.1 + libsql@1.7.2 (works) OR core@1.35.0 + libsql@1.11.0 (build fails on the bundler bug)
- Mixed: core@1.33.1 + libsql@1.11.0 = `TABLE_FAVORITES not exported` error

A 3-hour bisection later, you discover the satellite coupling is undocumented and the catalog needs to declare them as a single named unit so this hazard doesn't recur.

## Decision Tree

```
Is this dep declared in 3+ workspace package.json files?
│
├─ NO → Leave it. Workspace-local deps are fine.
│
└─ YES → Hoist to catalog.
        │
        ├─ Are these N packages of the same family that MUST move together?
        │  (Mastra, React renderer + types, Tailwind core + plugins,
        │   @ai-sdk/* providers, @clerk/* SDKs, fumadocs-*)
        │  │
        │  ├─ YES → Named catalog: workspaces.catalogs.{name}
        │  │
        │  └─ NO  → Default catalog: workspaces.catalog
        │
        └─ Is there real version drift in use?
           │
           ├─ Single range, multiple refs → "insurance lock-in." Catalog at current pin.
           ├─ 2-3 minor ranges → Catalog at highest pin. Soft-bumps the laggers.
           ├─ Major-version split (e.g., 12.x vs 16.x) → STOP. This is a migration, not a hoist.
           └─ Wildcard (>=15.0.0) in use → Catalog and tighten. Wildcards in workspaces are a smell.
```

## Implementation Pattern

### Step 1: Survey drift

Before hoisting anything, scan for what's actually duplicated. The threshold to hoist is "3 refs and 2 ranges" or "any family coupling regardless of count."

```bash
# Replace `bun` paths with `pnpm` / `yarn` equivalents as needed
python3 << 'EOF'
import json, glob
from collections import defaultdict
deps_by_pkg = defaultdict(list)
for pkg in glob.glob("apps/*/package.json") + glob.glob("packages/*/package.json"):
    if "node_modules" in pkg: continue
    d = json.load(open(pkg))
    for kind in ("dependencies","devDependencies","peerDependencies"):
        for name, ver in (d.get(kind) or {}).items():
            if isinstance(ver, str) and ver not in ("workspace:*",) and not ver.startswith("catalog:"):
                deps_by_pkg[name].append((pkg, ver))
# Sort by drift severity (range count desc, ref count desc)
rows = [(len(v), len(set(x[1] for x in v)), name) for name, v in deps_by_pkg.items() if len(v) >= 3]
rows.sort(key=lambda r: (-r[1], -r[0]))
for refs, ranges, name in rows[:30]:
    print(f"  {name:<40} {refs:>3} refs × {ranges} ranges")
EOF
```

### Step 2: Declare the catalogs at root

```jsonc
// root package.json
{
  "workspaces": {
    "packages": ["apps/*", "packages/*"],
    "catalog": {
      // Default catalog: plain shared deps with no family coupling.
      // Workspaces reference as "X": "catalog:"
      "zod": "^4.4.3",
      "drizzle-orm": "^0.45.2",
      "typescript": "^5.9.3",
      "@types/node": "^25.0.9"
    },
    "catalogs": {
      // Named catalogs: families that MUST move together.
      // Workspaces reference as "X": "catalog:NAME"
      "mastra": {
        "@mastra/core": "1.33.1",
        "@mastra/deployer-vercel": "1.1.8",
        "@mastra/libsql": "1.7.2",
        "@mastra/loggers": "1.0.3",
        "@mastra/memory": "1.10.0",
        "@mastra/observability": "1.5.1",
        "mastra": "1.3.15"
      },
      "react": {
        "react": "19.2.0",
        "react-dom": "19.2.0",
        "@types/react": "19.2.3",
        "@types/react-dom": "19.2.3"
      }
    }
  }
}
```

### Step 3: Bulk-rewrite consumer workspaces

For high-count hoists (10+ refs), use a JSON script over `sed`/`Edit` to avoid quote/escape edge cases:

```python
import json, glob

TARGETS = {"react", "react-dom", "@types/react", "@types/react-dom"}
CATALOG_REF = "catalog:react"

for pkg_path in glob.glob("apps/*/package.json") + glob.glob("packages/*/package.json"):
    if "node_modules" in pkg_path: continue
    with open(pkg_path) as f:
        pkg = json.load(f)
    changed = False
    for kind in ("dependencies", "devDependencies", "peerDependencies"):
        deps = pkg.get(kind)
        if not deps: continue
        for name in list(deps.keys()):
            # Guard: only touch string values. peerDependenciesMeta has object values.
            if name in TARGETS and isinstance(deps[name], str) and deps[name] != CATALOG_REF:
                deps[name] = CATALOG_REF
                changed = True
    if changed:
        with open(pkg_path, "w") as f:
            f.write(json.dumps(pkg, indent="\t") + "\n")
```

### Step 4: Verify

```bash
bun install                          # should resolve cleanly
grep -rn '"X":' --include=package.json apps packages | grep -v node_modules | grep -v "catalog:"
# ↑ should return empty: no non-catalog refs remain
# Pick the riskiest consumer (most lines of code or most extreme version jump) and typecheck it
cd apps/web && bun run typecheck
```

### Step 5: Commit each family separately

One named-family per commit. Easier to bisect if a later commit regresses a build:

```
chore(deps): hoist all @mastra/* + mastra CLI into a named bun catalog
chore(deps): hoist react family into named bun catalog "react"
chore(deps): hoist zod to default bun catalog (^4.4.3)
chore(deps): hoist typescript + @types/node + @supabase/supabase-js to catalog
```

## Anti-Patterns

### Anti-pattern 1: Bumping a satellite without bumping the rest of the family

```jsonc
// WRONG - works at install time, fails at build time
// (workspaces other than the bumped one still have explicit @mastra/core@1.33.1)
{
  "dependencies": {
    "@mastra/core": "1.33.1",           // unchanged
    "@mastra/libsql": "1.11.0"          // bumped - requires core@1.35+
  }
}
```

Use a named catalog. Bumping the catalog forces all family members to move together. Bumping just one entry of a named catalog is what you *want* to make impossible.

### Anti-pattern 2: Catalog'ing a "drift" that's actually three configs

```jsonc
// WRONG - single catalog can't represent three different working configs
"catalogs": {
  "fumadocs": { "fumadocs-core": "^16.4.4", ... }  // forces docs + handbook (on v12) to break
}
```

The pre-hoist scan reveals **drift**. Look more carefully. If apps/docs is on `fumadocs@12.0.0` and apps/admin is on `^16.4.4`, you're not looking at drift - you're looking at two apps stuck on different majors. Hoisting to one forces a migration. **That's a feature work item, not a hoist commit.** Defer it; ship a Linear ticket; don't paper over a migration with a one-line catalog edit.

### Anti-pattern 3: Hoisting tooling-internal deps

`@types/node` and `typescript` benefit from catalogs (consistency across consumers prevents type incompatibilities). But hoisting build-only deps like `@babel/preset-env` or test-only deps like `@testing-library/react` is usually not worth it - they're isolated to per-workspace config.

The bar is: **does drift cause real bugs?** Type-checking consistency does. Test runner version does. Babel preset version doesn't, in most projects.

### Anti-pattern 4: Catalog references in published-library `peerDependencies`

```jsonc
// In a package you publish to npm:
{
  "peerDependencies": {
    "react": "catalog:react"  // becomes "19.2.0" - way narrower than you mean
  }
}
```

In a fully internal monorepo this is fine (and arguably correct). In a package you actually publish, peer deps are an external contract - narrowing them via catalog leaks an implementation detail to consumers. Either keep an explicit range in the peer, or pre-process before publish.

### Anti-pattern 5: Mixing version strategies across the catalog

Pick one: caret (`^X.Y.Z`) for "follow minor bumps" or exact (`X.Y.Z`) for "lock to this version exactly." Mixing them in the same catalog without a reason creates noise:

```jsonc
"catalogs": {
  "mastra": {
    "@mastra/core": "1.33.1",        // exact - good for AI frameworks that move fast
    "@mastra/deployer-vercel": "^1.1.8"  // caret - inconsistent for the same family
  }
}
```

For framework families that hard-import internals (Mastra), prefer exact pins so updates are deliberate. For everything else, caret is fine.

## The 4-Tier Methodology

When sweeping a repo for catalog candidates, prioritize in this order:

### Tier A - Demonstrated drift (do these first)

Deps with 3+ refs *and* 2+ distinct version ranges in use. Each is a future incident waiting to happen. Hoist to default catalog at the highest existing pin.

### Tier B - Family couplings (do these next, as named catalogs)

Package families that must move together. Discovered by:

- Reading the satellite's `peerDependencies` (if `>=X.Y.Z` and X is the same as the family's other packages, it's coupled)
- Hitting a bundler error like "X not exported by Y" after bumping one but not the others
- Reading the changelog for "we added a new core export" → all satellites need at least that version

Examples that come up often:
- `@mastra/*` (the worst offender - hard-imports core internals)
- React renderer family: `react` + `react-dom` + `@types/react` + `@types/react-dom`
- `@ai-sdk/*` providers
- `@clerk/nextjs` + `@clerk/backend` + `@clerk/themes` + `@clerk/types`
- `fumadocs-core` + `fumadocs-ui` + `fumadocs-mdx` (when on the same major)
- Tailwind: `tailwindcss` + `@tailwindcss/postcss` + `tailwind-merge`

### Tier C - Single-range insurance locks (cheap and worth it)

Deps already in lockstep across 3+ consumers - catalog them anyway. Locks the lockstep so future drift can't sneak in.

### Tier D - Apparent drift that's a migration (DON'T hoist)

If the scan shows `fumadocs-core: 12.0.0` in two apps and `^16.4.4` in another, that's not 2-range drift - it's two apps stuck on a deprecated major. A hoist would force a migration. File a ticket; come back to it as a feature.

## Audit Checklist

When reviewing a PR that adds or bumps shared deps:

- [ ] Is this dep used in 3+ workspaces?
  - [ ] If yes and not hoisted: should be a `"catalog:"` ref, not a literal range.
- [ ] Does this dep have sibling packages from the same family in the repo?
  - [ ] If yes: are they all on the same major? If yes, use a named catalog. If no, this is a migration.
- [ ] Does the satellite package hard-import internals from a sibling core package?
  - [ ] Read its `dist/*.js` for `import { ... } from '@family/core'`. If it imports symbols that are new in a recent core release, the catalog must cover both.
- [ ] Does the catalog entry's version range match what's installed in the lockfile?
  - [ ] If not, run `bun install` once more - the catalog is the source of truth.
- [ ] If you're adding a named catalog, is *every* family member included?
  - [ ] Partial named catalogs (e.g., catalog `react` + `react-dom` but leave `@types/react` literal) reintroduce the coupling failure mode.
- [ ] After the hoist, does the riskiest consumer (most code, biggest version delta) typecheck cleanly?

## When Bun Catalogs Aren't Available

If you're on a package manager that doesn't support catalogs (older pnpm, older yarn, npm), use:

- **`overrides` / `resolutions`** at the root to force install-time deduplication. Works for transitives but doesn't help with declared per-workspace versions.
- **Syncpack** (`syncpack`) as a CI lint that fails when declared versions don't match across workspaces. Same outcome via a different mechanism - drift is detected and rejected rather than structurally prevented.
- **A README rule** that doesn't actually prevent drift, but at least documents the convention.

Bun supports catalogs natively from 1.2+; pnpm from 9.5+; yarn doesn't yet (as of 2025). If you have the choice, prefer catalogs - they're declarative and enforced by the package manager rather than by linter convention.

## Origin

This skill was extracted from a Mastra audit on the Aura monorepo. The audit's "Step 1: bump all `@mastra/*`" was estimated at "1 hour, low risk." The actual sequence:

1. Bumped 7 `@mastra/*` packages + CLI across 6 workspaces. Install succeeded.
2. Build failed with `"admin" cannot be exported from .mastra/.build/@aura__database.mjs as it is a reexport that references itself`. Spent 30 minutes assuming the bug was in our `@aura/database` package.
3. Bisected the version matrix - discovered `@mastra/core@1.35.0` has a bundler regression on monorepo workspace re-exports.
4. Reverted core to 1.33.1, kept satellites at latest. Different build error: `"TABLE_FAVORITES" is not exported by @mastra/core@1.33.1, imported by @mastra/libsql@1.11.0`. Discovered satellite hard-coupling.
5. Reverted everything. Audit shipped with version bumps deferred and a "package version coupling" memory entry written.

The structural fix arrived in a follow-up session: hoist the family into a named catalog so bumping one element forces bumping all, and so future audits can't accidentally split the matrix again. Future Mastra upgrades are now one root edit.
