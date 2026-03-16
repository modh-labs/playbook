---
title: "CI Pipeline"
subtitle: "5-second CI that catches everything"
chapter: 6
section: "Architecture"
seo_title: "Fast CI Pipeline Design — Cheapest-First, Fail-Fast Patterns 2026"
seo_description: "Build a CI pipeline that runs in 5 seconds and catches lint, type, and test errors. Cheapest checks first, Turborepo caching, incremental TypeScript builds."
keywords: ["CI pipeline", "continuous integration", "Turborepo", "TypeScript", "Biome", "fast CI", "fail-fast"]
reading_time: "7 min"
difficulty: "intermediate"
tech_stack: ["Next.js", "Supabase", "TypeScript"]
business_case: "Developers who wait 10+ minutes for CI stop running it. A 5-second pipeline gets run before every commit, catching bugs before they reach production."
---

# CI Pipeline

> "The slower the CI, the less it gets used. The less it gets used, the more bugs reach production."

## The Problem

There's a threshold where CI goes from useful to ignored. Somewhere around two minutes, developers start pushing code without waiting for the result. At five minutes, they stop running it locally entirely. At ten minutes, the CI badge on the README is a decoration.

We've watched teams build elaborate CI pipelines — parallel jobs, matrix builds, integration tests, end-to-end tests, Lighthouse audits — that take fifteen minutes to complete. The pipeline catches everything. It also catches no one's attention, because no one waits for it.

The failure mode is predictable. A developer pushes a change, context-switches to another task, and doesn't notice the CI failure until the next morning. By then, two more PRs have stacked on top. The fix requires rebasing, re-reviewing, and re-running the full pipeline. An error that would have taken thirty seconds to fix in context now takes thirty minutes to untangle.

The opposite extreme is equally broken: no CI at all, or CI that only runs linting. The team moves fast right up until the moment they deploy a type error to production, or a regression that would have been caught by a three-line test.

The goal isn't comprehensive CI or fast CI. It's comprehensive CI that's fast enough to actually use.

## The Principle

Order checks from cheapest to most expensive. Fail fast. Cache aggressively.

A lint error takes two seconds to detect. A type error takes eight seconds. A test failure takes fourteen seconds. If you run tests first, you waste fourteen seconds before discovering a formatting issue that Biome would have caught in one second.

The cheapest checks act as filters. If formatting is wrong, there's no point checking types. If types are wrong, there's no point running tests. Each layer only runs if the previous layer passed, and the total time is dominated by the most expensive check that actually runs — which, in the common case (everything passes), is the full pipeline.

## The Pattern

### The pipeline: four steps, five seconds

```
Developer pushes code
    |
    +---> Lint & Format (Biome)        ~1 second
    |     Catches: style, formatting, import issues
    |
    +---> Convention Checks            ~1 second
    |     Catches: missing required files, naming violations
    |
    +---> TypeScript Typecheck         ~3-8 seconds (incremental)
    |     Catches: type errors across the monorepo
    |
    +---> Unit & Integration Tests     ~5-14 seconds
          Catches: logic errors, regressions
```

Total: under 5 seconds on a warm cache, under 30 seconds cold. Fast enough to run before every commit.

### A shell script, not a package.json chain

CI orchestration lives in a shell script with a step runner. Each step gets a name, timing, and fail-fast behavior. This replaces the opaque `"ci": "cmd1 && cmd2 && cmd3"` pattern that gives you no visibility into what failed or how long each step took.

```bash
#!/usr/bin/env bash
set -euo pipefail

STEPS=()
RESULTS=()
TOTAL_START=$(date +%s)

run_step() {
  local name="$1"
  shift
  local start=$(date +%s)

  echo "==> $name"
  if "$@"; then
    local duration=$(($(date +%s) - start))
    STEPS+=("$name")
    RESULTS+=("PASS (${duration}s)")
  else
    local duration=$(($(date +%s) - start))
    STEPS+=("$name")
    RESULTS+=("FAIL (${duration}s)")
    # Print summary so far, then exit
    print_summary
    exit 1
  fi
}

# Cheapest first
run_step "Lint & Format"          npx biome check .
run_step "Convention Checks"      ./scripts/lint-conventions.sh
run_step "TypeScript Typecheck"   npx turbo typecheck
run_step "Unit & Integration"     npx turbo test:ci

print_summary
```

