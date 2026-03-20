# The Modh Playbook

> How Modh Labs builds production software. Battle-tested patterns, standards, and AI agent skills from shipping SaaS at scale.

This is the engineering playbook we use every day. It started as a collection of agent skills — reusable rules that teach AI coding assistants how we write code. But the patterns behind those skills are more valuable than the skills themselves. So we wrote them down.

24 chapters across 7 sections. Each chapter covers one pattern: the problem it solves, the principle behind it, the concrete implementation, and why it matters to the business. We also ship 18 AI agent skills that enforce these patterns automatically in your editor.

## Quick Start

```bash
# Add to your project as a git submodule
git submodule add https://github.com/modh-labs/playbook .agents/modh-playbook

# Install skills (creates symlinks into .claude/skills/)
./.agents/modh-playbook/install.sh
```

## The Chapters

### 1. Data Layer

How we access, mutate, and think about data. No raw queries. No client-side fetching. Type-safe from database to UI.

| Chapter | Core Idea |
|---------|-----------|
| [The Repository Pattern](chapters/01-data-layer/repository-pattern.md) | Why we never write raw database queries |
| [Server Actions](chapters/01-data-layer/server-actions.md) | Type-safe mutations that just work |
| [Data Fetching](chapters/01-data-layer/data-fetching.md) | Server Components changed everything |
| [Database Standards](chapters/01-data-layer/database-standards.md) | Schema-first, types-generated, RLS-enforced |

### 2. Architecture

How we structure applications. Routes own their code. Dependencies point inward. Webhooks are first-class citizens.

| Chapter | Core Idea |
|---------|-----------|
| [Route Colocation](chapters/02-architecture/route-colocation.md) | Files live next to the route that uses them |
| [Webhook Architecture](chapters/02-architecture/webhook-architecture.md) | One handler per event, SOLID registry, idempotency |
| [Multi-Tenant Isolation](chapters/02-architecture/multi-tenant-isolation.md) | RLS enforces org boundaries at the database level |

### 3. Quality

How we keep code correct. Types catch bugs at compile time. Tests catch bugs at merge time. Linters catch bugs before you finish typing.

| Chapter | Core Idea |
|---------|-----------|
| [TypeScript Strict](chapters/03-quality/typescript-strict.md) | Zero `any`, generated types, strict mode always on |
| [Testing Strategy](chapters/03-quality/testing-strategy.md) | Vitest for units, Playwright for flows, mocks for Supabase |
| [CI Pipeline](chapters/03-quality/ci-pipeline.md) | Cheapest checks first, no deploy in CI, fail fast |
| [Code Quality Audit](chapters/03-quality/code-quality-audit.md) | Detect parallel systems, delete dead code, validate against production |

### 4. Security

How we protect data. RLS is not optional. Validation happens at every boundary. Secrets never touch client code.

| Chapter | Core Idea |
|---------|-----------|
| [Row Level Security](chapters/04-security/row-level-security.md) | Every table has RLS policies, no exceptions |
| [Input Validation](chapters/04-security/input-validation.md) | Zod schemas at every boundary — forms, actions, webhooks |
| [Security Headers](chapters/04-security/security-headers.md) | CSP, CORS, and webhook signature verification |

### 5. Observability

How we understand what is happening in production. Structured logs. Distributed traces. Domain-specific captures. No `console.log`.

| Chapter | Core Idea |
|---------|-----------|
| [Structured Logging](chapters/05-observability/structured-logging.md) | Module loggers with context, never console.log |
| [Error Tracking](chapters/05-observability/error-tracking.md) | Sentry with domain captures, not generic exceptions |
| [Webhook Observability](chapters/05-observability/webhook-observability.md) | Every webhook traced end-to-end with searchable tags |

### 6. Process

How we work as a team. Features start with design, not code. Tickets have acceptance criteria. PRs tell a story.

| Chapter | Core Idea |
|---------|-----------|
| [Feature Design](chapters/06-process/feature-design.md) | Think before you code — 2-3 approaches, then decide |
| [Linear Tickets](chapters/06-process/linear-tickets.md) | User stories, architecture context, sub-task breakdown |
| [Pull Requests](chapters/06-process/pull-requests.md) | CI passes first, then a rich description with test plan |
| [Documentation](chapters/06-process/documentation.md) | Three layers — README, AGENTS.md, inline docs |

### 7. Frontend Craft

How we build interfaces. Server Components by default. Client boundaries pushed to the leaves. Every interaction feels instant.

| Chapter | Core Idea |
|---------|-----------|
| [Component Architecture](chapters/07-frontend-craft/component-architecture.md) | Composition over configuration, colocation over abstraction |
| [Performance Patterns](chapters/07-frontend-craft/performance-patterns.md) | Suspense, streaming, and instant UI feedback |
| [Design Standards](chapters/07-frontend-craft/design-standards.md) | shadcn/ui, semantic tokens, premium by default |
| [Internal Tools](chapters/07-frontend-craft/internal-tools.md) | Data density over visual impact, scannability first |

---

## Agent Skills

20 AI agent skills that enforce these patterns automatically. Compatible with Claude Code, Cursor, GitHub Copilot, Windsurf, and OpenAI Codex.

