---
title: "Documentation as Code"
subtitle: "Three-layer docs for humans + AI"
chapter: 22
section: "Process"
seo_title: "Three-Layer Documentation Architecture — README, AGENTS.md, and CLAUDE.md in 2026"
seo_description: "A documentation system where humans read README.md, AI agents read AGENTS.md, and Claude Code imports both — one source of truth, universal coverage."
keywords: ["documentation as code", "AGENTS.md", "CLAUDE.md", "ai documentation", "developer documentation", "documentation architecture"]
reading_time: "8 min"
difficulty: "intermediate"
tech_stack: ["Next.js", "Supabase", "TypeScript"]
business_case: "Eliminate stale documentation and AI hallucinations by co-locating docs with code, making every directory self-describing for both humans and AI agents."
---

# Documentation as Code

> "Documentation that lives outside the code it describes is documentation that lies."

## The Problem

Every engineering team has a documentation problem, but it is not the problem they think it is.

The obvious problem is that documentation goes stale. Someone writes a comprehensive guide to the authentication flow, puts it in Notion, and six months later the authentication flow has changed three times. The Notion page is now a trap — it describes a system that no longer exists, and anyone who follows it will build the wrong thing.

The less obvious problem is the audience problem. In 2026, your codebase has two audiences: human engineers and AI coding agents. A README that explains "what this does and how to get started" is perfect for a human onboarding onto the project. But an AI agent does not need onboarding — it needs rules. "Always use `select('*')`. Never create custom interfaces. Use the repository pattern for all database access." Prose that helps humans confuses AI. Directives that guide AI bore humans.

The third problem is discoverability. Documentation in a wiki, a Notion workspace, or a Google Drive is invisible to the engineer (or AI agent) working in the codebase. The only documentation that gets read is documentation that lives next to the code it describes.

## The Principle

We solve all three problems with a three-layer documentation system. Every meaningful directory in the codebase gets up to three files, each serving a different audience:

| File | Audience | Purpose |
|------|----------|---------|
| **README.md** | Human engineers | What this does, features, quick start, architecture |
| **AGENTS.md** | AI coding agents (all tools) | Rules, conventions, file structure, imports, pitfalls |
| **CLAUDE.md** | Claude Code specifically | Import directive — always contains `@AGENTS.md` |

**Why three files instead of one?**

`README.md` answers "what does this do and how do I get started?" It is written in prose for humans.

