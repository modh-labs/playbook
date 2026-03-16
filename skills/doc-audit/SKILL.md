---
name: doc-audit
description: >
  Audit and maintain documentation coverage across any codebase using the three-layer
  system (README.md for humans, AGENTS.md for AI agents, CLAUDE.md as pointer).
  Finds gaps, stale references, and JSDoc coverage issues. Can generate missing docs.
  Use when adding features, before shipping, or periodically to maintain coverage.
tier: process
icon: file-text
title: "Documentation Audit"
seo_title: "Documentation Audit — Modh Engineering Skill"
seo_description: "Audit and maintain documentation coverage across any codebase using the three-layer system. Finds gaps, stale references, and JSDoc coverage issues."
keywords: ["documentation", "audit", "AGENTS.md", "JSDoc", "coverage"]
difficulty: beginner
related_chapters: []
related_tools: []
---

# Documentation Audit Skill

## When This Skill Activates

- Auditing documentation coverage across a codebase
- Generating missing documentation for undocumented directories
- Checking if existing docs reference files that no longer exist
- Periodic maintenance to keep documentation accurate
- Before shipping a feature to ensure docs are complete

---

## Invocation Modes

- `/doc-audit` — Full codebase audit (coverage report)
- `/doc-audit route [path]` — Audit a specific route
- `/doc-audit lib [path]` — Audit a specific library
- `/doc-audit fix [path]` — Generate missing docs for a specific directory
- `/doc-audit validate` — Check existing docs against code for staleness

---

## Three-Layer Documentation System

Every meaningful directory in a codebase should have up to three documentation files:

| File | Audience | Content |
|------|----------|---------|
| **README.md** | Humans (engineers) | JTBD, features, quick start, architecture |
| **AGENTS.md** | AI agents (all tools) | Standards, conventions, file structure, imports, pitfalls |
| **CLAUDE.md** | Claude Code | Always exactly `@AGENTS.md` (import directive) |

### Why Three Files?

- **README.md** answers "what does this do and how do I get started?"
- **AGENTS.md** answers "what are the rules and patterns I must follow here?"
- **CLAUDE.md** is Claude Code's native import syntax — it tells Claude to read AGENTS.md
- Every other AI tool (Cursor, Codex, Devin, Gemini CLI) reads AGENTS.md natively

One source of truth (AGENTS.md) with universal coverage across 20+ AI tools.

---

## Directory Classification

Not every directory needs documentation. Classify first:

| Type | Rule | Documentation |
|------|------|---------------|
| **Route** | Has `page.tsx` or route handler | README.md + AGENTS.md + CLAUDE.md |
| **Package** | Top-level under `packages/` or similar | README.md + AGENTS.md + CLAUDE.md |
| **App** | Top-level application directory | README.md + AGENTS.md + CLAUDE.md |
| **Shared lib** | 3+ files, non-obvious patterns | AGENTS.md + CLAUDE.md (README.md optional) |
| **Trivial** | `fonts/`, `data/`, `__tests__/`, 1-2 obvious files | SKIP |

---

## Audit Algorithm

### Step 1: Discovery

Walk all directories and classify each using the rules above.

### Step 2: Coverage Check

For each non-trivial directory, check:

- [ ] `AGENTS.md` exists and is non-empty
- [ ] `CLAUDE.md` exists and contains exactly `@AGENTS.md`
- [ ] `README.md` exists (required for routes + packages, optional for libs)
- [ ] Route-specific: `error.tsx` exists
- [ ] Route-specific: `loading.tsx` exists

### Step 3: Staleness Detection

For each existing AGENTS.md:

1. Parse "Key Files" section (the tree structure)
2. Compare listed files against actual directory contents
3. Flag **phantom references** — files in docs but not on disk
4. Flag **undocumented files** — files on disk but not in docs
5. Check that linked reference docs still exist

### Step 4: JSDoc Coverage (Optional)

For critical-path files, check exported functions for JSDoc:

