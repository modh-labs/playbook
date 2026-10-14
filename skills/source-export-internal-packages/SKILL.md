---
name: source-export-internal-packages
description: Internal-only TypeScript packages in a monorepo should export source, not a compiled dist/. A built artifact silently goes stale when its source changes and can ship outdated types to production. Activates when adding/auditing a workspace package's build setup, when a just-added export isn't visible to a dependent until rebuild, or when reviewing a package that has a `build` script + `dist/` exports but is consumed only by other buildable apps.
---

# Source-Export Internal Packages

## The one principle

**An internal package consumed only by other buildable apps in the same monorepo
should export its TypeScript source (`exports` → `./index.ts`), not a compiled
`dist/`.** Compiling it creates a second copy of the truth that goes stale the
moment you edit source without rebuilding — and nothing forces the rebuild.

## When This Skill Activates

- Adding a new shared/internal package to a monorepo (`packages/*`).
- A dependent doesn't see a symbol you just added/changed in a workspace package — until you rebuild that package.
- Reviewing a package that has a `"build"` script + `dist/` in its `exports`/`main`/`types`, and is imported only by other apps/packages in the repo.
- A `dist/` directory is checked into git for an internal package.
- Typecheck/CI passes locally but ships wrong types, or vice-versa.

## The diagnostic question

> **"Is this package imported only by other things in this monorepo that compile
> their own code (apps via a bundler, or packages that are themselves bundled)?"**

- **Yes** → export source. No build step. (Turborepo calls this a *Just-in-Time package*.)
- **No** — it's published to npm, or `require()`d at runtime by a plain Node process that does not transpile TS → it genuinely needs a build (a *Compiled package*).

## Decision Tree

```
Who consumes this package?
├─ Only apps/packages in THIS monorepo that transpile TS
│  (Next.js, Vite/Vitest, bun, tsup-built siblings, ts-node/tsx)
│        → SOURCE-EXPORT. Delete the build. exports → ./index.ts
│
├─ Published to npm for external consumers
│        → COMPILED. Build to dist/, ship types.
│
└─ require()'d at runtime by a plain `node dist/x.js` process
   that does NOT transpile TS
         → COMPILED (or make that consumer transpile).
```

## Why the built artifact is a footgun

A compiled internal package has **two representations of the same code**: the
source you edit and the `dist/` dependents resolve. They drift the instant you
edit source without rebuilding. The failure compounds when:

- The consuming app's build does **not** depend on the package's build
  (`"dependsOn": []` in `turbo.json`, or no `^build`), so a stale `dist/` is used as-is.
- The app **ignores type errors at build** (`typescript: { ignoreBuildErrors: true }`),
  so even a type mismatch from the stale `dist/` won't fail the build.

Result: you can ship **outdated types/values to production** from a `dist/` nobody
remembered to rebuild — with zero signal. Source-export removes the artifact, so
there is nothing to go stale.

## Core Rules

### Rule 1 — Internal package `exports` point at source

```jsonc
// ✅ CORRECT — package.json of an internal-only TS package
{
  "name": "@org/schema",
  "private": true,
  "main": "./index.ts",
  "types": "./index.ts",
  "exports": {
    ".":       { "types": "./index.ts", "default": "./index.ts" },
    "./types": { "types": "./types.ts", "default": "./types.ts" }
  }
  // no "build" script, no tsup/tsc-build, no "dist" in exports
}
```

```jsonc
// ❌ WRONG — compiled artifact for an internal-only package
{
  "main": "./dist/index.cjs",
  "types": "./dist/index.d.ts",
  "exports": { ".": { "types": "./dist/index.d.ts", "import": "./dist/index.mjs" } },
  "scripts": { "build": "tsup" }   // <-- the stale-artifact source
}
```

### Rule 2 — `dist/` for an internal package is never committed

Add it to `.gitignore`. A tracked `dist/` is a guarantee someone will commit a
stale one. (If there's no build, there's no `dist/` at all — even better.)

### Rule 3 — Consuming apps must transpile the workspace package

This is usually automatic (Next.js App Router + Turbopack, Vite, bun, tsx all
transpile workspace TS). If a bundler needs to be told, add the package to its
transpile list (e.g. Next's `transpilePackages`). Verify with a typecheck after
deleting `dist/` — if dependents still resolve the symbols, source-export works.

### Rule 4 — Document the "no build" decision at the package root

A `README`/`AGENTS.md` line stating "source-export package — do not add a build
step or `dist/` export" stops the next person from 'helpfully' re-adding tsup.

## Migration Pattern (compiled → source-export)

```
1. package.json: exports/main/types → ./index.ts (+ subpath → ./<entry>.ts)
2. Remove the "build"/"dev" scripts and the bundler devDep (tsup/tsc-build).
3. Delete dist/ and any build-only tsconfig/caches. Gitignore dist/.
4. Document "no build step" at the package root.
5. Delete dist/, run a full typecheck. If dependents resolve from source
   (a just-edited symbol is visible with NO rebuild), you're done.
```

The single most convincing verification: **delete `dist/`, then typecheck the
whole repo.** Green = dependents read source.

## Anti-Patterns

- **"Build your shared packages, that's best practice."** True for *published*
  packages. For internal-only TS packages it adds a stale-artifact class of bug
  for zero benefit — the consuming apps already compile.
- **Keeping the build "for faster typecheck" via prebuilt `.d.ts`.** The cache
  saved is dwarfed by the debugging cost of one stale-dist incident.
- **Gating the stale artifact behind a turbo `dependsOn: ["^build"]` instead of
  removing it.** That patches the *build* path but not local dev, single-file
  test runs, or a committed-stale `dist/`. Remove the artifact.
- **Mixing strategies inconsistently.** If 6 internal packages export source and
  1 compiles, the 1 is the footgun. Make them uniform.

## Audit Checklist

- [ ] Every internal (`private: true`, monorepo-only) package exports source, not `dist/`.
- [ ] No internal package has a `build` script unless it's published or runtime-`require`d untranspiled.
- [ ] No `dist/` directory is tracked in git for an internal package; `dist/` is gitignored.
- [ ] Consuming apps transpile workspace packages (verified: delete `dist/`, full typecheck stays green).
- [ ] The package root documents "no build step."
- [ ] CI/build does not silently depend on a prebuilt `dist/` (`dependsOn`/`ignoreBuildErrors` can't mask a stale one).

## Related

- `turborepo` — task graph + Just-in-Time vs Compiled package strategies.
- `bun-workspaces-catalog-hoisting` — the sibling concern for shared *dependency versions*.
- `monster-file-decomposition` — another "no re-export shim / source is the truth" monorepo principle.
