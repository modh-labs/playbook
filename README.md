# Modh Agent Skills

Battle-tested AI coding agent skills, consolidated from production SaaS development. 17 portable skills across architecture, design, backend, and workflow — compatible with Claude Code, Cursor, GitHub Copilot, Windsurf, and OpenAI Codex.

**Why this exists:** After building with AI agents across multiple projects, we found ourselves recreating the same patterns, rules, and guardrails. We had 40+ skills — many redundant, most project-specific. We consolidated them into 17 framework-agnostic skills that encode our best engineering practices without being tied to any single codebase.

## Quick Start

```bash
# Add to your project as a git submodule
git submodule add https://github.com/modh-labs/agent-skills .agents/modh-skills

# Install skills (creates symlinks into .claude/skills/)
./.agents/modh-skills/install.sh
```

That's it. Claude Code and Cursor will auto-discover the skills immediately.

> **New to agent skills?** See [What Are Agent Skills?](docs/what-are-agent-skills.md) for background on how AI agents use skills to write better code.

## What Happens After Install

```
your-project/
├── .agents/modh-skills/          ← Git submodule (this repo)
├── .claude/skills/
│   ├── design-taste/             → .agents/modh-skills/skills/design-taste (symlink)
│   ├── react-architecture/       → .agents/modh-skills/skills/react-architecture (symlink)
│   ├── observability/            → .agents/modh-skills/skills/observability (symlink)
│   ├── ...                       → (17 skills total)
│   └── my-custom-skill/          ← Your own project-specific skill (untouched)
├── AGENTS.md                     ← Created if missing (from template)
└── CLAUDE.md                     ← Created if missing ("@AGENTS.md")
```

install.sh **never overwrites** existing local skill directories or files.

## Skills Reference

### Tier 1: Universal (Any Stack, Any Language)

| Skill | When It Activates | What It Does |
|-------|------------------|--------------|
| [`design-taste`](skills/design-taste/) | Building any user-facing UI | Enforces premium design — anti-AI pattern detection, typography rules, color calibration, tunable dials for variance/motion/density |
| [`internal-tools-design`](skills/internal-tools-design/) | Building admin panels, dashboards, ops tools | Optimizes for scannability and data density over visual impact — monospace numbers, dark mode, CSS-only transitions |
| [`output-enforcement`](skills/output-enforcement/) | Any code generation task | Bans `// ...`, `// TODO`, truncation patterns — forces complete, production-ready output |
| [`cross-editor-setup`](skills/cross-editor-setup/) | Setting up AI config for a project | Guides AGENTS.md + CLAUDE.md + Cursor rules setup for multi-agent team compatibility |

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
| [`webhook-architecture`](skills/webhook-architecture/) | Creating webhook handlers | SOLID handler registry, one handler per event, dependency injection, idempotency |
| [`security-and-compliance`](skills/security-and-compliance/) | New tables, auth flows, input validation | RLS enforcement, Zod at boundaries, webhook signatures, GDPR consent, SOC 2 checklist |
| [`testing`](skills/testing/) | Writing tests | Vitest patterns, Supabase mocking, Playwright page objects, `__tests__/` conventions |

### Tier 4: Workflow / Process

| Skill | When It Activates | What It Does |
|-------|------------------|--------------|
| [`feature-design`](skills/feature-design/) | Starting new features | Interactive brainstorming, 2-3 approach proposals, design specs before implementation |
| [`linear-tickets`](skills/linear-tickets/) | Creating issues or tickets | Rich tickets with user stories, architecture context, acceptance criteria, sub-task breakdown |
| [`pull-request`](skills/pull-request/) | Creating PRs | CI validation first, rich descriptions with summary + test plan |
| [`ci-pipeline`](skills/ci-pipeline/) | Modifying CI/CD | CI checks only (no deploy), cheapest-first ordering, extensible step pattern |
| [`route-colocation`](skills/route-colocation/) | Creating routes, organizing files | Colocate with routes, share at 3+ usages, actions folder pattern |

## Usage Examples

### In Claude Code

Skills activate automatically based on what you're doing. You can also invoke them directly:

```bash
# Skills auto-activate when context matches
> "Build a dashboard for order management"
# → design-taste + internal-tools-design + shadcn-components activate

# Or invoke directly with /skill-name
> /design-taste
> /react-architecture
```

**Example: Claude Code detects a bloated component**

```
You: "Refactor this UserProfile component, it's 800 lines"

Claude: I'll use the react-architecture skill to decompose this.

Based on the decomposition signals:
- File length: 800 lines (threshold: >500 → mandatory split)
- useState count: 22 (threshold: >15 → group into hooks)
- useEffect count: 7 (threshold: >4 → each effect owns one concern)

Extracting these hooks:
- useUserProfile() → profile state + fetch effect
- useNotifications() → notification state + polling effect
- useFormValidation() → form state + validation logic
...
```

**Example: Design taste catching AI slop**

