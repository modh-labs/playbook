---
name: cross-editor-setup
description: Ensure AI configuration works across Claude Code, Cursor, Copilot, Windsurf, and Codex. Use when creating AGENTS.md files, adding skills, setting up project rules, or discussing cross-editor compatibility. Enforces the @import convention and single-source-of-truth strategy.
tier: universal
icon: settings-2
title: "Cross-Editor AI Setup"
seo_title: "Cross-Editor AI Setup — Modh Engineering Skill"
seo_description: "Ensure AI configuration works across Claude Code, Cursor, Copilot, Windsurf, and Codex. Enforces the @import convention and single-source-of-truth strategy."
keywords: ["cross-editor", "AI setup", "AGENTS.md", "Claude Code", "Cursor"]
difficulty: beginner
related_chapters: []
related_tools: []
---

# Cross-Editor Setup Skill

## When This Skill Activates

This skill automatically activates when you:
- Create a new `AGENTS.md` file in any directory
- Create or modify a skill in `.claude/skills/`
- Discuss Cursor vs Claude Code vs Copilot vs Windsurf configuration
- Set up project rules for a new directory or package

## Core Rule: AGENTS.md is the Source of Truth

Every directory that needs AI context has two files:

```
AGENTS.md   <- real file (source of truth, Cursor/Copilot/Codex read natively)
CLAUDE.md   <- contains "@AGENTS.md" (Claude Code resolves the import)
```

**Why:** Most AI coding agents read `AGENTS.md` natively (root and subdirectories). Claude Code reads `CLAUDE.md` and uses `@` import syntax to resolve the content from `AGENTS.md`. One source of truth, all editors served.

## Cross-Agent Compatibility

| Agent | Config Location | Format | Notes |
|-------|----------------|--------|-------|
| **Claude Code** | `.claude/skills/` + `CLAUDE.md` | YAML frontmatter + MD | Reads `CLAUDE.md`, resolves `@AGENTS.md` imports |
| **Cursor** | `.claude/skills/` (Import Agent Skills toggle) | Same | Reads `AGENTS.md` natively + `.cursor/rules/` |
| **GitHub Copilot** | `.github/copilot-instructions.md` + `AGENTS.md` | Plain MD | Reads `AGENTS.md` natively in all directories |
| **Windsurf** | `.windsurfrules` or `.windsurf/rules/` | Plain MD | Project-level rules file or rules directory |
| **Codex** | `AGENTS.md` | Plain MD | Reads `AGENTS.md` natively |

## What Goes Where

| Config Type | Location | Claude Code | Cursor | Copilot | Windsurf | Action |
|-------------|----------|-------------|--------|---------|----------|--------|
| Core project rules | `AGENTS.md` (root) | Via `@AGENTS.md` in CLAUDE.md | Native | Native | Copy to `.windsurfrules` | Edit `AGENTS.md` |
| Directory context | `<dir>/AGENTS.md` | Via `<dir>/CLAUDE.md` import | Native | Native | Not supported | Edit `AGENTS.md` |
| AI skills | `.claude/skills/*/SKILL.md` | Native | Native (toggle) | Not supported | Not supported | No duplication needed |
| Cursor-only rules | `.cursor/rules/*.mdc` | Not read | Native | Not read | Not read | Only Cursor-specific behavior |
| Copilot instructions | `.github/copilot-instructions.md` | Not read | Not read | Native | Not read | Copilot-specific overrides |
| Windsurf rules | `.windsurfrules` | Not read | Not read | Not read | Native | Windsurf-specific overrides |

## When Creating New Directory Context

Follow this exact sequence:

1. Write `AGENTS.md` with the directory context content
2. Create `CLAUDE.md` in the same directory with just one line:
   ```
   @AGENTS.md
   ```
3. Verify: `cat AGENTS.md` shows your content, `cat CLAUDE.md` shows `@AGENTS.md`

## Setting Up Each Editor

### Claude Code (works out of the box)

No extra setup needed. Claude Code reads:
- Root `CLAUDE.md` (which imports `AGENTS.md`)
- All `CLAUDE.md` files in subdirectories
- All `.claude/skills/*/SKILL.md` files

### Cursor

One manual step for team members:

**Cursor Settings > Rules > "Import Agent Skills"** -- Enable this toggle.

This makes Cursor scan `.claude/skills/` for all `SKILL.md` files and use them the same way Claude Code does. Cursor also reads `AGENTS.md` natively in root and subdirectories.

### GitHub Copilot

1. Create `.github/copilot-instructions.md` with project-wide instructions
2. Copilot reads `AGENTS.md` files natively in all directories
3. For skills, you may need to reference key rules in `copilot-instructions.md` since Copilot does not read `.claude/skills/`

### Windsurf

1. Create `.windsurfrules` in the project root with core project rules (copy key content from `AGENTS.md`)
2. Alternatively, create `.windsurf/rules/` directory with multiple rule files
3. Windsurf does not read `AGENTS.md` or `.claude/skills/`, so critical rules must be duplicated

### Codex (OpenAI)

No extra setup needed. Codex reads `AGENTS.md` natively. It does not read `.claude/skills/`, so skills are not available.

## NEVER Do These

- **NEVER put content directly in `CLAUDE.md`** — it should only contain `@AGENTS.md`. All content goes in `AGENTS.md`.
- **NEVER create `AGENTS.md` and `CLAUDE.md` with different content** — that causes drift.
- **NEVER duplicate skills into `.cursor/rules/`** — Cursor reads `.claude/skills/` natively when "Import Agent Skills" is enabled.
- **NEVER skip creating `CLAUDE.md`** when adding an `AGENTS.md` — Claude Code users won't get the context.
- **NEVER maintain the same rules in 4 different formats** — pick `AGENTS.md` as the source of truth and only duplicate to editor-specific files when that editor cannot read `AGENTS.md`.

## Skills: Zero Duplication (Claude Code + Cursor)

Skills in `.claude/skills/*/SKILL.md` work in both Claude Code and Cursor. The frontmatter format is compatible:

```yaml
---
name: skill-name
description: When this skill activates...
allowed-tools: Read, Grep, Glob
---
```

Both Claude Code and Cursor use the `description` field to decide when to load the skill. No transformation or conversion needed.

For editors that do not support `.claude/skills/` (Copilot, Windsurf, Codex), extract the most critical rules into their respective config files. Accept that full skill parity across all editors is not practical — focus on getting the core rules right everywhere.

## Maintenance Checklist

When adding a new `AGENTS.md` to a directory:
- [ ] `AGENTS.md` contains all the content
- [ ] `CLAUDE.md` exists in the same directory with only `@AGENTS.md`
- [ ] Content is tested in at least one editor (Claude Code or Cursor)

When adding a new skill:
- [ ] Created in `.claude/skills/<name>/SKILL.md`
- [ ] Has YAML frontmatter with `name` and `description`
- [ ] Verified Cursor picks it up (Settings > Rules > Import Agent Skills)
