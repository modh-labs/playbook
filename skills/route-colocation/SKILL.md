---
name: route-colocation
description: Guide code organization, folder structure, and route architecture following colocation-first patterns. Use when creating routes, deciding file placement, organizing imports, or structuring documentation. Enforces the 3+ routes sharing threshold, actions folder pattern, and documentation placement rules.
---

# Route Colocation Skill

## When This Skill Activates

This skill automatically activates when you:
- Create new routes or features
- Decide where to place new code
- Organize components, actions, or types
- Work with shared directories
- Add or update documentation for a feature

## Core Philosophy

**Colocation first, share when necessary.**

Code lives with the route that uses it until it needs to be shared. The threshold for sharing is **3+ routes** or **2 routes with clear expansion potential**.

---

## Directory Structure

```
app/
|-- (protected)/           # Authenticated routes
|   |-- [route]/           # Example: calls, leads, dashboard
|       |-- page.tsx       # Server Component (data fetching)
|       |-- actions.ts     # Server actions (1-2 actions)
|       |-- actions/       # Server actions folder (3+ actions)
|       |   |-- create-item.ts
|       |   |-- delete-item.ts
|       |-- components/    # Route-specific components
|       |-- loading.tsx    # Skeleton (matches UI layout)
|       |-- error.tsx      # Error boundary with retry
|       |-- AGENTS.md      # Route documentation (AI context)
|       |-- CLAUDE.md      # Contains "@AGENTS.md" (Claude Code import)
|
|-- (public)/              # Public routes
|
|-- api/webhooks/          # ONLY for external webhooks
|
|-- _shared/               # Shared code (3+ routes)
    |-- components/        # Shared UI components
    |-- lib/               # Utilities, clients
    |-- repositories/      # Data access layer
    |-- services/          # Business logic
    |-- types/             # TypeScript types
    |-- validation/        # Validation schemas
```

## When to Use What

### Repository vs Service vs Action

| Layer | Purpose | Location | When to Use |
|-------|---------|----------|-------------|
| **Repository** | Database CRUD | `_shared/repositories/` | ALL database operations |
| **Service** | Business logic | `_shared/services/` | Complex multi-step operations |
| **Server Action** | Entry point | Route `actions.ts` | User-triggered mutations |

```
User Click -> Server Action -> Service (if complex) -> Repository -> Database
```

### Decision Tree

```
"Where should this code live?"

Is it a database query?
  -> _shared/repositories/[entity].repository.ts

Is it complex business logic (multi-step, external services)?
  -> _shared/services/[domain].service.ts

Is it a user-triggered mutation or fetch?
  -> Route's actions.ts or actions/

Is it a UI component?
  -> Used by 1-2 routes? -> Route's components/
  -> Used by 3+ routes? -> _shared/components/

Is it a type definition?
  -> Route-specific? -> Route's types.ts
  -> Shared across routes? -> _shared/types/

Is it validation?
  -> _shared/validation/[route].schema.ts
```

---

## Documentation Placement

### Two-Layer System

| Layer | Location | Audience | Purpose |
|-------|----------|----------|---------|
| **Human docs** | `docs/` | Developers reading and learning | Explains how and why -- patterns, runbooks, standards |
| **AI skills** | `.claude/skills/` | AI coding agents | Enforces rules mechanically -- MUST/NEVER directives |

These layers often cover the same topic but serve different consumers. When you add a new pattern, consider whether BOTH need updating.

### Where to Put Documentation

| Type | Location | When |
|------|----------|------|
| **Engineering patterns** | `docs/patterns/` | Reusable approach for building something |
| **Operational runbooks** | `docs/runbook/<integration>/` | External system that needs debugging knowledge |
| **User journeys** | `docs/cuj/` | End-to-end flow spanning multiple components |
| **Coding standards** | `docs/standards/` | Rule applying across the entire codebase |
| **Internal guides** | `docs/internal/` | Deployment procedures, environment setup |
| **Route-level AI context** | `<route>/AGENTS.md` + `CLAUDE.md` | Directory with enough complexity for AI context |

### In-Code AI Context Files

When a directory contains enough complexity that AI tools need context:

1. Write content in `AGENTS.md` (source of truth)
2. Create `CLAUDE.md` with just `@AGENTS.md` (Claude Code import)
3. Keep it brief and focused on what's unique about this directory

### When to Create a Matching Skill

Create or update a `.claude/skills/` skill alongside human docs when:
- The pattern has strict rules (MUST/NEVER) that an AI agent should enforce
- Violations are common and caught repeatedly in code review
- The pattern involves code generation (scaffolding, boilerplate)

Do NOT create a skill when:
- The doc is purely informational (architecture overview, runbook)
- The topic is too broad to enforce mechanically
- It's a one-off guide (deployment steps, investigation notes)

---

## Actions Folder Pattern

When a route has **1-2 server actions**, use a single file:

```
route/
|-- page.tsx
|-- actions.ts          # Contains 1-2 actions
```

When a route has **3+ server actions**, use a folder:

```
route/
|-- page.tsx
|-- actions/
    |-- create-item.ts  # One action per file
    |-- update-item.ts
    |-- delete-item.ts
```

Each action file exports a single server action function. No barrel files.

---

## The 3+ Routes Threshold

This is the key decision boundary for code organization:

| Usage | Location | Rationale |
|-------|----------|-----------|
| 1 route | Colocated in route directory | No need to share |
| 2 routes | Colocated, or shared if expansion is likely | Use judgment |
| 3+ routes | `_shared/` directory | Clearly shared infrastructure |

**When promoting to shared:**
1. Move the file to the appropriate `_shared/` subdirectory
2. Update all imports
3. Ensure the module has a clear, single responsibility
4. Add documentation if the module is non-trivial

---

## New Feature Documentation Checklist

When building a significant new feature, create documentation in this order:

1. **In-code `AGENTS.md` + `CLAUDE.md`** -- immediate AI context for the route/directory
2. **Pattern doc** (`docs/patterns/`) -- if the feature introduces a reusable pattern
3. **User journey doc** (`docs/cuj/`) -- if the feature is a multi-step flow
4. **Runbook** (`docs/runbook/`) -- if the feature integrates an external system
5. **Skill** (`.claude/skills/`) -- if the pattern has strict enforceable rules
6. **Update indexes** -- add entries to relevant README.md files

---

## Checklist for New Routes

- [ ] `page.tsx` -- Server Component for data fetching
- [ ] `actions.ts` or `actions/` -- Server actions
- [ ] `components/` -- Route-specific components
- [ ] `loading.tsx` -- Skeleton matching UI layout
- [ ] `error.tsx` -- Error boundary with retry
- [ ] `AGENTS.md` + `CLAUDE.md` -- Route documentation for AI context
- [ ] Repository in `_shared/repositories/` if new entity
- [ ] Validation schema in `_shared/validation/`

## Quick Reference

| What | Where | Rule |
|------|-------|------|
| Database queries | `_shared/repositories/` | Always |
| Complex business logic | `_shared/services/` | 3+ steps or external services |
| User mutations/fetches | Route `actions.ts` or `actions/` | Colocated with route |
| Route components | Route `components/` | Default |
| Shared components | `_shared/components/` | 3+ routes threshold |
| Route-specific types | Route `types.ts` | Single route use |
| Shared types | `_shared/types/` | Multiple route use |
| Validation schemas | `_shared/validation/` | Always |
| Engineering patterns | `docs/patterns/` | Reusable approaches |
| Operational runbooks | `docs/runbook/` | External system debugging |
| AI enforcement rules | `.claude/skills/` | Strict MUST/NEVER rules |
