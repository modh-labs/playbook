---
name: code-review
description: >
  Run educational code reviews against your project's quality standards.
  Use when reviewing PRs, checking current branch before pushing, or doing
  batch quality sweeps across all open PRs. Applies observability, testing,
  SOLID, type safety, security, business logic, and clean code checks with
  pass/fail verdicts. Produces actionable findings with real-world impact
  explanations, not just "best practice" citations.
tier: universal
icon: search-check
title: "Code Review"
seo_title: "Code Review — Modh Engineering Skill"
seo_description: "Educational code review skill for AI agents. Seven review dimensions, pass/fail verdicts, and actionable findings with real-world impact explanations."
keywords: ["code review", "pull request review", "quality audit", "SOLID", "observability", "security", "type safety"]
difficulty: intermediate
related_chapters: ["code-quality-audit", "testing-strategy", "typescript-strict"]
related_tools: ["code-quality-audit", "pull-request", "testing", "security-and-compliance", "observability"]
---

# Code Review

Educational code review that applies your project's quality standards to diffs. Every finding explains what is wrong, why it matters (product/compliance/reliability context), and exactly how to fix it. Produces a pass/fail verdict.

## When This Skill Activates

- User invokes `/review`
- User asks to "review", "check", or "audit" code changes or PRs
- User wants a quality sweep before merging

## Invocation Modes

| Command | Mode | Diff Source | Output |
|---------|------|-------------|--------|
| `/review` | Current branch | `git diff main...HEAD` | Terminal report |
| `/review 423` | Single PR | `gh pr diff 423` | Terminal + GitHub PR review |
| `/review --prs` | All open PRs | `gh pr list` then loop | Terminal summary + GitHub PR reviews |

---

## Review Dimensions

Seven categories. Critical findings auto-fail the review.

### 1. Observability

| Check | Critical? | What to look for |
|-------|-----------|-----------------|
| Structured logging | Yes | Uses your project's logger, not `console.log/error` |
| Error tracking integration | Yes | Errors captured with domain context, not bare `catch` blocks that swallow |
| PII in error tags | Yes | No emails, phones, names in searchable error tags (use metadata/context) |
| Tracing wrappers | No | Exported functions wrapped with tracing/instrumentation |
| Wide events | No | Prefer fewer, attribute-rich logs over many thin logs |
| Span naming | No | Follows consistent naming convention (`db.*`, `http.*`, `function.*`) |

### 2. Testing

| Check | Critical? | What to look for |
|-------|-----------|-----------------|
| Test file exists | Yes | New/changed logic files must have corresponding tests |
| Auth test case | Yes | Tests unauthorized access (no user, no org/tenant) |
| Validation test case | Yes | Tests invalid input (bad schema, missing required fields) |
| Happy path test | Yes | Tests success case with correct service/repo calls |
| Error handling test | No | Tests failure paths, error propagation |
| Mock structure | No | Uses hoisted mocks, proper type assertions |

**Exemptions** (tests not required):
- Pure UI/layout changes (loading states, error boundaries, CSS-only)
- Config file changes (bundler, linter, formatter configs)
- Documentation-only changes (`*.md`)
- Type-only changes (type definitions, generated types)
- Generated files (migrations, code generation output)
- Skill files (agent skills, prompt files)

### 3. SOLID Architecture

| Check | Critical? | What to look for |
|-------|-----------|-----------------|
| Layer violation | Yes | Business logic calls database directly (must use service/repository layer) |
| Cross-boundary import | Yes | Module imports internals from another module's directory |
| Wrong domain coupling | Yes | Module uses error handling/services from wrong domain |
| God file | No | File >500 lines, should split by responsibility |
| Side effect mixing | No | One function does DB + email + webhook + cache |
| Dependency direction | No | Dependencies point UP instead of DOWN |

### 4. Type Safety

| Check | Critical? | What to look for |
|-------|-----------|-----------------|
| `as any` | Yes | Use `as Record<string, unknown>` or proper type guards |
| `@ts-nocheck` | Yes | Remove, fix each error with targeted assertions |
| Untyped parameters | No | Function parameters should have explicit types |
| `@ts-ignore` | No | Replace with `@ts-expect-error` and a comment |

### 5. Security & PII

| Check | Critical? | What to look for |
|-------|-----------|-----------------|
| PII in logs/tags | Yes | Emails, phones, names must be in metadata, not searchable tags |
| Missing input validation | Yes | Server/API inputs must be validated with a schema (Zod, etc.) |
| Authorization bypass risk | Yes | Validates input but doesn't verify ownership/permissions |
| Hardcoded secrets | Yes | API keys, tokens, passwords in source code |
| SQL injection | Yes | Raw string interpolation in queries |

### 6. Business Logic

| Check | Critical? | What to look for |
|-------|-----------|-----------------|
| Missing cache invalidation | Yes | Mutation without cache bust / revalidation |
| Side effects before commit | Yes | Email/webhook fires before DB write is confirmed |
| Missing error return | No | Catch block doesn't return error to caller |
| Race condition risk | No | Concurrent access without optimistic locking |
| Stale data after mutation | No | UI doesn't refresh after successful mutation |

### 7. Clean Code

Advisory only, never auto-fails.

