---
title: "Agentic Development"
subtitle: "Building with AI agents, not against them"
chapter: 23
section: "Process"
seo_title: "Agentic Development — Context Engineering, Skill Systems, and AGENTS.md in 2026"
seo_description: "How to structure your codebase, documentation, and workflow so AI coding agents produce production-quality code instead of hallucinated garbage."
keywords: ["agentic development", "ai coding agents", "context engineering", "AGENTS.md", "claude code", "skill systems", "ai-first development"]
reading_time: "12 min"
difficulty: "advanced"
tech_stack: ["Next.js", "Supabase", "TypeScript"]
business_case: "10x individual developer throughput by making AI agents effective collaborators instead of expensive autocomplete."
---

# Agentic Development

> "The quality of an AI agent's output is a function of the context it receives. Fix the context, and the output fixes itself."

## The Problem

Most engineering teams adopt AI coding agents the same way: they install a tool, paste a prompt, and hope for the best. When the output is wrong — and it often is — they blame the model. "AI is not ready for production code." "It keeps hallucinating APIs that do not exist." "It does not follow our patterns."

The model is rarely the problem. The context is.

When you ask an AI agent to "create a repository function," the agent does not know that your project uses a specific repository pattern, that every function takes a typed database client as its first parameter, that you always use `select('*')`, or that you never create custom interfaces. Without this context, the agent generates plausible but wrong code — code that looks correct but violates every convention your team has established.

The typical response is to manually correct the output, adding a long system prompt or pasting the relevant docs into every conversation. This is exhausting, error-prone, and does not scale. You are doing the context work that the system should do automatically.

The deeper problem is that AI agents consume context on every request. A bloated root configuration file — 700 lines of documentation that loads on every interaction — wastes tokens, increases latency, and dilutes the agent's focus. When your authentication documentation loads during a CSS styling task, the agent might apply auth patterns to your component code. Irrelevant context produces irrelevant output.

## The Principle

Agentic development is not about prompting better. It is about engineering your codebase so that AI agents receive the right context at the right time, automatically.

We call this **context engineering**, and it has three layers:

**Layer 1: Documentation as Interface.** Your documentation is not just for humans anymore. It is the API that AI agents call to understand your codebase. The AGENTS.md open standard (used by 60,000+ repositories, supported by 20+ AI tools including Cursor, VS Code, Gemini CLI, Codex, Devin, and Jules) provides a universal format for this. Every directory gets an AGENTS.md file with the rules, conventions, and patterns that AI agents must follow when working in that directory.

**Layer 2: Progressive Disclosure.** Not all context is needed for every task. A hierarchical loading system ensures agents see project-wide rules on every request (kept minimal), directory-specific context when working in a specific area, and detailed documentation only when the task requires it. This is the difference between 25,000 tokens of baseline context and 5,000.

**Layer 3: Skill Systems.** Reusable patterns — how to create a repository, how to write a server action, how to build a component — are packaged as "skills" that auto-activate when the task matches. The agent does not need to be told to follow the repository pattern. It recognizes that you asked for a database function and loads the skill automatically.

## The Pattern

### The Six Memory Mechanisms

AI coding agents (specifically Claude Code, but the principles apply to all tools) load context through six mechanisms, each with different cost and scope characteristics.

#### 1. Root Configuration (Always Loads)

The root CLAUDE.md or AGENTS.md file loads on every single request. Every line here costs tokens on every interaction.

**Rule:** Keep this under 150 lines. Only include information that every task needs: tech stack, critical DO/DON'T rules, package manager, test commands.

```markdown
# Project Guide

## Tech Stack
- Next.js 16 (App Router) + React 19 + TypeScript strict
- Tailwind CSS + shadcn/ui
- Supabase (PostgreSQL + RLS)
- Vitest + Playwright

## Critical Rules
- Use repositories for ALL database queries
- Use Server Actions for ALL mutations
- Always `select('*')` in database queries
- Always `revalidatePath()` after mutations
- Use shadcn/ui — never raw HTML elements

## Commands
- `bun dev` — Development server
- `bun test` — Run tests
- `bun ci` — Full CI check
```

That is it. Everything else moves to a mechanism that loads conditionally.

