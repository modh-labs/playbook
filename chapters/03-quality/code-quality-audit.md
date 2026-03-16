---
title: "Code Quality Audit"
subtitle: "Systematic route audits that find dead code, wrong abstractions, and missing tests"
chapter: 9
section: "Quality"
seo_title: "Code Quality Audit — SOLID Architecture Audits for TypeScript SaaS — 2026"
seo_description: "Production-grade code quality audit methodology: detect parallel systems, apply SOLID principles, validate business logic against production data, and eliminate dead code systematically."
keywords: ["code audit", "SOLID principles", "dead code detection", "clean architecture", "TypeScript refactoring", "code quality", "technical debt"]
reading_time: "12 min"
difficulty: "advanced"
tech_stack: ["Next.js", "TypeScript", "Supabase", "Sentry", "Vitest"]
business_case: "Systematic audits prevent the accumulation of dead code, wrong-domain error captures, and legacy fallback mechanisms. One audit session can delete thousands of lines while improving observability and test coverage."
---

# Code Quality Audit

Most codebases don't need more code. They need less code that does the right thing.

A code quality audit is a systematic process for bringing a module to production-grade quality. Not by adding features, but by removing waste: dead code, wrong abstractions, duplicated patterns, and missing safety nets.

## The Core Insight: Detect Before You Split

The most common audit mistake is splitting a 2,000-line god file into six smaller files of equally bad code. Before touching anything, check if a gold-standard implementation already exists elsewhere in the module.

Many codebases evolve naturally: someone builds a proper system alongside the original, migrates a few consumers, then moves on. The old system lingers with active imports. The audit's first job is to find these parallel systems and route consumers to the better one.

### Detection Protocol

```bash
# Check for parallel directories
ls module/actions/ module/_actions/ 2>/dev/null

# Compare exports - find overlap
grep "^export" module/old/*.ts module/new/*.ts

# Find actual consumers of the old system
grep -rn "from.*old-system" module/ --include="*.tsx" | grep -v __tests__
```

**Decision tree:**
1. Old code has equivalent in new system -> Migrate consumer, delete old
2. Old code has no equivalent -> Move to new system, upgrade patterns
3. Old code has no consumers -> Delete immediately

### Real Example

A 2,155-line `actions.ts` file was split into 6 focused files. An audit then discovered the module already had a `_actions/` directory with gold-standard equivalents for 9 of 15 actions. Result:

- 9 actions: **Deleted** (consumers already pointed to new system)
- 4 actions: **Moved** to new system with upgraded patterns
- 2 actions: **Already gold-standard**
- Net: **1,612 lines of dead code removed**, zero functionality lost

The mechanical split was a stepping stone. The audit was the real work.

## The Audit Checklist

For every action, handler, or service function:

| Check | What to look for |
|-------|-----------------|
| **Tracing** | Is the export wrapped with a tracing function? |
| **Error capture** | Uses domain-specific capture, not bare handlers or wrong-domain captures? |
| **Structured logging** | Module-specific logger, not console.error? |
| **Input validation** | Schema validation before any operations? |
| **Cache invalidation** | Consistent pattern after mutations? |
| **Type safety** | No `as any`, no `@ts-nocheck`? |
| **PII safety** | No emails/phones in error tags? |
| **Test coverage** | Auth, validation, happy path, error cases? |
| **Dead code** | No unused exports, dangling JSDoc, stale imports? |

## SOLID in Practice

### Single Responsibility

The symptom is always the same: a file that's too big. But "split it" isn't the fix. Understanding *why* it's big is.

- File does DB + business logic + notifications + cache -> Extract service layer
- File handles 5 unrelated operations -> Split by operation, one file each
- Component fetches + renders + manages state -> Server Component for data, Client for interaction

### Dependency Inversion

The layered architecture matters:

```
Actions -> Services -> Repositories -> Database
```

When an action calls the database directly, it's not just messy architecture. It means you can't test the business logic without a database, can't add caching at the repository level, and can't trace queries centrally.

## Business Logic Validation

**This is the most important part.** Clean code that does the wrong thing is worse than messy code that works.

For each module:

1. **Who is the user?** What job are they hiring this code for?
2. **What's the critical path?** The 3-5 steps that MUST work.
3. **Trace it end-to-end.** At every step: what if this fails?
4. **Check against production.** Does the data actually look like what the code expects?

### Validate Before Removing "Legacy" Code

Before removing format-handling code that looks dead:

```sql
-- Verify no records use the old format
SELECT COUNT(*) FROM records
WHERE data IS NOT NULL
  AND jsonb_typeof(data) = 'object';
-- Must return 0 before removing object-format handling
```

If the count is non-zero, check *when* those records were created. Recent records mean something is still writing the old format. Fix the writer first.

## The Remediation Sequence

1. **Detect parallel systems** - Find before splitting
2. **Domain error capture** - Create or use domain-specific capture
3. **Tracing wrappers** - Add to all exports
4. **Security audit** - No PII in tags, proper authorization
5. **Type safety** - Eliminate `as any` with type guards
6. **DRY extraction** - Consolidate 3+ duplicates to shared module
7. **Unit tests** - Auth, validation, happy path, errors
8. **Verify** - Typecheck, lint, all tests pass

The order matters. Don't write tests for code you're about to delete.