| Check | Critical? | What to look for |
|-------|-----------|-----------------|
| Dead code | No | Commented-out code, unused imports, stale compatibility shims |
| Duplicated patterns | No | Same pattern in 3+ files, extract helper |
| Console statements | No | `console.log/warn/error` left in (should be structured logger) |
| Naming | No | Unclear variable/function names |

---

## Finding Format

Every finding MUST follow this template:

```
### [Category] Finding Title

**What:** `file:line` -- one-line description
**Why it matters:** Product/compliance/reliability impact (never just "best practice")
**How to fix:**
  <concrete code example or step-by-step>
**Standard:** dimension name, specific check reference
**Severity:** Critical | Important | Advisory
```

### Writing "Why it matters"

This is what makes the review educational. Always ground in real consequences:

| Category | Bad "Why" | Good "Why" |
|----------|-----------|------------|
| Observability | "You should use structured logging" | "Bare console.log is invisible to your error tracker. When this fails at 2 AM, no alert fires and no one knows until a customer reports it" |
| Testing | "Missing test coverage" | "This function handles payment state. Untested payment logic is how you get duplicate charges in production" |
| SOLID | "Violates single responsibility" | "This 600-line file means 3 developers will have merge conflicts every sprint when touching unrelated features" |
| Security | "Should validate input" | "Without schema validation, a malformed tenant ID could bypass authorization and leak data across accounts" |

---

## Verdict

After all findings are collected, compute the verdict:

```
======================================================
  REVIEW VERDICT: [APPROVED | CHANGES REQUESTED | NEEDS DISCUSSION]
======================================================
  Critical:  N findings (must fix)
  Important: N findings (should fix)
  Advisory:  N findings

  Breakdown:
    Observability   Pass | Fail
    Testing         Pass | Fail
    SOLID           Pass | Fail
    Type Safety     Pass | Fail
    Security & PII  Pass | Fail
    Business Logic  Pass | Fail
    Clean Code      Pass (always passes, advisory only)
======================================================
```

Rules:
- **APPROVED** -- Zero critical findings
- **CHANGES REQUESTED** -- 1+ critical findings
- **NEEDS DISCUSSION** -- Zero critical but 5+ important findings

---

## Workflow

### Step 1: Get the Diff

```bash
# Branch mode
git diff main...HEAD --name-only   # List changed files
git diff main...HEAD               # Full diff

# PR mode
gh pr diff 423 --name-only
gh pr diff 423

# All PRs mode
gh pr list --state open --json number,title,author
# Then loop through each
```

### Step 2: Classify Changed Files

For each changed file, determine which dimensions apply:

| File Pattern | Dimensions to Check |
|-------------|-------------------|
| Actions, handlers, controllers | All 7 dimensions |
| Repository/service/data-access files | Type Safety, Clean Code |
| Test files (`*.test.*`, `*.spec.*`) | Clean Code only |
| Page/layout/route entry points | SOLID, Type Safety, Clean Code |
| UI components | SOLID, Type Safety, Clean Code |
| Config, docs, styles (`*.md`, `*.json`, `*.css`) | Skip review |
| Generated files (migrations, types) | Skip review |

### Step 3: Review Each File

For each non-skipped file:
1. Read the FULL file (not just the diff -- you need context)
2. Read the diff to identify what changed
3. Run applicable dimension checks against the changed code
4. Collect findings with exact file:line references

### Step 4: Compute Verdict

Aggregate all findings across all files. Apply verdict rules.

### Step 5: Output

**Terminal (all modes):** Print formatted report with findings grouped by dimension, then verdict.

**GitHub (PR modes):** Post as a single PR review via `gh api`:

```bash
gh api repos/{owner}/{repo}/pulls/{pr}/reviews \
  --method POST \
  -f body="<verdict summary>" \
  -f event="REQUEST_CHANGES" \
  -f 'comments=[{"path":"file.ts","line":45,"body":"finding"}]'
```

Use `REQUEST_CHANGES` when verdict is CHANGES REQUESTED, `APPROVE` when APPROVED, `COMMENT` when NEEDS DISCUSSION.

**Max 15 inline comments per PR.** Group related findings if there are more.

---

## Anti-Patterns

| Anti-Pattern | Why It's Wrong |
|-------------|---------------|
| "This violates best practices" | Always explain the REAL impact |
| Reviewing generated files | Skip migrations, type generation, lock files |
| Reviewing test files for business logic | Tests follow their own patterns |
| Posting 50+ comments on one PR | Group related findings, max 15 comments |
| Blocking on advisory findings | Only critical findings produce CHANGES REQUESTED |
| Reviewing code you didn't read fully | Always read the full file, not just the diff |
| Reviewing non-logic files | Skip `.md`, `.json`, `.css`, config files |

---

## Relationship to Other Skills

| Skill | How It Relates |
|-------|---------------|
| `code-quality-audit` | Deep audit of a single module. Use `/review` for PR-scoped checks, `code-quality-audit` for full-module remediation |
| `pull-request` | Creates PRs. `/review` reviews them. Run `/review` before `/pr` to catch issues early |
| `testing` | Defines test patterns. `/review` checks that those patterns are followed |
| `security-and-compliance` | Defines security rules. `/review` enforces them at PR time |
| `observability` | Defines logging/tracing patterns. `/review` checks compliance |
