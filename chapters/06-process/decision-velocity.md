---
title: "Decision Velocity"
subtitle: "One-way doors vs two-way doors"
chapter: 21
section: "Process"
seo_title: "Decision Velocity for Engineering Teams — Ship Fast Without Breaking Things (2026)"
seo_description: "A framework for classifying decisions as reversible or irreversible, then moving at the right speed for each."
keywords: ["decision velocity", "one-way door", "two-way door", "engineering decisions", "shipping speed", "analysis paralysis"]
reading_time: "7 min"
difficulty: "beginner"
tech_stack: ["Next.js", "Supabase", "TypeScript"]
business_case: "Eliminate weeks of unnecessary deliberation on reversible decisions while protecting irreversible ones with structured trade-off analysis."
---

# Decision Velocity

> "Good enough to ship beats perfect in a branch."

## The Problem

Engineering teams slow down for one of two reasons, and both are expensive.

The first is analysis paralysis. Every decision — component naming, CSS approach, internal API shape — becomes a committee discussion. Three engineers spend two hours debating whether to use `orderItems` or `lineItems` as a variable name. The meeting ends without a decision. They schedule another meeting for Thursday. Meanwhile, no code ships.

The second is recklessness. A database schema change goes in without review. A public API contract changes without documentation. Billing logic ships with a one-line code review. Two months later, the schema change requires a painful migration, the API change broke a partner integration, and the billing logic has been silently overcharging customers.

Both failures share the same root cause: the team treats all decisions with the same level of scrutiny. They either deliberate everything (slow) or deliberate nothing (dangerous). The solution is to classify decisions by their reversibility and match the scrutiny to the stakes.

## The Principle

We borrow Amazon's "one-way door / two-way door" framework and make it specific to engineering.

**Two-way doors** are decisions you can easily reverse. Component structure, CSS styling, internal API shape, logging instrumentation, test organization — all of these can be changed in less than an hour of work. The cost of a wrong decision is an hour of refactoring. The cost of deliberating is days of lost shipping velocity.

**One-way doors** are decisions that are expensive, risky, or time-consuming to reverse. Database schema changes require migrations. Public API contracts affect external consumers. Authentication patterns touch every route. Billing logic handles real money. Reversing any of these requires significant effort, user communication, or both.

The framework:

| Decision Type | Examples | Who Decides | Review Needed | Timeline |
|---------------|----------|-------------|---------------|----------|
| Two-way door | Component names, styling, copy, internal APIs, feature flags, test structure | Individual engineer | No | Immediately |
| One-way door | Schema changes, public APIs, auth patterns, billing, third-party integrations | Engineer proposes, team reviews | Yes | 24-48 hours max |

**Default to autonomy.** Engineers make most decisions without approval. Speed matters. Waiting for consensus slows everything down. Most decisions are reversible.

**The one-hour rule:** If you can reverse this decision with less than one hour of work, it is a two-way door. Ship it. Do not ask permission.

## The Pattern

### The Ship-Now Checklist

Before every feature ships, run through this checklist. If all boxes are checked, merge and deploy.

- **Core workflow works** — The happy path is complete
- **Edge cases are handled** — Error states, loading states, empty states exist
- **No data loss risk** — Users will not lose work or data
- **Tests pass** — CI is green
- **Documented** — Future you can understand this code

If all five pass: ship now. Do not wait for perfection.

### The Keep-Iterating Checklist

If any of these are true, do not ship:

- **Core workflow is broken** — The happy path does not work
- **Data loss risk** — Users could lose work or data
- **Major UX issues** — Confusing, error-prone, or inaccessible
- **Security vulnerability** — XSS, SQL injection, auth bypass
- **CI is failing** — Tests fail, linting errors, type errors

### Trade-Off Documentation for One-Way Doors

When making a one-way door decision, document the trade-offs. This takes five minutes and saves hours of future confusion.

```markdown
## Decision: [Brief description]

**Problem:** [What problem does this solve?]

**Options Considered:**

1. **Option A:** [Description]
   - Pros: [List benefits]
   - Cons: [List downsides]

2. **Option B:** [Description]
   - Pros: [List benefits]
   - Cons: [List downsides]

**Chosen:** Option [A/B]

**Why:** [1-2 sentences explaining the trade-off]

**Reversibility:** [How hard would it be to undo this later?]
```