#### 2. Directory Context (Loads When Working in Directory)

Nested AGENTS.md files load only when the agent is working in that directory. This is where route-specific and feature-specific context lives.

```
orders/AGENTS.md     ← Only loads when editing files in orders/
users/AGENTS.md      ← Only loads when editing files in users/
webhooks/AGENTS.md   ← Only loads when editing webhook handlers
```

Directory context is free when you are not using it and precisely targeted when you are.

#### 3. Skills (Auto-Invoke When Task Matches)

Skills are the most powerful optimization. They are documentation files that auto-activate when the agent determines the task matches the skill's description.

```yaml
# .claude/skills/repository-pattern/SKILL.md
---
name: repository-pattern
description: Database access via repositories. Use when writing
  database queries, creating repositories, or adding data access
  code.
---

# Repository Pattern

## Rules
1. Always `select('*')` — never pick specific columns
2. Accept typed database client as first parameter
3. Use generated types from database schema
4. One repository per database table

## Template
[Complete working example...]
```

When you ask "help me create a function to fetch users from the database," the agent sees keywords like "fetch," "users," and "database," matches them to the repository skill, and loads the complete pattern. No manual prompting required.

#### 4. Path Rules (Load for Matching File Types)

Path rules activate when the agent is editing files that match a glob pattern.

```yaml
# .claude/rules/testing.md
---
paths:
  - "**/*.test.ts"
  - "**/*.spec.ts"
---

# Testing Standards
These rules only load when working with test files.
- Use Vitest, not Jest
- Mock the database client, not the repository
- Test behavior, not implementation
```

Testing standards load when editing test files. Not when editing components. Not when editing server actions. The context is precisely scoped.

#### 5. Imports (On-Demand)

Reference detailed documentation from any AGENTS.md file using `@imports`. The agent reads these files only when it decides it needs the information.

```markdown
## Documentation
- @docs/patterns/repository-pattern.md
- @docs/patterns/server-actions.md
- @docs/workflows/order-lifecycle.md
```

Imports are lazy-loaded. They cost zero tokens until the agent actively reads them.

#### 6. Subagents (Isolated Context)

Heavy tasks like code review, PR creation, and documentation generation run in a separate context window via subagents. They consume zero tokens from the main conversation.

```yaml
# .claude/agents/code-reviewer.md
---
name: code-reviewer
description: Review code against project patterns
model: sonnet
tools: [Read, Grep, Glob]
skills: [repository-pattern, server-action]
---
```

### The Token Economics

The difference these mechanisms make is dramatic.

**Before optimization:** Every request loaded 25,000 tokens of context. Root CLAUDE.md alone was 724 lines. Analytics documentation loaded during repository tasks. Commit conventions loaded during styling tasks. Testing standards loaded during every interaction.

**After optimization:** Root configuration: 132 lines (~3,000 tokens). Skills, path rules, and directory context load conditionally: ~2,000 tokens average. Total baseline: ~5,000 tokens per request.

**80% reduction in token consumption.** But the bigger win is quality: the agent sees only the context relevant to the current task, so its output is more focused and more accurate.

### Building Effective Skills

A skill has three parts:

**The description** determines when it activates. Write it with the keywords that a developer would naturally use when requesting this type of work.

```yaml
description: Create server actions following established patterns.
  Use when writing mutations, form handlers, or data operations.
```

"Mutations," "form handlers," "data operations" — these are the words engineers use when they need a server action. The agent matches on these keywords.

**The rules** are imperative directives that the agent follows literally. Not suggestions. Not explanations. Directives.

```markdown
## Rules
1. Use Server Actions for ALL mutations — not API routes
2. Always use repositories for database access — never call the
   database directly
3. Always validate input with Zod before processing
4. Always call `revalidatePath()` after every mutation
5. Return structured responses: `{ success, data?, error? }`
```

**The template** is a complete, working example that the agent can copy and adapt. Not a snippet. Not pseudocode. A production-ready implementation.

