# Writing Skills

A guide to creating effective AI agent skills — whether for this repo or your own project.

## The Golden Rule

**A skill is a contract between you and the AI agent.** If a rule is in the skill, the agent follows it. If it's ambiguous, the agent guesses. Write skills like you're writing a spec for a junior developer who is very literal but very fast.

## Skill Structure

```
my-skill/
├── SKILL.md              # Required. The main instruction set.
├── references/            # Optional. Deep docs loaded on-demand.
│   ├── template.ts
│   └── advanced-patterns.md
└── examples/              # Optional. Project-specific examples.
    └── real-usage.md
```

### SKILL.md Requirements

Every SKILL.md needs YAML frontmatter:

```yaml
---
name: my-skill                        # kebab-case, matches directory name
description: >                        # Keyword-rich for agent matching
  What this skill does and when it activates.
  Include action words: "Use when adding...", "Enforces...", "Prevents..."
---
```

**The description is critical.** Agents decide whether to load your skill based on this description. Include:
- Action verbs ("Use when...", "Enforces...", "Prevents...")
- Specific keywords the agent can match against ("webhook", "testing", "shadcn", "RLS")
- What problems it solves ("Prevents console.log", "Ensures trace correlation")

## Token Budget

Skills are loaded into the agent's context window. Every line costs tokens. Be ruthless about density.

| Target | Max Lines | Why |
|--------|-----------|-----|
| SKILL.md | 500 | Loaded into context — every line counts |
| Individual reference file | 500 | Loaded on-demand, but still costs tokens |
| Code example in SKILL.md | 15 | Longer examples go in references/ |

### Token-Efficient Patterns

**Tables over prose** (3x more efficient):

```markdown
<!-- BAD: 6 lines, low density -->
When you encounter an error in a webhook handler, you should use the
webhook logger's failure method. When you encounter an error in a
server action, you should use the module logger's error method combined
with the domain capture function. When you encounter an error in an
AI agent call, the instrumented wrapper captures it automatically.

<!-- GOOD: 5 lines, high density, scannable -->
| Error Location | Use This |
|----------------|----------|
| Webhook handler | `logger.failure(error)` |
| Server action | `logger.error()` + `captureException()` |
| AI agent call | Auto-captured by instrumented wrapper |
```

**Decision trees over paragraphs:**

```markdown
<!-- GOOD -->
Error in webhook?     → logger.failure(error)
Error in action?      → logger.error() + captureException()
Error in AI agent?    → Auto-captured
Need duration?        → Sentry.startSpan()
Need search filter?   → setTag() (low cardinality)
Need debug data?      → setContext() (not searchable)
```

**Side-by-side wrong/right:**

```markdown
<!-- GOOD -->
// Wrong — raw console
console.log("Processing", id);

// Correct — structured logger
logger.info("Processing item", { item_id: id });
```

## Anatomy of a Good Skill

### 1. When This Skill Activates (2-5 lines)

Tell the agent exactly when to use this skill:

```markdown
## When This Skill Activates

- Creating or modifying React components over 300 lines
- Extracting custom hooks from complex components
- Discussing state management patterns or hydration issues
```

### 2. Core Rules (the meat)

These are the rules the agent must follow. Use MUST/NEVER/ALWAYS language:

```markdown
## Core Rules

### 1. NEVER Use Browser APIs in useState Initializers

// Wrong — hydration mismatch
const [id] = useState(() => crypto.randomUUID());

// Correct — deterministic init, populate on mount
const [id, setId] = useState<string | null>(null);
useEffect(() => setId(crypto.randomUUID()), []);
```

### 3. Decision Trees

For complex decisions, give the agent a flowchart:

```markdown
## Decision Tree

Component >500 lines?     → Mandatory decomposition
>15 useState declarations? → Group into custom hooks
>4 useEffect hooks?        → Each effect owns one concern
Same value computed 3x?    → Compute once at top
>5 pass-through props?     → Consider context or restructure
```

### 4. Anti-Patterns Table

Show what NOT to do with clear fixes:

```markdown
## Anti-Patterns

| Pattern | Why It's Wrong | Do This Instead |
|---------|---------------|-----------------|
| `useState` for derivable value | Unnecessary state, extra re-renders | `const x = !!otherState` |
| Dead state (setter never called) | Bloat, confusion | Delete entirely |
| `useEffect` with 8+ deps | Unintended re-fires, bugs | Break into focused hooks |
```

### 5. Quick Audit Checklist

A pre-ship checklist the agent runs through:

```markdown
## Quick Audit Checklist

- [ ] No browser APIs in useState initializers
- [ ] No dead state (unused setters or unread values)
- [ ] Each useEffect owns exactly one concern
- [ ] File under 500 lines
```

### 6. Reference Pointers (optional)

Point to deeper content without bloating SKILL.md:

```markdown
## References

- Full migration workflow: `references/migration-workflow.md`
- Handler template: `references/handler-template.ts`
```

## Naming Conventions

| Convention | Example | Why |
|-----------|---------|-----|
| **kebab-case** | `react-architecture` | Consistent with AAIF standard |
| **Domain-first** | `react-architecture` not `architecture-react` | Scannable in file listings |
| **No `-skill` suffix** | `testing` not `testing-skill` | The directory IS a skill |
| **No `-patterns` suffix** | `observability` not `observability-patterns` | Shorter, cleaner |
| **Max 2-3 words** | `design-taste`, `webhook-architecture` | Memorable, typeable |
| **Directory = name field** | dir `testing/` → `name: testing` | Required by AAIF standard |

## Common Mistakes

| Mistake | Why It Fails | Fix |
|---------|-------------|-----|
| Vague description | Agent can't match to tasks | Use specific keywords and action verbs |
| Suggestions instead of rules | Agent treats them as optional | Use MUST/NEVER/ALWAYS |
| Project-specific imports | Breaks when used elsewhere | Use generic paths with comments |
| Prose-heavy content | Burns tokens, hard to scan | Use tables and decision trees |
| 1000+ line SKILL.md | Exceeds token budget | Move depth to references/ |
| No anti-patterns section | Agent doesn't know what to avoid | Always show wrong AND right |
| No checklist | Agent skips verification | Add a quick audit checklist |

## Portability Rules

For skills in this repo (meant to be used across projects):

1. **No project names** — Use "your project" not "Acme" or "MyApp"
2. **No hardcoded paths** — Use `@/lib/` with a comment, not `@/app/_shared/lib/`
3. **No framework lock-in** — Mention the pattern, not the exact import
4. **Generic entity names** — Use "items", "orders", "users" not domain-specific terms
5. **Comment import sources** — `// your project's structured logger` not a specific module