**Example:**

```markdown
## Decision: Use hosted checkout instead of custom payment form

**Problem:** Need to collect payments for the pro tier.

**Options Considered:**

1. **Hosted checkout page:**
   - Pros: Fast to implement, PCI compliant by default, supports all methods
   - Cons: Less customizable, redirects users away

2. **Custom payment form:**
   - Pros: Fully customizable, keeps users on site
   - Cons: More work, PCI compliance burden, harder to maintain

**Chosen:** Hosted checkout

**Why:** Speed matters more than customization right now. We can
migrate to a custom form later if needed.

**Reversibility:** Medium — would require rebuilding checkout UI,
but both patterns are supported by the payment provider.
```

### Common Decision Patterns

**"Should I refactor this now or later?"**
Ship now if the code works and is tested. Refactor now only if the code is actively confusing and you are about to build on top of it. Refactor when you touch the code, not speculatively.

**"Should I add this feature or keep it simple?"**
Add it if a user explicitly requested it and it solves a real pain point. Keep it simple if no user asked for it and it adds complexity without clear value. Simplicity wins. Add features only when there is demand.

**"Should I build this abstraction or copy-paste?"**
Build an abstraction if the pattern is used in three or more places and the logic is complex enough that duplication risks bugs. Copy-paste if the pattern is used in fewer than three places and the logic is simple. Abstract on the third use, not the first.

**"Should I write a doc for this?"**
Write a doc if you are introducing a new pattern, making a one-way door decision, or solving a problem others will encounter. Skip the doc if you are following an existing pattern (link to it in the PR) or making a two-way door decision where the code is self-explanatory.

### Scope Decisions: Build vs Skip

**Build now if:**
- A user explicitly requested it
- It blocks a planned feature
- It fixes a production bug
- It removes tech debt that is slowing current work

**Skip (or defer) if:**
- No user asked for it
- It is speculative optimization without data
- It is over-engineering for hypothetical future requirements
- Fewer than 10 users would benefit

**Rule:** If you are unsure whether to build something, do not build it. Wait for user pain.

### Red Flags: When to Stop and Discuss

Even with autonomy, some situations warrant a pause:

- **Multiple engineers disagree** — Seek alignment before shipping
- **User data at risk** — Data loss, privacy, security concerns
- **Breaking change to a public API** — Affects external integrations
- **High cost or irreversible** — Expensive migration, third-party commitment
- **Unclear requirements** — You do not understand the problem well enough

Escalate asynchronously. Post in your project management tool with a mention, or flag in chat. Set a 24-48 hour decision deadline. The proposer makes the final call after feedback.

### Anti-Patterns

**Analysis paralysis.** Spending days debating the perfect solution. Fix: set a decision deadline. Most one-way doors can be decided in 24-48 hours.

**Consensus-seeking.** Waiting for everyone to agree before shipping. Fix: one engineer proposes, others review, the proposer decides.

**Perfectionism.** "This could be 10% better, so I will not ship it." Fix: ship the 90% solution now, iterate to 100% later if needed.

**Ignoring trade-offs.** Choosing an option without considering downsides. Fix: use the trade-off documentation template for one-way doors.

**Building for hypothetical users.** "Some user might want this feature someday." Fix: build for real users with real needs. Ship when demand exists.

## The Business Case

**Shipping velocity doubles.** When two-way doors ship immediately and one-way doors resolve within 48 hours, the team spends its time building instead of debating.

**Decision quality improves.** Counterintuitively, faster decisions produce better outcomes. Two-way doors get validated in production (the best feedback loop). One-way doors get focused scrutiny because the team's deliberation energy is concentrated on the decisions that actually matter.

**Engineering morale rises.** Engineers who ship daily feel productive. Engineers who attend three meetings to decide a variable name feel demoralized. Autonomy and trust compound into engagement and retention.

**Risk is properly allocated.** Critical decisions (schema, billing, auth) get real review. Low-stakes decisions (naming, styling, test structure) get shipped and iterated. No resources are wasted protecting decisions that can be cheaply reversed.

## Try It

Install the [Modh Playbook](https://github.com/modh-ai/playbook) to get the decision velocity framework with the ship-now checklist, trade-off documentation template, and one-way/two-way door classification pre-configured for your engineering team.