### Tier 1: Universal (Any Stack, Any Language)

| Skill | When It Activates | What It Does |
|-------|------------------|--------------|
| [`design-taste`](skills/design-taste/) | Building any user-facing UI | Enforces premium design — anti-AI pattern detection, typography rules, color calibration, tunable dials for variance/motion/density |
| [`internal-tools-design`](skills/internal-tools-design/) | Building admin panels, dashboards, ops tools | Optimizes for scannability and data density over visual impact — monospace numbers, dark mode, CSS-only transitions |
| [`output-enforcement`](skills/output-enforcement/) | Any code generation task | Bans `// ...`, `// TODO`, truncation patterns — forces complete, production-ready output |
| [`cross-editor-setup`](skills/cross-editor-setup/) | Setting up AI config for a project | Guides AGENTS.md + CLAUDE.md + Cursor rules setup for multi-agent team compatibility |
| [`code-review`](skills/code-review/) | Reviewing PRs, checking branch before push, batch quality sweeps | Seven-dimension review (observability, testing, SOLID, type safety, security, business logic, clean code) with pass/fail verdicts and educational findings |

### Tier 2: React / Next.js / TypeScript

| Skill | When It Activates | What It Does |
|-------|------------------|--------------|
| [`react-architecture`](skills/react-architecture/) | Components >300 lines, >15 useState, decomposition work | Hook extraction, state machines, hydration safety, composition patterns, React 19 APIs |
| [`nextjs-patterns`](skills/nextjs-patterns/) | Data fetching, mutations, loading states | Server Components, Suspense boundaries, server actions with Zod, cache invalidation, prefetching |
| [`shadcn-components`](skills/shadcn-components/) | Creating UI components | shadcn/ui rules, CSS variables over hardcoded colors, Sheet toggle pattern, detail view architecture |

### Tier 3: Backend / Infrastructure

| Skill | When It Activates | What It Does |
|-------|------------------|--------------|
| [`supabase-patterns`](skills/supabase-patterns/) | Database queries, migrations, RLS | Repository pattern, schema-first workflow, RLS policies, type generation |
| [`observability`](skills/observability/) | Adding logging, error tracking, tracing | Structured logger factory, Sentry integration, domain capture functions, webhook observability |
| [`write-criticality`](skills/write-criticality/) | Adding error handling for DB writes, retry logic | Three-tier write classification (tracking/retriable/critical), transient retry, alarm severity matching |
| [`webhook-architecture`](skills/webhook-architecture/) | Creating webhook handlers | SOLID handler registry, one handler per event, dependency injection, idempotency |
| [`security-and-compliance`](skills/security-and-compliance/) | New tables, auth flows, input validation | RLS enforcement, Zod at boundaries, webhook signatures, GDPR consent, SOC 2 checklist |
| [`testing`](skills/testing/) | Writing tests | Vitest patterns, Supabase mocking, Playwright page objects, `__tests__/` conventions |
| [`code-quality-audit`](skills/code-quality-audit/) | Auditing routes/modules for quality | Detect parallel systems, SOLID compliance, dead code removal, production data validation |

### Tier 4: Workflow / Process

| Skill | When It Activates | What It Does |
|-------|------------------|--------------|
| [`doc-audit`](skills/doc-audit/) | Auditing docs, adding features, before shipping | Three-layer doc system (README + AGENTS.md + CLAUDE.md), coverage reports, staleness detection, gap generation |
| [`feature-design`](skills/feature-design/) | Starting new features | Interactive brainstorming, 2-3 approach proposals, design specs before implementation |
| [`linear-tickets`](skills/linear-tickets/) | Creating issues or tickets | Rich tickets with user stories, architecture context, acceptance criteria, sub-task breakdown |
| [`pull-request`](skills/pull-request/) | Creating PRs | CI validation first, rich descriptions with summary + test plan |
| [`ci-pipeline`](skills/ci-pipeline/) | Modifying CI/CD | CI checks only (no deploy), cheapest-first ordering, extensible step pattern |
| [`route-colocation`](skills/route-colocation/) | Creating routes, organizing files | Colocate with routes, share at 3+ usages, actions folder pattern |

---

## Install

### Full Install (All Skills)

```bash
git submodule add https://github.com/modh-labs/playbook .agents/modh-playbook
./.agents/modh-playbook/install.sh
```

### Selective Install

```bash
# Just universal skills (works with any stack)
./install.sh . --tier=universal

# Universal + React/Next.js
./install.sh . --tier=universal --tier=react

# Backend only
./install.sh . --tier=backend

# Everything + generate configs for all agents
./install.sh . --all-agents
```

### Updating

```bash
cd .agents/modh-playbook && git pull
```

Because install.sh creates symlinks (not copies), pulling updates to the submodule immediately updates all skills. No reinstall needed.

---

## About

These are the patterns we actually use at [Modh Labs](https://modh.ca). They have been refined through building production SaaS products — finding what works, what the AI keeps getting wrong, and encoding those lessons so we do not repeat ourselves.

We are sharing them because we think they are useful. Take what works for you, ignore what does not.

## License

MIT — use freely in personal and commercial projects.
