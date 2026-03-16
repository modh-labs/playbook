---
title: "Linear Tickets"
subtitle: "User stories, architecture context, sub-task breakdown"
chapter: 18
section: "Process"
seo_title: "Writing Linear Tickets That Actually Ship — User Stories, Architecture, Acceptance Criteria 2026"
seo_description: "A ticket is a contract. Write tickets with user stories, architecture context, acceptance criteria, and sub-task breakdowns that let any engineer ship without follow-up questions."
keywords: ["Linear tickets", "user stories", "acceptance criteria", "engineering tickets", "project management", "issue tracking"]
reading_time: "8 min"
difficulty: "beginner"
tech_stack: ["Next.js", "Supabase", "TypeScript"]
business_case: "Well-written tickets eliminate the back-and-forth that adds 2-3 days to every feature. The 20 minutes spent writing a complete ticket saves 2 days of implementation time."
---

# Linear Tickets

> "A ticket without acceptance criteria is a wish. A ticket without architecture context is a trap."

## The Problem

"Add export functionality to orders."

That's the entire ticket. Six words. The developer reads it on Monday and starts building. They have questions immediately. Export to what format — CSV, Excel, PDF? Which fields? All orders or just the filtered view? Should it include related data like customer information? Is there a file size limit? Does it need to work for 100,000 orders or just the visible page?

They post a comment on the ticket. The PM responds Tuesday afternoon. The developer has two more questions. The PM answers Wednesday morning. By Thursday, the developer has enough context to start. They've lost three days to asynchronous Q&A that could have been avoided with twenty minutes of upfront writing.

This is the hidden cost of thin tickets. Not the writing time — the wait time. Every missing detail becomes a blocking question. Every blocking question adds a round-trip of asynchronous communication. Every round-trip adds 4-24 hours of latency, depending on time zones and meeting schedules.

But the deeper problem isn't speed — it's accuracy. When a developer fills in gaps with assumptions, they build the wrong thing. Not because they're bad at guessing, but because product decisions disguised as implementation details look identical from the outside. "Should this export include archived orders?" is a product decision. The developer guesses no. The customer expected yes. The bug report arrives two weeks later.

We've measured this. Teams with comprehensive tickets ship features in 60% of the time compared to teams with minimal tickets. Not because they code faster — because they don't rework.

## The Principle

A ticket is a contract between the person who understands the problem and the person who will solve it. It must contain everything the implementer needs to ship without asking follow-up questions: who is affected, what the user experiences today, what they should experience after, how the architecture supports it, and how to verify it's done.

Every ticket. Every time. No exceptions for "small" changes, because small changes with missing context cause the same rework cycles as large ones.

## The Pattern

### The anatomy of a complete ticket

Every ticket follows the same structure, scaled to the complexity of the work:

#### Complexity assessment

Lead with an honest estimate. This sets expectations and determines whether the ticket needs breakdown.

```markdown
## Complexity Assessment

**Estimated Effort:** Standard (3-5 days)

**Reasoning:** New server action + repository query + UI component.
Existing export patterns in the codebase can be adapted.
No schema changes needed.
```

If the estimate exceeds five days, the ticket must be broken into smaller, independently shippable milestones before work begins.

#### User story

One sentence that captures who benefits, what they do, and why it matters:

```markdown
## User Story

As a **sales manager**, I want to **export filtered orders to CSV**
so that **I can share pipeline data with stakeholders who don't have
application access**.
```

This isn't ceremony. The user story prevents the implementer from optimizing for the wrong persona. A feature built for a sales manager looks different from the same feature built for a data analyst — different defaults, different columns, different file format assumptions.

#### Current behavior and expected behavior

Show the gap between today and tomorrow. For bugs, this is exact reproduction steps. For features, it's the workaround the user currently uses.

```markdown
## Current Behavior

Users manually copy data from the orders table into a spreadsheet.
For large datasets (>100 orders), they screenshot the table or ask
engineering for a database export.

## Expected Behavior

A "Download CSV" button in the orders table toolbar exports all orders
matching the current filters. The CSV includes: order ID, title,
customer name, status, amount, created date. Maximum 10,000 rows.
Archived orders are excluded unless the "Show archived" filter is active.
```

Notice the specifics: which columns, what limit, how archived orders are handled. These are the details that, if missing, generate follow-up questions.

#### Architecture context

Tell the implementer which files, patterns, and layers are involved. This prevents them from reinventing a pattern that already exists or modifying the wrong layer.

