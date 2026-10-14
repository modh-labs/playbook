---
name: github-ci-efficiency-audit
description: 'Audit a GitHub repo (or monorepo) for wasted CI minutes and missing governance, then fix the safe parts via the gh CLI. Use when CI feels slow or expensive, after a billing surprise, when hardening a repo/org, or when a green-looking pipeline doesn''t actually block bad merges. Covers runner-cost auditing, caching the every-PR install, the --affected/changed-set gotchas that red unrelated PRs, and the required-status-checks ordering trap.

'
---

# GitHub CI Efficiency & Governance Audit

A mature pipeline can still bleed money and ship weak guarantees. This skill is the audit you run
to find both: where minutes leak, and where a green check is decoration rather than a gate. It
pairs with `ci-pipeline` (which covers pipeline *structure* — cheapest-first, fail-fast, no deploy
in CI); this one covers *cost*, *governance*, and the *traps* that come with change-detection.

## When This Skill Activates

- A CI/Actions billing surprise, or "make CI cheaper / faster without burning minutes."
- Hardening a repo or org (after a plan upgrade, a new client, a security review).
- A pipeline that looks green but a red check still merges — i.e. checks aren't required.
- Onboarding a repo onto faster third-party runners (Blacksmith, Depot, Namespace).
- Unrelated PRs suddenly going red, or a docs/config-only PR failing the build/test job.

## The Two Diagnostic Questions

1. **Cost:** "Which jobs run on *metered* runners, how *often*, and is the *every-PR install* cached?"
2. **Governance:** "Does a *red check actually block merge*, and who is forced to review?"

If you can't answer both from the workflow files + repo settings, run the audit below.

## Decision Tree

```
Auditing CI cost?
  ├─ List `runs-on:` across ALL workflows.
  │    Third-party runners (blacksmith-*, depot-*, namespace-*) bill SEPARATELY from
  │    GitHub-hosted minutes and are usually cheaper/faster. `ubuntu-latest` = metered.
  │    → Any metered jobs hiding among third-party ones? Standardize onto one pool.
  ├─ List scheduled crons. A */15 cron = ~2,880 runs/month — usually THE dominant cost.
  │    → Move off metered runners and/or relax cadence; dedupe vs uptime monitors.
  └─ Which workflow runs on EVERY pr/push? Is its dependency install cached?
       → The hot path is the cache that matters most. Rarely-run workflows caching while
         the every-PR one doesn't is the most common inversion. Add a lockfile-keyed cache.

Auditing governance?
  ├─ Does the branch ruleset / protection list REQUIRED status checks?
  │    null/empty = CI is advisory; a red check still merges.
  │    → BUT only require checks once the branch is PR-only (see ordering trap).
  ├─ Merge hygiene: squash-only? auto-delete branch? auto-merge?
  ├─ Secret scanning + push protection on? Dependabot on every repo?
  └─ CODEOWNERS present? Org defaults secure for NEW repos?

Pipeline uses --affected / changed-set?
  → Walk the "Change-Detection Gotchas" section. These red unrelated PRs.
```

## Core Rules

### 1. Standardize runners; find the metered stragglers

Third-party runners are drop-in (`runs-on: ubuntu-latest` → `runs-on: blacksmith-4vcpu-ubuntu-2404`)
and bill outside GitHub's metered pool. When most jobs are already on them, the few left on
`ubuntu-latest` are the entire bill — and usually an oversight, not a decision.

```bash
# CORRECT — enumerate every runner and every cron in one pass
grep -Hn "runs-on:" .github/workflows/*.yml
grep -Hn "cron:"    .github/workflows/*.yml
```

A `*/15` schedule is ~96 runs/day. On a metered runner, uncached, that single cron dwarfs every
PR run combined. Move it to the cheap pool, cache it, and question the cadence (does a 15-minute
synthetic monitor duplicate your uptime tool?).

### 2. Cache the every-PR install — it's the highest-leverage cache

The setup action that installs your toolchain (`setup-bun`, `setup-node`, …) installs the *binary*,
not your *project dependencies*. Cache the package manager's global cache, keyed on the lockfile.

```yaml
# CORRECT — restores on lockfile match, invalidates only when deps change
- name: Cache dependencies
  uses: actions/cache@v4
  with:
    path: ~/.bun/install/cache          # or ~/.npm, ~/.pnpm-store, etc.
    key: deps-${{ runner.os }}-${{ hashFiles('bun.lock') }}
    restore-keys: deps-${{ runner.os }}-
```

The payoff scales with frequency: trivial on a once-per-PR job, dominant on a `*/15` cron. The
classic inversion to fix: E2E/monitoring workflows cache deps while the every-PR gate doesn't.

### 3. Don't require status checks until the branch is PR-only (the ordering trap)

Making CI a required status check is the single highest-value governance fix — it turns an advisory
gate into a blocking one. But there's a deadlock:

> If CI only triggers on `pull_request` and you require it on a branch people still push to
> directly, those direct pushes block forever — the required check never runs.