`AGENTS.md` answers "what are the rules and patterns I must follow here?" It is written in imperative directives for AI. It is the [AGENTS.md open standard](https://agents.md), stewarded by the Agentic AI Foundation under the Linux Foundation, used by 60,000+ repositories, and supported by 20+ AI coding tools including Cursor, VS Code, Windsurf, Zed, Claude Code, Gemini CLI, Codex, Aider, Devin, and Jules.

`CLAUDE.md` is Claude Code's native import syntax. It contains exactly one line: `@AGENTS.md`. This tells Claude Code to read the AGENTS.md file. Every other AI tool reads AGENTS.md directly. One source of truth, universal coverage.

**Co-location prevents staleness.** When the documentation lives in the same directory as the code it describes, engineers update it as part of the same PR that changes the code. A change to the order processing logic includes an update to the order directory's AGENTS.md. The documentation evolves with the code because it is reviewed in the same diff.

## The Pattern

### Layer 1: README.md (Humans)

README files are required for route directories (pages users visit) and package directories. They are optional for shared libraries unless the library has five or more files or complex logic.

```markdown
# Orders

## What This Does
Manages the full order lifecycle from creation through fulfillment.

## Features
- Create and edit orders with line items
- Track order status through the pipeline
- Bulk actions (archive, export, reassign)
- Real-time status updates via webhook sync

## Quick Start
- **Entry point:** `page.tsx`
- **Actions:** `actions/`
- **Key component:** `OrdersDataTable`

## How It Works
The page is a Server Component that fetches orders via the
repository. Each mutation goes through a server action that
validates with Zod, calls the repository, and revalidates the
cache. Status changes trigger webhook notifications.

## Related Docs
- [Order Lifecycle](docs/workflows/order-lifecycle.md)
```

### Layer 2: AGENTS.md (AI Agents)

AGENTS.md files use imperative language. AI tools follow directives better than prose.

```markdown
# Orders Feature Guide

## Purpose
Full order lifecycle management — creation, status tracking,
fulfillment.

## Key Components
| Component | Purpose |
|-----------|---------|
| `page.tsx` | Server Component, data fetching |
| `actions/` | Server Actions for all mutations |
| `components/OrdersDataTable` | Main data grid |
| `components/OrderDetailSheet` | Side panel detail view |

## Data Flow
1. `page.tsx` calls `ordersRepository.list()` via Supabase
2. Mutations go through server actions in `actions/`
3. Every action calls `revalidatePath('/orders')` after mutation
4. Status changes emit webhook events

## Rules
- Always use `ordersRepository` for database access
- Never call Supabase directly in components or actions
- Always validate input with Zod before mutations
- Always call `revalidatePath()` after every mutation

## Repositories Used
- `orders.repository.ts` — CRUD for orders table
- `order-items.repository.ts` — Line item management

## Related Workflows
- [Order Lifecycle](docs/workflows/order-lifecycle.md)
```

### Layer 3: CLAUDE.md (Claude Code)

Always exactly one line:

```
@AGENTS.md
```

That is it. All content lives in AGENTS.md. CLAUDE.md is purely an import directive.

### Directory Types

Not every directory needs all three files. Match the documentation depth to the directory's complexity.

**Route directories** (pages users visit): All three files required. These are the most complex directories with the most context for AI agents to understand.

**Shared library directories** (utilities, services): AGENTS.md + CLAUDE.md required if the directory has three or more files or non-obvious patterns. README.md optional unless the library is complex.

**Package directories** (monorepo packages): All three files required. Packages have their own conventions, build steps, and consumer lists.

**Trivial directories** (fonts, static data, constants, test directories, skeleton components): Skip documentation entirely. These are self-documenting by nature.

### Core Principles

**Link, never duplicate.** Route-level docs link to canonical references. They never re-explain lifecycle logic that lives in a workflow document.

```markdown
## Related Workflows
- [Order Lifecycle](docs/workflows/order-lifecycle.md) — creation
  through fulfillment
```

Not:

```markdown
## How Orders Work
When an order is created, the lifecycle begins with...
[200 lines duplicating the workflow doc]
```

**Single source of truth.** Each piece of knowledge lives in one place:

| Knowledge Type | Canonical Location |
|---------------|-------------------|
| Lifecycle logic | `docs/workflows/` |
| Engineering patterns | `docs/patterns/` |
| Coding standards | `docs/standards/` |
| Operational knowledge | `docs/runbook/` |
| Route-specific context | Route's `AGENTS.md` |

**Precedence.** When multiple AGENTS.md files exist in a directory tree, the closest one to the file being edited takes precedence. The root AGENTS.md provides global rules. Nested files provide directory-specific context that can override or extend the root.

### Tool Support

The AGENTS.md standard is supported natively by the major AI coding tools:

| Category | Tools |
|----------|-------|
| IDE Agents | Cursor, VS Code, Windsurf, Zed |
| CLI Agents | Claude Code, Gemini CLI, Codex (OpenAI), Aider |
| Autonomous Agents | Devin, Jules (Google), Factory, Amp |
| Code Review | Semgrep, RooCode |

You write the AGENTS.md file once. Every AI tool your team uses reads it automatically. No plugin configuration, no tool-specific formats, no vendor lock-in.

## The Business Case

**AI agent output quality jumps immediately.** An AI agent working in a directory with an AGENTS.md file follows your patterns instead of guessing. It uses your repository layer instead of calling the database directly. It validates with Zod instead of trusting input. The generated code is mergeable without a rewrite.

**Onboarding time drops by 50%.** New engineers (and new AI agents) get context exactly where they need it — in the directory they are working in. No searching through wikis, no asking teammates, no reading month-old Slack threads.

**Documentation stays fresh.** When docs live with the code, they are updated in the same PR as the code change. A stale AGENTS.md is visible in code review the same way a stale test is visible in CI.

**Tool switching becomes painless.** Because AGENTS.md is an open standard, switching from one AI tool to another requires zero documentation migration. The context travels with the codebase, not with the tool.

## Try It

Install the [Modh Playbook](https://github.com/modh-ai/playbook) to get the three-layer documentation architecture with templates for route, library, and package directories, plus the AGENTS.md convention pre-configured across your codebase.