```
You: "Create a landing page hero section"

Claude: Using design-taste skill (DESIGN_VARIANCE: 8).

Anti-center bias active — centered hero sections are banned
at this variance level. Using split-screen layout instead.

Checking AI tells:
✗ Inter font → switching to Geist
✗ Purple gradient accent → using Zinc base + Emerald accent
✗ 3-column feature cards → using asymmetric 2-column zig-zag
...
```

### In Cursor

1. **Enable skills:** Settings > Rules > toggle "Import Agent Skills"
2. Skills are automatically loaded from `.claude/skills/` (same path, same format)
3. Cursor reads the `description` field in SKILL.md frontmatter to decide when to activate

### In GitHub Copilot

```bash
# Generate Copilot instructions from your AGENTS.md
./.agents/modh-skills/install.sh . --all-agents
# Creates .github/copilot-instructions.md
```

Copilot reads `AGENTS.md` at the project root and `.github/copilot-instructions.md` for workspace-level instructions.

### In Windsurf

```bash
# Generate Windsurf rules
./.agents/modh-skills/install.sh . --all-agents
# Creates .windsurfrules
```

### In OpenAI Codex

Codex reads `AGENTS.md` natively — no extra setup needed after install.

## Selective Install

Install only the skill tiers your project needs:

```bash
# Just universal skills (works with any stack)
./install.sh . --tier=universal

# Universal + React/Next.js
./install.sh . --tier=universal --tier=react

# Backend only
./install.sh . --tier=backend

# Everything (default)
./install.sh .

# Everything + generate configs for all agents
./install.sh . --all-agents
```

**Tier contents:**

| Tier | Skills | Best For |
|------|--------|----------|
| `universal` | design-taste, internal-tools-design, output-enforcement, cross-editor-setup | Any project |
| `react` | react-architecture, nextjs-patterns, shadcn-components | React / Next.js apps |
| `backend` | supabase-patterns, observability, webhook-architecture, security-and-compliance, testing | Supabase / Node.js backends |
| `process` | feature-design, linear-tickets, pull-request, ci-pipeline, route-colocation | Team workflows |

## How Skills Work

### Anatomy of a Skill

```
design-taste/
├── SKILL.md              ← Loaded into agent context (<500 lines)
│                           Contains rules, patterns, anti-patterns
│                           Agent follows these while writing code
│
├── references/            ← Loaded on-demand when SKILL.md says "See references/X.md"
│   ├── creative-arsenal.md   Deep techniques library
│   └── design-audit.md       Full audit checklist
│
└── examples/              ← Optional, project-specific
    └── your-examples.md      Replace with your own
```

### SKILL.md Format

Every skill uses YAML frontmatter compatible with Claude Code, Cursor, and the AAIF standard:

```yaml
---
name: design-taste                    # Must match directory name
description: >                        # Keyword-rich — agents match on this
  Senior UI/UX design standards. Anti-AI pattern detection,
  typography rules, color calibration, performance guardrails.
  Use when building or reviewing any user-facing interface.
---

# Design Taste

## Core Rules
...
```

### Progressive Loading

Agents don't load all 17 skills at once. The process is:

1. **Startup:** Agent reads only `name` + `description` from each SKILL.md frontmatter
2. **Matching:** When your task matches a skill's description, the full SKILL.md is loaded
3. **Deep dive:** If the skill references `references/X.md`, those load only when needed

This keeps context windows lean — typically 1-3 skills active at a time.

## Updating Skills

```bash
cd .agents/modh-skills && git pull
```

Because install.sh creates **symlinks** (not copies), pulling updates to the submodule immediately updates all skills. No reinstall needed.

## Adding Your Own Skills

Your project can have local skills alongside the Modh pack:

```
.claude/skills/
├── design-taste/             → symlink (Modh pack)
├── react-architecture/       → symlink (Modh pack)
├── billing-patterns/         ← Your local skill
│   └── SKILL.md
└── my-api-integration/       ← Your local skill
    ├── SKILL.md
    └── references/
        └── api-docs.md
```

**To create a new skill:**

```bash
mkdir -p .claude/skills/my-skill
cat > .claude/skills/my-skill/SKILL.md << 'EOF'
---
name: my-skill
description: >
  When this skill activates and what it does.
  Use keyword-rich descriptions for better agent matching.
---

# My Skill

## Core Rules
1. Rule one
2. Rule two

## Anti-Patterns
| Pattern | Why It's Wrong | Do This Instead |
|---------|---------------|-----------------|
| ... | ... | ... |
EOF
```

## Writing Good Skills

See [docs/writing-skills.md](docs/writing-skills.md) for the complete guide. Key principles:

- **Under 500 lines** — SKILL.md is loaded into the agent's context window. Every line costs tokens.
- **Tables over prose** — `| Pattern | Fix |` is ~3x more token-efficient than paragraph explanations.
- **Rules, not suggestions** — "NEVER use console.log" beats "Consider using a structured logger".
- **Anti-patterns with fixes** — Show the wrong way AND the right way side by side.
- **Decision trees over paragraphs** — `Error in webhook? → use captureException()` beats a paragraph.
- **No project-specific references** — Use generic paths like `@/lib/` not `@/app/_shared/lib/`.
- **Reference files for depth** — Keep SKILL.md sharp; put full templates in `references/`.

