---
name: pull-request
description: Create pull requests with mandatory CI validation, unit tests, and rich descriptions. Use when creating PRs, submitting code for review, or pushing changes. Runs CI before any PR and blocks creation on failure. Uses standard git + gh CLI for branching and PR creation.
tier: process
icon: git-pull-request
title: "Pull Request Conventions"
seo_title: "Pull Request Conventions — Modh Engineering Skill"
seo_description: "Create pull requests with mandatory CI validation, unit tests, and rich descriptions. Runs CI before any PR and blocks creation on failure."
keywords: ["pull request", "code review", "CI validation", "git workflow", "PR description"]
difficulty: beginner
related_chapters: []
related_tools: []
---

# Pull Request Skill

## When This Skill Activates

This skill automatically activates when you:
- Create a pull request
- Are asked to submit code for review
- Need to push and open a PR
- Use `/pr` command

## Critical Gates (All Must Pass)

1. **Unit tests exist** for changed code (unless exempted -- see below)
2. **CI pipeline passes** with zero errors
3. **PR description is rich and detailed** (not a stub)

## Workflow

### Step 0: Ensure Unit Tests Exist (Mandatory)

Before running CI, verify that tests exist for the code being changed:

```bash
# Check for test files near changed source files
git diff --name-only main...HEAD | grep -v __tests__ | head -20
```

**For each changed source file**, there SHOULD be a corresponding test file:

```
src/features/calls/cancel-call.ts
  -> src/features/calls/__tests__/cancel-call.test.ts

src/lib/repositories/leads.repository.ts
  -> src/lib/repositories/__tests__/leads.repository.test.ts
```

**If tests are missing**: Write them before proceeding.

**Exemptions** (tests not required):
- Pure UI/layout changes (loading states, error boundaries, CSS-only)
- Config file changes (bundler config, linter config)
- Documentation-only changes (markdown files)
- Type-only changes (type definitions, generated types)
- Generated files (migrations, code generation output)
- Skill files (AI agent skills)

### Step 1: Run CI (Mandatory -- Hard Gate)

Run your project's CI command (e.g., `npm run ci`, `bun run ci`, `make ci`).

This typically runs: lint + typecheck + tests.

**If CI fails:**
1. Read the error output carefully
2. Fix ALL failures (lint, type errors, test failures)
3. Stage and commit the fixes
4. Re-run CI
5. Only proceed when CI passes with **zero errors**

**Do NOT:**
- Skip CI with `--no-verify` or similar flags
- Create the PR anyway with "will fix in follow-up"
- Only run part of CI (e.g., just tests without typecheck)

### Step 2: Gather Context from Issue Tracker

If the branch name contains an issue ID (e.g., `fix/ISSUE-401-csv-import-timeout`), look up the issue to understand:
- **Title** -- use for PR title context
- **Description** -- understand the original problem statement
- **Acceptance criteria** -- reference in test plan
- **Labels** -- map to PR label (Bug, Feature, Improvement)
- **Related/blocking issues** -- mention in PR description if relevant

### Step 3: Ensure Changes Are Committed

```bash
git status
```

If there are uncommitted changes, commit them following conventional commits:
- Format: `type(scope): description`
- Types: `feat`, `fix`, `perf`, `refactor`, `test`, `docs`, `chore`, `ci`

### Step 4: Craft Rich PR Description

**The PR description is a first-class artifact.** It should be detailed enough that a reviewer understands the full context without reading the code first.

Use this template, adapting sections based on PR complexity:

````markdown
## Summary

<2-5 sentences explaining what this PR does and **why**. Reference the issue context.>

### Problem

<What was broken or missing? Quote from the issue if helpful.>

### Solution

<How does this PR solve it? Explain the approach, not just "fixed it".>

## Changes

| File | Change |
|------|--------|
| `path/to/file.ts` | Added validation for edge case X |
| `path/to/other.ts` | Refactored to use repository pattern |

## User Journey

<How does the user experience this change? Walk through the flow step by step.>

```mermaid
sequenceDiagram
    participant U as User
    participant App as Application
    participant API as Backend
    participant DB as Database
    U->>App: [What the user does]
    App->>API: [What the app triggers]
    API->>DB: [What gets persisted]
    DB-->>App: [What comes back]
    App-->>U: [What the user sees]
```

## Architecture

<Include when the PR changes data flow, adds new patterns, or modifies architecture.>

