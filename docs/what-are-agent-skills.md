# What Are Agent Skills?

Agent skills are modular instruction sets that teach AI coding agents how to write better code for your specific project. Think of them as "coding standards that the AI actually follows."

## The Problem

AI coding agents (Claude Code, Cursor, Copilot, etc.) are incredibly capable out of the box, but they don't know:

- Your team's architectural patterns (repository pattern? server actions? hooks extraction?)
- Your design standards (shadcn/ui? CSS variables? no hardcoded colors?)
- Your security requirements (RLS policies? Zod validation at boundaries?)
- Your workflow conventions (CI before PR? Linear tickets with full context?)

Without skills, you repeat the same corrections conversation after conversation. "No, don't use console.log — use the structured logger." "No, don't hardcode colors — use CSS variables." Every time.

## The Solution

Skills are markdown files (SKILL.md) that encode your engineering standards in a format AI agents understand. When an agent's task matches a skill's description, the skill loads automatically and the agent follows those rules.

```
You: "Build an admin dashboard for order management"

Without skills:
  → Generic Bootstrap-looking table
  → console.log everywhere
  → Hardcoded gray-500 colors
  → No loading states
  → No error handling

With skills (design-taste + internal-tools-design + observability):
  → Dense, scannable layout optimized for daily ops use
  → Monospace numbers, dark mode support
  → Structured logger with Sentry integration
  → Skeleton loaders matching final layout
  → Error boundaries with retry buttons
```

## How They Work

### 1. Discovery (startup)

When you open a project, the agent scans `.claude/skills/` and reads just the frontmatter:

```yaml
---
name: design-taste
description: Senior UI/UX design standards. Anti-AI pattern detection...
---
```

This is lightweight — just a name and description per skill.

### 2. Matching (per task)

When you give the agent a task, it checks which skills match. A task like "Build a landing page" matches `design-taste`. A task like "Add Sentry logging" matches `observability`.

### 3. Loading (on demand)

Only matched skills are loaded into the agent's context. The full SKILL.md content (rules, patterns, anti-patterns) guides the agent's output.

### 4. Deep reference (when needed)

If a skill says "See `references/creative-arsenal.md` for advanced techniques," the agent loads that file only when it needs the deeper content.

## Why Not Just Use AGENTS.md?

AGENTS.md and skills serve different purposes:

| | AGENTS.md | Skills |
|---|-----------|--------|
| **Loaded** | Always (every conversation) | On-demand (when task matches) |
| **Content** | Project overview, tech stack, critical rules | Specialized domain knowledge |
| **Size** | Short (~100 lines) | Deep (~300 lines each) |
| **Scope** | "What is this project?" | "How do we do X specifically?" |

Use AGENTS.md for things every conversation needs (tech stack, package manager, critical do/don't rules). Use skills for specialized knowledge (how to write tests, how to design dashboards, how to structure webhooks).

## The Skill Ecosystem

Skills aren't proprietary to any one tool. The SKILL.md format is an open standard managed by the [Agentic AI Foundation](https://aaif.io/) (AAIF) under the Linux Foundation. It's supported by:

- **Claude Code** — native support, auto-discovers from `.claude/skills/`
- **Cursor** — reads `.claude/skills/` when "Import Agent Skills" is enabled
- **GitHub Copilot** — reads `AGENTS.md` and `.github/copilot-instructions.md`
- **OpenAI Codex** — reads `AGENTS.md`
- **Windsurf** — reads `.windsurfrules`

This means your investment in skills is portable across tools — you're not locked into any single AI agent.

## Next Steps

- [Install the Modh skills pack](../README.md#quick-start) into your project
- [Write your own skills](writing-skills.md) for project-specific patterns
- [Contribute a skill](contributing.md) back to this repo