```markdown
## Architecture

**Repository:** `orders.repository.ts` — add `exportOrders()` function
that accepts filter criteria and returns a flat array (no pagination).

**Server Action:** `orders/actions/export-orders.ts` — validate filters
with Zod, call repository, convert to CSV string, return as download.

**UI:** Add export button to `OrderToolbar.tsx`. Use `useTransition`
for loading state during generation.

**Existing Pattern:** See `customers/actions/export-customers.ts`
for the CSV generation helper we already use.
```

This section takes three minutes to write and saves the developer from spending thirty minutes exploring the codebase to figure out where things go.

#### User journey

For features that change user-facing behavior, a step-by-step flow:

```markdown
## User Journey

1. User navigates to Orders page
2. User applies filters (date range, status, assignee)
3. User clicks "Download CSV" in the toolbar
4. Button shows loading spinner (useTransition)
5. Browser downloads `orders-export-2026-03-15.csv`
6. CSV opens in Excel/Sheets with correct column headers
```

For complex flows, a sequence diagram makes the interactions explicit — especially when multiple systems are involved.

#### Acceptance criteria

The definition of done. Each criterion is independently verifiable:

```markdown
## Acceptance Criteria

- [ ] CSV includes columns: Order ID, Title, Customer, Status, Amount, Created
- [ ] Export respects all active filters (date, status, assignee)
- [ ] Archived orders excluded unless "Show archived" filter is active
- [ ] Maximum 10,000 rows — show toast if limit exceeded
- [ ] Empty export (no matching orders) shows informational toast, no download
- [ ] Loading state shown during CSV generation
- [ ] File name includes current date: `orders-export-YYYY-MM-DD.csv`
- [ ] Amounts formatted as dollars (not cents) in the CSV
```

Each criterion answers a question the developer would otherwise have to ask. Together, they form the test plan for the PR.

#### Edge cases

The scenarios that the developer will encounter during implementation and need product guidance for:

```markdown
## Edge Cases

- **Large dataset (>10K rows):** Truncate at 10,000 with toast:
  "Export limited to 10,000 orders. Refine your filters for a smaller set."
- **No matching orders:** Toast: "No orders match your current filters."
  No file download.
- **Special characters in data:** Customer names with commas must be
  properly CSV-escaped (quoted fields).
- **Concurrent exports:** Allow multiple — each is a stateless server action.
```

### Complexity tiers and breakdown

Quick Win (0-2 days): Ship as-is. The ticket above is sufficient.

Standard (3-5 days): Ship as a single ticket with full acceptance criteria. The export example fits here.

Complex (6+ days): Must be broken down into independently shippable milestones:

```markdown
## Breakdown

1. **Milestone 1 (Enabler):** Add `exportOrders()` repository function
   with filter support [1 day]
2. **Milestone 2 (Feature):** CSV export with UI button and basic
   columns [2 days]
3. **Milestone 3 (Enhancement):** Column selection dialog and
   Excel format option [2 days]

Each milestone ships independently. Milestone 1 blocks 2 and 3.
```

Each milestone becomes its own ticket with its own acceptance criteria. The parent ticket links to all three.

### Labels and metadata

Use labels to communicate signal, not bureaucracy:

- **Type:** Bug, Feature, Improvement (pick one)
- **Area:** The primary domain (Orders, Payments, Scheduling)
- **Complexity:** Quick Win or Needs Breakdown
- **Priority:** Set by the PM, not the developer

Estimate in days, not story points. "3 days" is concrete. "5 story points" means different things to different people on the same team.

### The 20-minute rule

Writing a complete ticket takes about 20 minutes. Reading a thin ticket and filling in the gaps through async Q&A takes 2-3 days of elapsed time. The math is obvious.

If you don't have 20 minutes to write the ticket properly, you don't have enough understanding of the problem to assign it.

## The Business Case

- **Elimination of async Q&A cycles.** Every missing detail in a ticket adds a 4-24 hour round-trip of questions and answers. A complete ticket eliminates these entirely. A five-day feature ships in five days instead of eight.
- **Accurate estimation.** When tickets include architecture context and edge cases, developers can estimate accurately because they understand the full scope before they start. No more "this was supposed to be two days" surprises.
- **AI-agent compatibility.** AI coding agents can implement well-written tickets autonomously. A ticket with user stories, architecture context, and acceptance criteria gives the agent everything it needs. A six-word ticket gives it nothing.

## Try It

Install the Modh Playbook skills to enforce this pattern automatically:
```bash
# Add to your project
git submodule add https://github.com/modh-labs/playbook .agents/modh-playbook
./.agents/modh-playbook/install.sh
```
