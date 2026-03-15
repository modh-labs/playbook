# Contributing

Want to add a skill to the Modh pack? Here's how.

## Adding a New Skill

### 1. Create the directory

```bash
mkdir -p skills/my-skill
```

### 2. Write the SKILL.md

```bash
cat > skills/my-skill/SKILL.md << 'EOF'
---
name: my-skill
description: >
  Clear, keyword-rich description of when this activates
  and what it enforces. Use action verbs.
---

# My Skill

## When This Skill Activates

- Specific trigger 1
- Specific trigger 2

## Core Rules

### 1. Rule Name

...

## Anti-Patterns

| Pattern | Fix |
|---------|-----|
| ... | ... |

## Quick Audit Checklist

- [ ] Check 1
- [ ] Check 2
EOF
```

### 3. Validate

Run these checks before submitting:

```bash
# SKILL.md under 500 lines
wc -l skills/my-skill/SKILL.md

# Directory name matches name: field
grep 'name:' skills/my-skill/SKILL.md

# No project-specific references
grep -i 'aura\|@/app/_shared\|your-company' skills/my-skill/SKILL.md
# Should return nothing

# Frontmatter present
head -3 skills/my-skill/SKILL.md
# Should show --- / name: / description:
```

### 4. Add to install.sh

Add your skill name to the appropriate tier array in `install.sh`:

```bash
TIER_UNIVERSAL=(design-taste internal-tools-design output-enforcement cross-editor-setup)
TIER_REACT=(react-architecture nextjs-patterns shadcn-components my-skill)  # ← here
```

### 5. Submit PR

```bash
git checkout -b add-my-skill
git add skills/my-skill/ install.sh
git commit -m "feat: add my-skill"
gh pr create --title "feat: add my-skill" --body "## What
Brief description of the skill.

## Tier
Which tier it belongs to and why.

## Checklist
- [ ] SKILL.md under 500 lines
- [ ] Directory name matches name: field
- [ ] No project-specific references
- [ ] Frontmatter with name and description
- [ ] Added to install.sh tier array"
```

## Guidelines

- **One skill, one concern** — Don't create a skill that covers testing AND deployment
- **Generic first** — No references to specific projects or companies
- **Tables over prose** — More token-efficient, easier to scan
- **Rules, not suggestions** — MUST/NEVER/ALWAYS language
- **Include anti-patterns** — Show what NOT to do alongside what TO do
- **Reference files for depth** — Keep SKILL.md under 500 lines

See [writing-skills.md](writing-skills.md) for the full writing guide.
