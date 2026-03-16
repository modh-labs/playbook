---
name: feature-design
description: Interactive feature design process from rough idea to implementation-ready spec. Use when brainstorming new features, fleshing out tickets, or planning multi-phase projects. Enforces a hard gate — no implementation until the design is approved.
tier: process
icon: lightbulb
title: "Feature Design Process"
seo_title: "Feature Design Process — Modh Engineering Skill"
seo_description: "Interactive feature design process from rough idea to implementation-ready spec. Enforces a hard gate — no implementation until the design is approved."
keywords: ["feature design", "specification", "planning", "design process", "implementation spec"]
difficulty: intermediate
related_chapters: []
related_tools: []
---

# Feature Design

Transform rough feature ideas into comprehensive, implementation-ready specifications through structured interactive dialogue.

## Hard Gate

**No implementation begins until the design is explicitly approved by the user.** The design phase is not a speed bump — it is the product. Rushing to code without a clear design contract leads to rework, scope creep, and misaligned outcomes.

The process is: **Explore -> Decide -> Design -> Approve -> Build.**

## When to Use

- Starting a new feature from a ticket or request
- Enriching a thin ticket with full design documentation
- Planning multi-phase feature rollouts
- Designing features that span multiple systems (DB + API + UI + background jobs)
- Brainstorming approaches with stakeholders before committing to a direction

---

## Process

### Phase 1: Context Gathering

**Goal:** Understand the full landscape before designing anything.

1. **Read the request** — Get the raw requirement from the ticket, message, or conversation
2. **Search for meeting notes** — Check if the team discussed this feature in recent meetings
3. **Explore existing code** — Map what already exists that can be reused or extended
4. **Check references** — Ask the user for competitor screenshots, examples, or inspiration

**Ask these questions (one at a time, not all at once):**
- "What problem does this solve for the user?"
- "Who are all the personas affected?" (end user, admin, prospect, support agent, engineer)
- "What exists today that we can build on?"
- "Are there competitor examples to reference?"

### Phase 2: Structured Design Questions

**Goal:** Make every design decision explicitly, one at a time.

**One question at a time.** Do not dump 10 questions on the user. Ask the most important question, get the answer, then ask the next one. Prefer multiple-choice format.

Present decisions as **visual choice cards** with clear tradeoffs:

```
Decision: [Topic]

Option A: [Name]
  Pros: ...
  Cons: ...

Option B: [Name]
  Pros: ...
  Cons: ...

Recommendation: [Option] because [reason]
```