```mermaid
graph LR
    A[User Action] --> B[Server Action]
    B --> C[Repository]
    C --> D[Database]
```

## Edge Cases Addressed

<What boundary conditions does this PR handle? List the scenarios you considered.>

- <Edge case 1 -- e.g., "Empty state: no data exists yet">
- <Edge case 2 -- e.g., "Large dataset: 500+ items">
- <Edge case 3 -- e.g., "Error state: external API timeout">
- <Not handled (follow-up): describe any known gaps>

## Testing

### Automated
- [x] Unit tests added/updated (`__tests__/*.test.ts`)
- [x] CI pipeline passes locally

### Manual
- [ ] <Step-by-step manual verification if applicable>
- [ ] <Edge case: describe specific scenario>

## Screenshots

<Include before/after screenshots for UI changes. Omit for backend-only.>

| Before | After |
|--------|-------|
| <screenshot> | <screenshot> |

## Issue Reference

Fixes: ISSUE-XXX

> **Issue:** <Title from tracker>
> **Labels:** <Bug/Feature/Improvement>

## Notes for Reviewers

<Any context that helps review: trade-offs made, things you considered but rejected, known limitations, follow-up work needed.>
````

### Section Usage Guide

| Section | When to Include |
|---------|----------------|
| Summary + Problem + Solution | **Always** |
| Changes table | 3+ files changed |
| User Journey | Any user-facing change (UI or behavior) |
| Architecture / Mermaid diagrams | New patterns, data flow changes, multi-service interactions |
| Edge Cases Addressed | Any feature or bug fix (list what you handled + what you didn't) |
| Screenshots | Any UI change |
| Notes for Reviewers | Trade-offs, known limitations, follow-ups |

### Mermaid Diagram Cheat Sheet

Use diagrams when they clarify architecture better than prose:

```markdown
<!-- Data flow -->
graph LR / graph TD

<!-- Multi-step interactions -->
sequenceDiagram

<!-- State transitions -->
stateDiagram-v2

<!-- Decision logic -->
flowchart TD
    A{Condition?} -->|Yes| B[Action]
    A -->|No| C[Other]
```

### Step 5: Push and Create PR

```bash
# Push current branch to remote
git push -u origin HEAD

# Create PR with rich description
gh pr create --title "type(scope): description" --body "$(cat <<'EOF'
<paste rich body here>
EOF
)"
```

### Step 6: Verify PR Was Created

```bash
gh pr view --web
```

## PR Title Format

Follow conventional commits -- keep under 70 characters:

```
feat(scheduler): add buffer time between bookings
fix(billing): prevent duplicate subscription on upgrade
refactor(webhooks): extract handler registry pattern
test(calls): add unit tests for cancel flow
```

## Decision Tree

```
Ready to create PR?
|
|-- Tests exist for changed code?
|   |-- YES -> Continue
|   |-- EXEMPT -> Continue (UI/config/docs/types/generated)
|   |-- NO -> Write tests first
|
|-- Run CI
|   |-- PASS -> Continue
|   |-- FAIL -> Fix -> Re-run -> Loop
|
|-- Fetch issue context (if available)
|   |-- Extract title, description, labels, relations
|
|-- All changes committed?
|   |-- YES -> Continue
|   |-- NO -> Commit first
|
|-- Craft rich PR description
|   |-- Summary + Problem + Solution + Changes + Diagrams + Testing
|
|-- Create PR via gh pr create
```

## Anti-Patterns

```bash
# Creating PR without CI
gh pr create  # Without running CI first!

# PR with no tests for new logic
gh pr create --title "feat: add booking validation"  # Where are the tests?

# Stub PR description
--body "Fixed the thing"  # Not enough context!

# Missing issue context
# Not looking up the issue to understand acceptance criteria

# Skipping diagrams for architectural changes
# A 3-paragraph prose explanation when a mermaid diagram would be clearer
```

## Quick Reference

| Step | Action | Required? |
|------|--------|-----------|
| Check tests exist | Verify test files exist | **YES** (unless exempt) |
| Run CI | Project CI command | **YES -- MANDATORY** |
| Fetch issue | Look up issue details | Yes (if ID available) |
| Check status | `git status` | Yes |
| Commit | `git commit` (conventional) | If needed |
| Write description | Rich markdown + diagrams | **YES** |
| Create PR | `gh pr create` | Yes |
| Verify | `gh pr view` | Yes |