```typescript
"use server";

import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";
import * as ordersRepo from "@/repositories/orders.repository";
import { createOrderSchema } from "@/validation/orders.schema";

export async function createOrderAction(input: unknown) {
  const validation = createOrderSchema.safeParse(input);
  if (!validation.success) {
    return { success: false, error: validation.error.issues[0]?.message };
  }

  try {
    const supabase = await createClient();
    const order = await ordersRepo.create(supabase, validation.data);
    revalidatePath("/orders");
    return { success: true, data: order };
  } catch (error) {
    return { success: false, error: "Failed to create order" };
  }
}
```

When an agent loads this skill, it produces code that follows your patterns on the first try. No corrections needed.

### Scaling Across the Codebase

At scale, this system produces a documentation graph that is both human-readable and machine-optimized.

```
Root AGENTS.md          ← 150 lines, loads always
├── apps/web/AGENTS.md  ← App conventions, loads in web/
│   ├── orders/AGENTS.md    ← Route context
│   ├── users/AGENTS.md     ← Route context
│   └── webhooks/AGENTS.md  ← Webhook patterns
├── packages/ui/AGENTS.md   ← Component library rules
├── .claude/skills/
│   ├── repository-pattern/SKILL.md  ← Auto-invokes
│   ├── server-action/SKILL.md       ← Auto-invokes
│   └── component-creation/SKILL.md  ← Auto-invokes
└── .claude/rules/
    ├── testing.md           ← Loads for test files
    └── migrations.md        ← Loads for migration files
```

The root file is lean. Skills handle reusable patterns. Path rules handle file-type conventions. Directory AGENTS.md files handle feature-specific context. Every piece of documentation loads at the right time for the right task.

### The Open Standard Advantage

AGENTS.md is not a proprietary format. It is an open standard under the Linux Foundation, adopted by 60,000+ repositories including OpenAI's Codex (which has 88 AGENTS.md files). Every major AI coding tool reads it natively.

This means your documentation investment is portable. If your team switches from one AI coding tool to another — from Claude Code to Cursor, from Cursor to Gemini CLI — the AGENTS.md files come with the codebase. No migration, no format conversion, no vendor lock-in.

It also means your documentation serves both human and AI audiences. A new team member reads README.md to understand what a feature does. An AI agent reads AGENTS.md to understand how to generate code for it. Both are co-located with the code they describe. Both evolve in the same PR as the code changes.

### The Workflow Shift

Agentic development changes how we work:

**Before:** Write code manually, use AI for autocomplete and suggestions.

**After:** Describe what you need, let the agent generate code that follows your patterns, review and refine.

The engineer's role shifts from writing every line to designing the system of constraints that produces correct code. You invest time in skills, AGENTS.md files, and pattern documentation. The return on that investment compounds with every task the agent performs.

A well-configured skill system means that creating a new repository function, a new server action, a new component, or a new test takes seconds of prompting followed by seconds of review. The agent does the typing. The engineer does the thinking.

## The Business Case

**Individual throughput increases 5-10x.** An engineer with a well-configured agentic development setup ships features in hours that previously took days. The agent handles boilerplate, pattern adherence, and test scaffolding. The engineer handles architecture, business logic, and code review.

**Pattern compliance reaches 100%.** When patterns are encoded in skills that auto-activate, every generated file follows the convention. No more "I forgot to use the repository" or "I accidentally called the database directly." The system enforces the pattern automatically.

**Onboarding shrinks to hours.** A new engineer (or a new AI agent) working in any directory gets the rules and conventions for that directory automatically. The codebase is self-describing. No tribal knowledge required.

**Context costs drop 80%.** Progressive disclosure means the agent loads 5,000 tokens instead of 25,000 on every request. Over hundreds of daily interactions, this translates to hundreds of dollars in monthly savings and measurably faster response times.

**The documentation stays alive.** When documentation is the interface that AI agents use to generate code, stale documentation produces visibly wrong code. This creates a natural feedback loop: engineers update AGENTS.md files because outdated files produce bad output. The documentation is no longer a chore — it is a tool that directly improves the quality of the code the team ships.

## Try It

Install the [Modh Playbook](https://github.com/modh-ai/playbook) to get the complete agentic development setup with the six-mechanism context hierarchy, skill templates, AGENTS.md convention, and progressive disclosure architecture pre-configured for Next.js.