**Common decisions to surface:**
- Default behavior (opt-in vs opt-out)
- Scope boundaries (what's in Phase 1 vs later)
- Data model (normalize vs denormalize, separate table vs column)
- Trigger mechanism (event-driven vs polling vs cron)
- Error handling (retry vs fail-fast vs degrade gracefully)
- Multi-tenant implications (isolation, permissions, org-scoping)
- Edge cases (what happens when X is empty? When Y fails? When Z has 10,000 items?)

### Phase 3: Propose Approaches

**Goal:** Give the user 2-3 concrete approaches to choose from before committing.

For each approach:
- **Name** — a short, memorable label
- **How it works** — 2-3 sentences
- **Pros** — what's good about this approach
- **Cons** — what's risky or limited
- **Estimated complexity** — files touched, systems involved (not time estimates)

**Always include your recommendation** with a clear reason. Users appreciate opinionated guidance.

### Phase 4: Architecture & Code Reuse Mapping

**Goal:** Map every existing file that can be reused or modified.

Create a table:

| What Exists | File/Module | How to Reuse It |
|-------------|-------------|-----------------|
| [existing capability] | [file path or module] | [extend, modify, or wrap] |

This prevents over-engineering. Reuse is always cheaper than greenfield.

### Phase 5: Phased Roadmap

**Goal:** Define clear phase boundaries with explicit scope.

For each phase:
- **What's included** (specific features)
- **What's NOT included** (scope boundaries — be explicit)
- **New infrastructure required** (tables, APIs, services)
- **Estimated complexity** (files touched, systems involved)
- **Can it ship independently?** (each phase should deliver user value)

**Phase boundaries are sacred.** Be explicit about what is NOT in Phase 1. Scope creep starts when boundaries are fuzzy.

### Phase 6: Detailed Design Document

**Goal:** Produce a comprehensive spec that an engineer (human or AI) can implement without follow-up questions.

Include:
1. **User stories** — As a [persona], I want [action], so that [benefit]
2. **Data model** — Tables, columns, relationships, indexes
3. **Service layer** — Functions, parameters, return types
4. **Integration points** — Which existing files to modify and how
5. **File map** — Every file to create or modify with purpose
6. **Edge cases** — Exhaustive list with expected behavior for each
7. **Diagrams** — Before/after, sequence, lifecycle, decision trees

### Phase 7: Ticket Creation (Optional)

**Goal:** Create a well-structured ticket with non-technical-first documentation.

If the project uses a ticketing system, structure the description:

1. **What is this?** (1-2 sentences, no jargon)
2. **The Problem** (business context, user pain, meeting references)
3. **The Solution** (walkthrough with named persona)
4. **Key Details Table** (scannable format for stakeholders)
5. **FAQ** (anticipate stakeholder questions)
6. **Technical Details** (collapsed section with full spec for implementers)

---

## Non-Technical Friendly Diagrams

When presenting designs to stakeholders who are not engineers, follow these rules:

### Use Named Personas, Not System Names

```
Bad:  User -> API -> DB -> Webhook -> Email Service
Good: Sarah (coach) -> books a call -> system notifies -> Alex (prospect) gets email
```

### Use Before/After Format

```
BEFORE (today):
  Sarah has to manually check her calendar, copy a link, and email it to Alex.
  If Alex reschedules, Sarah doesn't find out until she checks her inbox.

AFTER (with this feature):
  Sarah shares her booking page. Alex picks a time.
  If Alex reschedules, Sarah gets a push notification instantly.
```

### Keep Diagrams Simple

- Max 6 boxes in any diagram
- Use arrows with plain-language labels ("sends email", "updates record")
- No technical jargon in labels
- Color-code: green for new, gray for existing, red for removed

---

## Edge Case Analysis

For every feature, systematically consider:

| Category | Questions |
|----------|-----------|
| **Empty states** | What if there's no data yet? First-time user experience? |
| **Scale** | What if there are 10,000 items? Does the UI paginate? Does the query timeout? |
| **Permissions** | Who can see this? Who can edit? What about cross-org access? |
| **Concurrency** | What if two users edit the same thing simultaneously? |
| **Failure** | What if the external API is down? What if the database write fails? |
| **Undo** | Can the user reverse this action? Should they be able to? |
| **Migration** | What happens to existing data when this ships? |
| **Internationalization** | Timezones, currencies, date formats, character encodings? |

---

## Output Artifacts

At the end of the design process, you should have:

1. **Approved design** — The user has explicitly said "go" on an approach
2. **Design document** — Full spec with user stories, data model, edge cases, and file map
3. **Phased roadmap** — Clear scope boundaries for each phase
4. **Ticket(s)** — (Optional) Well-structured tickets ready for implementation

---

## Tips

- **Ask one decision at a time** — Don't overwhelm with 10 questions at once
- **Show your recommendation** — Users appreciate opinionated guidance
- **Map existing code early** — Reuse prevents over-engineering
- **Consider all personas** — Not just the happy-path user
- **Include the "what about X?" FAQ** — Anticipate stakeholder pushback
- **Phase boundaries are sacred** — Be explicit about what's NOT in Phase 1
- **Diagrams sell features** — Visual explanations beat walls of text for stakeholders
- **No implementation without approval** — This is a design skill, not a build skill