## Architecture

```
How skills flow from this repo to your AI agents:

┌─────────────────────────────┐
│  modh-labs/agent-skills      │  ← This repo (git submodule)
│  └── skills/                 │
│      ├── design-taste/       │
│      ├── react-architecture/ │
│      └── ...                 │
└──────────────┬──────────────┘
               │ install.sh creates symlinks
               ▼
┌─────────────────────────────┐
│  your-project/               │
│  ├── .claude/skills/         │  ← Symlinks to submodule
│  │   ├── design-taste/ →     │
│  │   └── ...                 │
│  ├── AGENTS.md               │  ← Project rules (all agents read)
│  └── CLAUDE.md               │  ← "@AGENTS.md" (Claude Code entry)
└──────────────┬──────────────┘
               │ Agents read .claude/skills/ + AGENTS.md
               ▼
┌─────────────────────────────┐
│  AI Agents                   │
│  ├── Claude Code ✓           │
│  ├── Cursor ✓                │
│  ├── GitHub Copilot ✓        │
│  ├── Windsurf ✓              │
│  └── OpenAI Codex ✓          │
└─────────────────────────────┘
```

## FAQ

**Q: Do I need Claude Code to use this?**
No. The skills work with any agent that reads `.claude/skills/` (Claude Code, Cursor) or `AGENTS.md` (Copilot, Codex, Windsurf). The `--all-agents` flag generates config files for non-Claude agents.

**Q: Will this slow down my agent?**
No. Skills use progressive loading — only the name and description are read at startup (~1 line each). The full skill loads only when the agent's task matches. Typical usage: 1-3 skills active at a time.

**Q: Can I override a skill for my project?**
Yes. Delete the symlink and create a local directory with the same name. install.sh never overwrites existing directories.

**Q: How do I add a skill to the pack?**
See [docs/contributing.md](docs/contributing.md). Fork, add your skill following the structure, and submit a PR.

**Q: What's the difference between skills and AGENTS.md?**
AGENTS.md contains project-level rules that are always loaded (tech stack, critical rules, file structure). Skills are specialized knowledge that loads on-demand when relevant to the current task.

**Q: Can I use this with a non-TypeScript project?**
Yes. Tier 1 (universal) and Tier 4 (process) skills are language-agnostic. Tier 2 (React) and Tier 3 (backend) are TypeScript/Supabase-focused but the patterns transfer to other stacks.

## Stats

| Metric | Value |
|--------|-------|
| Total skills | 17 |
| SKILL.md total lines | ~5,000 |
| Reference docs | 14 |
| Average skill size | 297 lines |
| Largest skill | shadcn-components (452 lines) |
| Smallest skill | output-enforcement (49 lines) |
| Aura-specific references | 0 |
| Compatible agents | 5+ |

## About This Pack

These are the skills I actually use across my projects at [Modh Labs](https://github.com/modh-labs). They've been refined through building production SaaS apps — finding what works, what the AI keeps getting wrong, and encoding those lessons so I don't have to repeat myself.

I'm sharing them because I think they're useful. Take what works for you, ignore what doesn't. Your mileage may vary — every project is different, and these skills encode *my* opinions about how code should be written. They're strong opinions, loosely held.

### Inspiration & Credit

These skills didn't come out of nowhere. A lot of the ideas, patterns, and structures were inspired by excellent work from the open-source community:

- **[Antiprompts / High-Agency Frontend Skill](https://github.com/sickn33/antiprompts-high-agency-frontend-skill)** by sickn33 — The tunable dials system, AI pattern detection, and Creative Arsenal concepts in `design-taste` draw heavily from this. Genuinely one of the best frontend skills out there.
- **[Superpowers Skills](https://github.com/superpowers-ai/superpowers)** — The brainstorming, TDD, debugging, and planning workflow skills that shaped how `feature-design` and our overall process skills work. We keep superpowers as a separate global install and recommend you do too.
- **[Vercel Engineering Skills](https://github.com/nicepkg/agent-skills)** — React composition patterns, performance optimization rules, and best practices that informed `react-architecture` and `nextjs-patterns`.
- **[Supabase Postgres Best Practices](https://github.com/nicepkg/agent-skills)** — RLS patterns and query optimization that shaped `supabase-patterns`.
- **[AGENTS.md Standard](https://agents.md/)** (AAIF / Linux Foundation) — The cross-editor configuration conventions behind `cross-editor-setup`.
- **[Anthropic](https://anthropic.com)** — For Claude Code and the SKILL.md framework that makes all of this possible.

The consolidated skills in this repo merge ideas from multiple sources, add patterns from our own production experience, and generalize everything for portability. The foundational ideas belong to their original creators — we just stitched together the best parts and pressure-tested them in real projects.

## License

MIT — use freely in personal and commercial projects.
