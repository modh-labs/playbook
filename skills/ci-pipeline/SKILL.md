---
name: ci-pipeline
description: Enforce CI pipeline conventions. Use when adding CI checks, modifying GitHub Actions workflows, or discussing CI vs deployment. Prevents deployment steps in CI and ensures the extensible step pattern is followed.
tier: process
icon: workflow
title: "CI Pipeline Standards"
seo_title: "CI Pipeline Standards — Modh Engineering Skill"
seo_description: "Enforce CI pipeline conventions. Prevents deployment steps in CI and ensures the extensible step pattern is followed."
keywords: ["CI pipeline", "GitHub Actions", "continuous integration", "automation", "quality gates"]
difficulty: intermediate
related_chapters: []
related_tools: []
---

# CI Pipeline Skill

## When This Skill Activates

This skill automatically activates when you:
- Add or modify CI checks or steps
- Edit GitHub Actions workflow files
- Edit CI orchestration scripts
- Discuss deployment in the context of CI
- Add a new linting, testing, or validation step

## Architecture: CI vs Deployment

```
CI Pipeline (GitHub Actions / CI service)  ->  Quality gate ONLY
Deployment Platform (Vercel, Railway, etc.)  ->  All deployments
```

**NEVER** add deployment commands to CI. Your deployment platform handles deployment automatically via Git integration or its own pipeline. CI is exclusively for quality checks.

## Core Rules

### 1. Use an Extensible Step Pattern for New CI Checks

All CI steps should go in a central orchestration script (e.g., `scripts/ci.sh`) using a consistent step runner:

```bash
# Example: run_step function in scripts/ci.sh
run_step "My New Check" ./scripts/my-check.sh

# NOT inline in package.json
"ci": "... && ./scripts/my-check.sh && ..."
```

If your project uses a different pattern (Makefile, Turborepo pipeline, etc.), follow the existing convention. The principle is the same: one place to add steps, not scattered across config files.

### 2. Order Steps Cheapest-First

Steps run sequentially and fail fast. Put fast/cheap checks before slow/expensive ones:

```
1. Lint & Format (seconds)        <- cheapest
2. Convention checks (seconds)
3. Migration Safety Check (seconds)
4. TypeScript Typecheck (minutes)
5. Tests (minutes)                <- most expensive
```

### 3. Mirror Steps in GitHub Actions

Every step in your CI orchestration MUST have a corresponding step in the GitHub Actions workflow with:
- A descriptive `name:` matching the step name
- An `id:` for summary reporting
- The same command

```yaml
# CORRECT
- name: "My New Check"
  id: my-check
  run: ./scripts/my-check.sh

# WRONG -- missing id
- name: "My New Check"
  run: ./scripts/my-check.sh
```

### 4. Update the Summary Step

When adding a new check, add it to the summary step in the workflow:

```yaml
echo "| My New Check | ${{ steps.my-check.outcome == 'failure' && 'FAIL' || 'PASS' }} |" >> $GITHUB_STEP_SUMMARY
```

### 5. NEVER Add Deployments to CI

```yaml
# WRONG -- deployment in GitHub Actions
- name: Deploy to Production
  run: vercel --prod

# WRONG -- deploy script in CI
run_step "Deploy" npm run deploy
```

Deployment is handled by your deployment platform, not CI.

## Performance Rules

### Use efficient file searches in lint scripts

```bash
# WRONG -- walks into node_modules then filters (25s)
find . -name "X" -not -path "*/node_modules/*"

# RIGHT -- never enters node_modules at all (0.3s)
find . \( -path "*/node_modules" -o -path "*/.next" \) -prune -o -name "X" -print
```

### Enable incremental compilation

All `tsconfig.json` files MUST include `"incremental": true` for faster subsequent builds:

```json
{
  "compilerOptions": {
    "incremental": true
  }
}
```

### Enable build caching

If using a build orchestrator (Turborepo, Nx, etc.), enable caching for CI-related tasks.

## NEVER Rules

- NEVER add deploy commands (`vercel deploy`, `railway up`, etc.) to CI
- NEVER push directly to production branches without merging from the main branch first
- NEVER add deployment-related secrets (deploy tokens, etc.) to CI workflows
- NEVER inline new checks in `package.json` scripts -- use the orchestration script
- NEVER put expensive checks before cheap ones
- NEVER skip step IDs in GitHub Actions workflow steps
- NEVER use `continue-on-error: true` on quality gate steps (defeats the purpose)
- NEVER use `find -not -path` to exclude directories -- use `-prune` instead
- NEVER create a `tsconfig.json` without `"incremental": true`

## Adding a New CI Step -- Checklist

1. Create the check script (e.g., `scripts/my-check.sh`) or identify the command
2. Add the step to your CI orchestration script in the correct position (cheapest-first)
3. Add a matching step with `id:` to the GitHub Actions workflow
4. Add the step to the summary in the workflow
5. Update CI documentation if it exists
6. Test locally by running the full CI command

## Key Files (Adapt to Your Project)

| File | Purpose |
|------|---------|
| `scripts/ci.sh` | CI orchestration script (source of truth for steps) |
| `.github/workflows/ci.yml` | GitHub Actions workflow (mirrors steps for PR visibility) |
| CI documentation | Explains the architecture and step ordering |
