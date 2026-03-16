---
name: code-quality-audit
description: >
  Systematic audit and remediation of a route or module to production-grade quality.
  Use when auditing for SOLID violations, missing error handling, type safety gaps,
  dead code, duplicated patterns, or insufficient test coverage. Also use when
  remediating code to gold-standard clean architecture.
tier: backend
icon: search-code
title: "Code Quality Audit"
seo_title: "Code Quality Audit — Modh Engineering Skill"
seo_description: "Systematic audit and remediation of a route or module to production-grade quality. Use when auditing for SOLID violations, missing error handling, and type safety gaps."
keywords: ["code quality", "audit", "SOLID", "clean architecture", "refactoring"]
difficulty: advanced
related_chapters: []
related_tools: []
---

# Code Quality Audit

Systematic audit and remediation to production-grade quality: SOLID architecture, clean separation of concerns, observability, type safety, test coverage, and DRY code.

## When to Use

- Module has fat files doing too many things (>500 lines)
- Cross-layer violations (actions calling database directly, skipping the repository/service layer)
- `as any` type casts, `@ts-nocheck`, `console.error` instead of structured logging
- Missing or wrong-domain error captures
- <50% test coverage on business-critical paths
- Duplicated patterns across 3+ files
- Dead code lingering from past refactors

---

## Step 0 (BEFORE anything else): Detect Parallel Systems

**Before splitting or refactoring, check if a gold-standard implementation already exists elsewhere.**

Many codebases evolve a second system alongside the original. The new system has proper architecture; the old has active consumers. Splitting the old code into smaller files of still-bad code is wasted effort.

### Detection checklist

```bash
# Check for parallel action/handler directories
ls {module}/actions/ {module}/_actions/ {module}/handlers/ {module}/_handlers/ 2>/dev/null

# Compare exports - find overlapping functionality
grep "^export" {module}/old-system/*.ts {module}/new-system/*.ts

# Find who actually imports from the old system
grep -rn "from.*old-system" {module}/ --include="*.tsx" | grep -v __tests__
```

### Decision tree

1. **Old code has equivalent in new system** -> Migrate consumer to new version, delete old code
2. **Old code has no equivalent** -> Move to new system directory, upgrade to gold-standard patterns
3. **Old code is unused** -> Delete immediately (verify with grep first)

**The lesson:** Don't polish bad code. Find the good code and route consumers to it.

---

## Audit Checklist

For every action/handler file in the module, check:

| Check | What to look for |
|-------|-----------------|
| Tracing wrapper | Is the export wrapped with a tracing function? |
| Domain-specific error capture | Uses the correct domain capture, not bare exception handlers or borrowed captures? |
| Structured logging | Uses a module logger, not `console.error/log`? |
| Input validation | Validated with a schema (Zod, etc.) before any operations? |
| Cache/state invalidation | Uses a helper or consistent pattern after mutations? |
| Type safety | No `as any`, no `@ts-nocheck`? |
| PII safety | No emails/phones in error tags (only in non-indexed metadata)? |
| Test coverage | Has tests with auth, validation, happy path, and error cases? |
| Dead code | No COMPAT blocks, unused vars, stale imports, dangling JSDoc? |

---

## SOLID & Clean Architecture Audit

### S - Single Responsibility

Each file should have ONE reason to change.

| Smell | Fix |
|-------|-----|
| File >500 lines | Split into focused files, one per operation |
| Function does DB + business logic + notifications + cache | Extract to service layer or use repository pattern |
| Component renders + fetches + manages complex state | Split into data layer + presentation layer |

### O - Open/Closed

Extend behavior without modifying existing code.

| Pattern | Example |
|---------|---------|
| Error capture factory | New domain = new file, zero changes to factory |
| Tracing wrapper | New tracing = wrap function, zero changes to business logic |
| Tag/metric registries | New domain = add constants, existing domains untouched |

### L - Liskov Substitution