```
Still pushing directly to the default branch?
  → FIRST add a push trigger so direct commits are checked too:
      on: { pull_request: {...}, push: { branches: [main] } }
  → THEN, once everyone is PR-only, promote the job NAMES to required checks.
Already PR-only?
  → Promote required checks now.
```

### 4. Apply the safe governance wins via CLI

These are free and one `gh` call each. Outward-facing (they affect teammates), so confirm intent
first, then:

```bash
R=owner/repo
# Merge hygiene: squash-only, auto-delete merged branches, allow auto-merge
gh api -X PATCH repos/$R -F delete_branch_on_merge=true -F allow_auto_merge=true \
  -F allow_squash_merge=true -F allow_merge_commit=false -F allow_rebase_merge=false
# Dependabot alerts + security updates
gh api -X PUT repos/$R/vulnerability-alerts
gh api -X PUT repos/$R/automated-security-fixes
# Secret scanning + push protection (private repos need a paid security add-on; errors if absent)
gh api -X PATCH repos/$R --input - <<'JSON'
{"security_and_analysis":{"secret_scanning":{"status":"enabled"},"secret_scanning_push_protection":{"status":"enabled"}}}
JSON
```

Add a `.github/CODEOWNERS` (auto-requests review; tighten ownership on migrations/schema/`.github`)
and set org defaults so NEW repos start secure (`PATCH /orgs/{org}` →
`dependabot_alerts_enabled_for_new_repositories`, etc.).

### 5. Verify server-side; don't trust the command's exit code alone

```bash
gh api repos/$R --jq '{squash_only:(.allow_squash_merge and (.allow_merge_commit|not)),
  auto_delete:.delete_branch_on_merge, secret_scanning:.security_and_analysis.secret_scanning.status}'
```

## Change-Detection Gotchas (`--affected` / changed-set pipelines)

These don't show up until a PR that touches *nothing* in a given package — then they red a job that
has nothing to do with the change.

### Gotcha A — report/artifact steps that hard-error on missing output

A coverage-comment or artifact step gated on `always()` runs even when the changed-set produced no
output for that package, then dies on the missing file (`ENOENT …coverage-summary.json`) and fails
the whole job. Gate on the file existing instead:

```yaml
# WRONG — runs even when no coverage was produced, then errors
if: github.event_name == 'pull_request' && always()
# RIGHT — skips cleanly when the affected set produced nothing
if: github.event_name == 'pull_request' && hashFiles('apps/api/coverage/coverage-summary.json') != ''
```

### Gotcha B — base-ref resolution failure silently runs everything

`Failed to resolve base ref 'main' … fatal: ambiguous argument 'main'` means the change-detector
couldn't compute the diff base, so it falls back to **all packages**. The optimization silently
dies *and* unrelated, pre-existing failures surface on your PR. Ensure the base ref is fetched
(`fetch-depth: 0`, and the base branch ref actually present on the runner).

### Gotcha C — a bad file on the base reds EVERY open PR

PR builds check out the **PR-merged-with-base** ref. So a file that breaks the build once it's on
the base branch (e.g. a docs file missing required frontmatter for a docs-site content dir) reds
*every* open PR's build — not just the PR that introduced it. Fix the base; the PRs recover.

### Gotcha D — `gh run rerun` reuses the stale merge commit

Re-running a failed PR workflow does **not** recompute the merge against an updated base — it
replays the original merge commit. After fixing the base, **rebase the branch and push** to force
a fresh merge ref; don't `gh run rerun`.

### Gotcha E — schema widened, fixtures left behind

When a parse/validation test starts failing with "expected true, got false" after someone expanded
a schema, check the **producer** (the serializer/transform that builds the value) before deciding
the fix. If the producer always emits the new fields, the *test fixture* is stale (update it). If
the producer emits them only sometimes, the *schema* should be optional. Don't reflexively loosen
the schema — that can mask a real contract gap.

## Anti-Patterns

- **Optimizing a $0 bill.** If included-tier usage covers you, the win is *headroom and consistency*,
  not dollars. Say so; don't burn engineering time chasing a free invoice.
- **Requiring checks on a direct-push branch.** Deadlocks pushes (Rule 3).
- **Enabling a paid security feature without flagging cost.** Secret scanning on private repos is
  metered per active committer — name it before flipping it.
- **`gh run rerun` to pick up a base fix.** Replays the stale merge ref (Gotcha D).
- **Bundling unrelated work into a governance/CI PR.** Keep the PR coherent; commit unrelated
  in-tree changes separately.

## Audit Checklist

- [ ] Every `runs-on:` enumerated; metered stragglers moved to the standard pool (or justified)
- [ ] Scheduled crons reviewed for cadence + runner + duplication with uptime monitors
- [ ] The every-PR workflow caches its dependency install, keyed on the lockfile
- [ ] Branch ruleset reviewed: are required status checks set — and is the branch PR-only first?
- [ ] Merge hygiene: squash-only, auto-delete branch, auto-merge — applied and verified server-side
- [ ] Secret scanning + push protection: on (cost flagged if paid), Dependabot on every repo
- [ ] CODEOWNERS present; org defaults secure for new repos
- [ ] If `--affected`: report steps gated on `hashFiles`, base ref fetched, rerun→rebase understood
