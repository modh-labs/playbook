# Modh Playbook

Read `/Users/igardezi/Repositories/modh/AGENTS.md` first.

## Purpose

This repository is the canonical source for portable Modh engineering skills and
the public engineering playbook.

## Rules

- A skill contains reusable procedural knowledge, not general repository context.
- Keep every `SKILL.md` concise, imperative, and below 500 lines where practical.
- Frontmatter contains only `name` and `description`.
- Public website and catalog metadata belongs in `skill-catalog.json`, keyed by
  skill directory.
- Put detailed domain references in `references/`, deterministic helpers in
  `scripts/`, and output material in `assets/`.
- Do not maintain divergent manual copies under consuming repositories.
- Run `ruby scripts/check_skill_frontmatter.rb` before publishing or projecting skills.
- Run `ruby scripts/consolidate_skill_metadata.rb` when migrating legacy
  frontmatter, then copy the catalog into the consuming website.
- Never copy client identifiers, credentials, or confidential incidents into a
  public skill.