**Tier 1 (always JSDoc):** Repositories, server actions, services, webhook handlers, workflow files
**Tier 2 (non-obvious only):** Shared utilities where function name alone is insufficient
**Tier 3 (skip):** React components, simple CRUD, constants, tests

### Step 5: Report

Output a structured coverage report:

```
=== Documentation Coverage Report ===

Overall: [X]% covered ([N]/[M] directories)

CRITICAL GAPS (directories with no AGENTS.md):
  ✗ [path] — no AGENTS.md, no README.md

STALE DOCS (AGENTS.md references non-existent files):
  ⚠ [path]/AGENTS.md — references [file] (deleted)

MISSING CLAUDE.md:
  ⚠ [path] — has AGENTS.md but no CLAUDE.md

JSDOC GAPS:
  ✗ [path] — [N]/[M] exports missing JSDoc

COVERAGE BY AREA:
  Routes:     [X]/[Y] ([Z]%)
  Libraries:  [X]/[Y] ([Z]%)
  Packages:   [X]/[Y] ([Z]%)
```

---

## Templates

### Route AGENTS.md

```markdown
# [Route Name] Feature Guide

## Purpose
[One-line description]

## Key Components
| Component | Purpose |
|-----------|---------|
| `ComponentName` | [what it does] |

## Data Flow
1. [Step 1]
2. [Step 2]

## Repositories Used
- `repository.ts` — [purpose]

## Common Tasks
### [Typical modification]
1. [Step]

## Key Files
[actual tree structure from ls]

## Related
- [Links to workflow/pattern docs]
```

### Library AGENTS.md

```markdown
# [Library Name]

## Purpose
[One sentence]

## Exports
| Export | Purpose |
|--------|---------|
| `functionName()` | [what it does] |

## Usage
[code example]

## Rules
- Always [do X]
- Never [do Y]

## Related
- [Link to canonical doc]
```

### Package README.md

```markdown
# @scope/[package-name]

[One paragraph: what this package provides]

## Installation
[How to install/import]

## API
[Public exports with brief descriptions]

## Development
[Build, test, generate commands]
```

---

## Fix Mode

When invoked with `fix [path]`:

1. Read all source files in the directory
2. Classify the directory type (route, lib, package)
3. Generate README.md using the appropriate template
4. Generate AGENTS.md using the appropriate template, populated from source code
5. Create CLAUDE.md with `@AGENTS.md`

### Rules for Generation

- **MUST** populate "Key Files" with actual directory contents
- **MUST** populate component/export tables with actual names from source
- **MUST** link to canonical docs rather than duplicating content
- **MUST NOT** add docs to trivial directories
- **MUST NOT** auto-delete stale docs — flag and require human confirmation

---

## Core Principles

### Link, Never Duplicate

Route-level docs LINK to canonical references — they never re-explain system logic.

```markdown
## Related Workflows
- [Call Lifecycle](../docs/workflows/call-lifecycle.md)
```

**NOT:**
```markdown
## How Calls Work
[200 lines duplicating the workflow doc]
```

### Single Source of Truth

Each piece of knowledge lives in ONE place. Other docs link to it.

### JSDoc Complements, Not Replaces

JSDoc on functions answers "what does this function do?" — not "how does the whole system work?" For system-level understanding, link to higher-level docs.

---

## JSDoc Convention

### Tags for Workflow Functions

```typescript
/**
 * [One-line description]
 *
 * @workflow docs/workflows/[workflow].md
 * @lifecycle-stage [kebab-case-stage]
 * @param paramName - [description]
 * @returns [description]
 */
```

### Don't JSDoc the Obvious

```typescript
// BAD
/** Creates a lead. */
export async function createLead(data: CreateLeadInput) { ... }

// GOOD — name is self-documenting
export async function createLead(data: CreateLeadInput) { ... }
```

---

## Validate Mode

When invoked with `validate`:

1. Find all AGENTS.md files in the codebase
2. For each, run staleness detection
3. Find all CLAUDE.md files, verify each contains `@AGENTS.md`
4. Check that documentation indexes match actual files
5. Output a staleness report with specific files and line numbers
