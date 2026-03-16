---
title: "Feature Design"
subtitle: "Think before you code — 2-3 approaches, then decide"
chapter: 17
section: "Process"
seo_title: "Feature Design Process — Think Before You Code, Ship With Confidence 2026"
seo_description: "Stop building the first thing that comes to mind. Explore 2-3 approaches, document trade-offs, align the team, then build with conviction. Ship faster by thinking first."
keywords: ["feature design", "design process", "engineering process", "trade-off analysis", "decision-making", "architecture decisions"]
reading_time: "8 min"
difficulty: "intermediate"
tech_stack: ["Next.js", "Supabase", "TypeScript"]
business_case: "Teams that spend 2 hours designing before coding ship in 3 days. Teams that start coding immediately spend 3 days building and 3 more days rebuilding."
---

# Feature Design

> "The most expensive line of code is the one you wrote before you understood the problem."

## The Problem

Monday morning. A ticket lands: "Add bulk actions to the orders table." The developer opens their editor, creates a branch, and starts building. They add checkboxes to each row, a floating action bar, a confirmation dialog, and a server action that loops through selected IDs.

By Wednesday, it works. They open a PR. The review comes back: "Why didn't we use a background job for this? If someone selects 500 orders, this will timeout." They didn't consider that. They rearchitect — add a job queue, a progress indicator, a status polling mechanism. Friday, they open a new PR.

The second review: "The PM wanted this to work on filtered results, not just selected rows. 'Bulk action on all 2,347 orders matching this filter.'" That's a fundamentally different design. The checkbox approach doesn't support it. They start over.

The feature ships the following Wednesday. Ten days for what should have been four. Not because the developer was slow — because they solved the wrong problem first, then solved it wrong, then solved it right.

This pattern repeats constantly on teams that treat code as the thinking medium. Writing code is not thinking. Writing code is executing a plan. If you start executing before you have a plan, you will build the wrong thing, build it the wrong way, or both.

The most dangerous moment in a feature's lifecycle is the ten minutes after a developer reads the ticket and before they open their editor. That's when the first approach locks in — usually the most obvious one, not the best one. Every hour of coding after that increases the sunk-cost resistance to changing direction.

## The Principle

Every feature that takes more than a day gets a design step: identify 2-3 viable approaches, document the trade-offs, pick one, and get alignment before writing a single line of implementation code.

This is not a heavyweight process. It's not a design committee or an architecture review board. It's a developer spending 30-90 minutes thinking about the problem space, writing down the options, and making a deliberate choice. The output is a few paragraphs, not a document.

The time investment pays for itself immediately. Two hours of design prevents two days of rework. Every single time.

## The Pattern

### Classify the decision first

Not every change needs a design step. Use the one-way door / two-way door framework:

**Two-way doors** are easily reversible. Component naming, CSS choices, internal API structure, test organization. Just ship it. If it's wrong, change it in an hour.

**One-way doors** are expensive to reverse. Database schema changes, public API contracts, third-party integrations, billing logic, data model decisions. These need the design step.

The heuristic: if reversing the decision requires a migration, API versioning, or affects user-facing behavior, it's a one-way door. Design first.

### The design exploration

For one-way door decisions, explore the problem before committing to a solution. This takes 30-90 minutes and produces a structured comparison.

```markdown
## Feature: Bulk Order Actions

### Problem
Users need to perform actions (archive, assign, export) on multiple
orders at once. Current UI only supports one-at-a-time.

### Approach A: Client-side selection + server action
- User checks boxes, clicks action, server action loops through IDs
- Pro: Simple implementation, instant UI feedback
- Con: Timeouts on large selections (>100 orders), no progress feedback
- Con: Only works on visible rows, not filtered results

### Approach B: Server-side filter-based actions
- User applies filters, clicks "Apply to all matching", server action
  uses the filter criteria (not IDs) to update
- Pro: Works on any number of orders, no pagination dependency
- Con: More complex — needs filter serialization, count confirmation
- Pro: Matches how users think ("update all pending orders")

### Approach C: Background job queue
- User selects action, job queued, progress shown via polling or SSE
- Pro: Handles any volume, no timeout risk
- Con: Significant infrastructure (job queue, status tracking, progress UI)
- Con: Overkill for most use cases (<100 orders)

### Decision: Approach B with Approach C as future enhancement
- Filter-based actions cover 90% of use cases without infrastructure overhead
- Add queue for truly large operations (>1000) in a future iteration
- Reversibility: Medium — filter serialization is reusable if we switch to C
```