| Smell | Fix |
|-------|-----|
| `as any` to force-fit a type | Use type guards, proper narrowing, or generics |
| `@ts-nocheck` to skip type checking | Remove, fix each error with targeted assertions |
| Function returns different shapes per branch | Define union return type or normalize to consistent shape |

### I - Interface Segregation

| Smell | Fix |
|-------|-----|
| Params object with 20+ optional fields | Split into focused param types |
| Component props with 15+ fields | Use compound component pattern |
| Function that accepts options it ignores | Remove unused params or split into focused functions |

### D - Dependency Inversion

```
Actions -> Services -> Repositories -> Database    CORRECT
Actions -> database.query("table")                 WRONG (skipping layers)
Module -> generic captureException                 WRONG (should use domain capture)
Module -> wrong-domain captureException            WRONG (cross-domain coupling)
```

### Clean Architecture Layers

```
UI Layer (pages, components)     Fetch data, handle interactions
Action Layer (mutations)         Orchestrate: validate -> service/repo -> invalidate cache
Service Layer (business logic)   Complex logic spanning multiple repositories
Repository Layer (data access)   Single-table CRUD, typed returns
External (DB, APIs)              Never accessed directly above repository layer
```

**Rules:**
- Dependencies point DOWN only
- Cross-cutting concerns (logging, tracing, error capture) are injected via wrappers, not scattered inline

---

## Business Logic & JTBD Validation

**This is the most important audit.** Clean code means nothing if the feature doesn't do what it's supposed to do.

### Step 1: Understand the Job-to-be-Done

1. **Who is the user?**
2. **What job are they hiring this code for?**
3. **What's the critical path?** (3-5 steps that MUST work)
4. **What's the failure mode?** (lost revenue? missed follow-up? data corruption?)

### Step 2: Trace the critical path end-to-end

```
User action
  -> Validate input
  -> Call service/repository
  -> Process result
  -> Trigger side effects (notifications, webhooks, audit log)
  -> Invalidate cache
  -> Return fresh data to UI
```

At each step: What if this fails? Is the error caught? Does the user see a meaningful message? Is the system left in a consistent state?

### Business Logic Red Flags

- Validates input but doesn't verify ownership (authorization bypass)
- Mutation succeeds but doesn't invalidate related caches (stale UI)
- Side effects fire before DB commit (data inconsistency)
- No idempotency on retryable operations (duplicates)
- Status transition allows invalid states
- Financial calculation uses floating point instead of integer cents
- Return type says success but operation was never awaited

---

## Remediation Steps (in order)

1. **Detect parallel systems** - Find and migrate before splitting
2. **Domain error capture** - Create/use domain-specific capture function
3. **Wrap with tracing** - Add tracing wrapper to all exports
4. **Security audit** - No PII in error tags, proper authorization
5. **Type safety** - Eliminate `as any`, use type guards
6. **DRY extraction** - Consolidate patterns duplicated in 3+ files
7. **Unit tests** - Auth, validation, happy path, error handling
8. **Verify** - Typecheck, lint, all tests pass

---

## Validating Against Production Data

Before removing "legacy" format handling:

1. **Query production** to verify zero records in old format
2. **Check if writers still produce old format** - recent records matter more than count
3. **If old format still being written** - fix the writer first, then remove reader fallbacks

```sql
-- Example: verify no legacy format data exists
SELECT COUNT(*) FROM records
WHERE data IS NOT NULL
  AND data != '{}'::jsonb
  AND jsonb_typeof(data) = 'object';
-- Must return 0 before removing object-format handling
```

---

## Common Mistakes

| Mistake | Fix |
|---------|-----|
| Splitting a god file without checking for parallel systems | Detect gold-standard equivalents before any refactoring |
| Using `as any` to "fix" JSONB types | Use type guards or `as Record<string, unknown>` |
| Removing "legacy" handling without checking production data | Run verification queries - data may still exist |
| Adding tracing without updating existing tests | Tests need mock for tracing wrapper |
| Moving search from in-memory to DB without fixing pagination | In-memory search after pagination misses results on other pages |