### Incremental TypeScript builds

TypeScript's incremental mode caches type information between runs using `.tsbuildinfo` files. On a warm cache, typecheck drops from 9 seconds to 3 seconds — a 67% improvement for zero effort.

```json
// tsconfig.json
{
  "compilerOptions": {
    "incremental": true,
    "noEmit": true
  }
}
```

```json
// turbo.json
{
  "tasks": {
    "typecheck": {
      "cache": true,
      "outputs": ["*.tsbuildinfo"]
    }
  }
}
```

Every package in the monorepo must include `"incremental": true`. One missing config and that package re-typechecks from scratch every time.

### Turborepo caching

Turborepo caches task results by input hash. If no source files changed since the last run, the task replays its cached output in under a second.

```json
// turbo.json
{
  "tasks": {
    "typecheck": {
      "cache": true,
      "outputs": ["*.tsbuildinfo"]
    },
    "test:ci": {
      "cache": true
    }
  }
}
```

Remote caching shares results across machines. A developer's local CI run can benefit from a teammate's cache, and vice versa.

```yaml
# .github/workflows/ci.yml
env:
  TURBO_TOKEN: ${{ secrets.TURBO_TOKEN }}
  TURBO_TEAM: ${{ vars.TURBO_TEAM }}
```

### CI mirrors local exactly

The GitHub Actions workflow runs the same steps in the same order as the local script. What passes locally passes in CI. No surprises.

```yaml
# .github/workflows/ci.yml
jobs:
  quality:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: oven-sh/setup-bun@v2

      - name: Install dependencies
        run: bun install --frozen-lockfile

      - name: Lint & Format
        id: lint
        run: npx biome check .

      - name: TypeScript Typecheck
        id: typecheck
        run: npx turbo typecheck

      - name: Unit & Integration Tests
        id: tests
        run: npx turbo test:ci

      - name: Summary
        if: always()
        run: |
          echo "| Check | Result |" >> $GITHUB_STEP_SUMMARY
          echo "|-------|--------|" >> $GITHUB_STEP_SUMMARY
          echo "| Lint | ${{ steps.lint.outcome }} |" >> $GITHUB_STEP_SUMMARY
          echo "| Types | ${{ steps.typecheck.outcome }} |" >> $GITHUB_STEP_SUMMARY
          echo "| Tests | ${{ steps.tests.outcome }} |" >> $GITHUB_STEP_SUMMARY
```

### One job, not many

Separate CI jobs (lint job, type job, test job) run in parallel but each needs its own setup — checkout, install, cache hydration. For a pipeline under 30 seconds total, sequential steps in one job are faster because setup runs once and the Turborepo cache is shared across steps.

If your pipeline grows beyond 10 minutes, split into parallel jobs. Until then, one job with fail-fast ordering is simpler and faster.

### What not to do

| Anti-pattern | Problem | Do this instead |
|-------------|---------|-----------------|
| Inline `package.json` ci script | No step names, no timing, opaque failures | Shell script with `run_step` |
| Tests before linting | Wastes 14s before catching a 1s lint error | Cheapest checks first |
| `continue-on-error: true` | Silently passes broken builds | Let failures fail |
| Build verification on every commit | 6x slower CI for checks Vercel does anyway | Optional `ci:build` for risky PRs |
| Separate jobs under 10min total | Setup overhead exceeds parallelism benefit | One job, sequential steps |

## The Business Case

- **CI that actually gets used.** A 5-second pipeline runs before every commit. A 15-minute pipeline runs once a day, maybe. The difference in bug detection rate is enormous.
- **Faster PR cycle time.** Developers get feedback while the change is still in their working memory. Fix-in-context takes seconds; fix-after-context-switch takes minutes.
- **Lower CI costs.** Turborepo caching and incremental builds mean most CI runs do almost no work. Cache hits are free compute.

## Try It

Install the Modh Playbook skills to enforce this pattern automatically:
```bash
# Add to your project
git submodule add https://github.com/modh-labs/playbook .agents/modh-playbook
./.agents/modh-playbook/install.sh
```