### Scoping: break it down before you build

Every feature over five days must be broken into independently shippable milestones. Each milestone delivers user value on its own.

Bad breakdown (not independently shippable):
1. Build database schema
2. Build API endpoints
3. Build UI

Good breakdown (each milestone ships value):
1. Filter-based count display — "2,347 orders match your filters" (demonstrates the filter serialization, ships as informational value)
2. Bulk archive action — single action using filter criteria (proves the pattern end-to-end)
3. Additional bulk actions — assign, export, status change (incremental features using the proven pattern)

Each milestone is a separate ticket. Each can be deployed independently. Each delivers something the user can see and use.

### The decision timeline

For two-way doors: decide immediately, ship in your PR.

For one-way doors: 24-48 hours maximum. Post the design exploration in the ticket or PR. Team members react or comment. After 48 hours, the proposer makes the final call and documents the decision.

If 48 hours pass with no feedback, that's a decision too — it means nobody has concerns strong enough to voice. Ship it.

### When to defer, when to build

Build now if:
- A real user requested it. Not a hypothetical user. A person with a name who described a pain point.
- It blocks planned work. The feature is an enabler for the next milestone.
- It fixes a production issue. Users are experiencing pain right now.

Defer if:
- "It would be nice to have." That's not a reason. That's a wish.
- "We might need this later." Build it when you actually need it.
- "This could be slow at scale." Do you have scale? Build for today, optimize when data demands it.

### Trade-off documentation

For one-way door decisions, the design exploration lives in the ticket or PR description. Future developers need to understand not just what you chose, but why you chose it and what you rejected.

```markdown
## Decision: Filter-based bulk actions (not client-side selection)

**Problem:** Need bulk order operations for users with large order volumes.

**Chosen:** Filter-based approach (Approach B)

**Why:** Matches user mental model ("update all pending orders"), handles
any volume without timeout risk, and doesn't require job queue infrastructure.

**Rejected:** Client-side selection (timeouts >100 items, pagination-dependent)
and background jobs (infrastructure overhead not justified for current volume).

**Reversibility:** Medium. Filter serialization logic is reusable. Switching
to background jobs later would be additive, not a rewrite.
```

This takes five minutes to write and saves hours of archaeological investigation when someone revisits the decision six months later.

### The anti-patterns

**Analysis paralysis.** Three days debating the perfect solution. The design step is 30-90 minutes, not a research project. Set a deadline. Most decisions can be made with 70% of the information.

**Consensus-seeking.** Waiting for everyone to agree. One engineer proposes. Others review. The proposer decides. Unanimous agreement is neither required nor realistic.

**Building for hypothetical users.** "A enterprise customer might want configurable widgets." Do you have that customer? Are they asking for it? No? Then don't build it.

**Perfectionism.** "This could be 10% better, so I won't ship it." Ship the 90% solution. Iterate later if users demand the remaining 10%. Most of the time, they won't.

## The Business Case

- **Predictable delivery.** Teams that design before coding hit their estimates. Teams that don't spend half their time on rework and course corrections. The 30-minute design step is the single highest-leverage activity in the development process.
- **Better technical decisions.** The first approach is rarely the best approach. By forcing yourself to consider two alternatives, you often discover a simpler or more extensible solution that you wouldn't have found while heads-down coding.
- **Reduced review cycles.** When the approach is aligned before implementation, PR reviews focus on code quality, not architectural direction. Reviews that devolve into "should we even be doing it this way?" are a symptom of missing design work.

## Try It

Install the Modh Playbook skills to enforce this pattern automatically:
```bash
# Add to your project
git submodule add https://github.com/modh-labs/playbook .agents/modh-playbook
./.agents/modh-playbook/install.sh
```
