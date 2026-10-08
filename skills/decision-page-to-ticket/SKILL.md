---
name: decision-page-to-ticket
description: >
  Turn a scoping question into one shared decision page, then a ticket an engineer can build
  from without asking. Use when a customer report or team thread turns out to need product
  decisions before work starts, when engineers and non-engineers must agree on the same
  choices, when options are easier to judge as mockups than as prose, or when a grilling
  session should end in a buildable ticket.
---

# Decision Page to Ticket

A decision made in a chat thread is gone within a week. A ticket written before the decisions
exist either guesses or stalls. Two artifacts, in order, fix both:

1. **A decision page** where everyone who must agree can see the same choices, in their own
   level of detail, with the options drawn.
2. **A ticket** that copies what was agreed and adds everything the builder needs, so nobody
   has to reopen the page to know the scope.

The page is where people agree. The ticket is where the work lives. Each links to the other.

## When This Skill Activates

- A customer report looks like a bug but turns out to need a product choice.
- The people who must agree include non-engineers (sales, support, a founder) as well as the
  people who build it.
- Two or more options are reasonable, and the difference only shows in the result: a screen, a
  record, what happens a month later.
- A grilling session is ending and its answers need to become work.

The diagnostic question: **can the engineer build this from the ticket alone, and can the
people who asked for it see on one page what they agreed to?** If either answer is no, apply
this pattern.

## Decision Tree

```
Is there a choice a human must make before building?
├─ No  → write the ticket directly
└─ Yes → Must anyone who doesn't read code agree to it?
    ├─ No  → grill in chat, record the decisions in the ticket
    └─ Yes → decision page:
        1. Ask round 1 now; send a read-only agent for code facts in parallel
        2. Publish the page with round 1 drawn as options
        3. Facts land → correct the page, add round 2
        4. The owner settles → mark each decision settled, with the date
        5. Write the ticket from the page; link page, ticket and blockers both ways
```

## Core Rules

### 1. Facts are the agent's job, decisions are the human's

Before asking anything, sort it. A fact can be looked up: what the code does, which table holds
what, whether a setting overrides another. A decision changes what gets built. Send a read-only
agent for every fact a question depends on, and ask the human only the questions whose
prerequisites are settled. Ask the fact-free ones at once rather than waiting for the agent.

WRONG: "Does the per-account setting override the global one?" asked to the product owner.
RIGHT: the agent reads the code, and the page states the fact with the file and line it came from.

### 2. One page, two audiences, one switch

The page opens in plain language. An **Everyone / Engineering** switch at the top reveals file
names, data shapes and plug-in points on the same diagrams and cards. Two separate documents
drift apart within a day; one page with two levels of detail cannot.

### 3. Draw the flow for each state

Show one flow per state: today, after step 1, after step 2. Each step names who acts, what
happens in plain words, and one status pill ("Saved", "Not sent", "Can't tell"). The engineering
caption sits under the step and only shows in Engineering view.

### 4. Put competing systems side by side first

When two records or systems hold overlapping truths, show them in one comparison table before
any option. Rows are the questions people care about (when it shows, who reads it, what happens
on opt-out, where it is sent). This table is usually the fact that changes the decision.

### 5. Draw every option

Each decision gets a card: the question, the options side by side, a small mockup of what each
option looks like to the person it affects, the recommended option outlined, and one "why" line.
For anything about what happens later, use a timeline with dates instead of a paragraph.

WRONG: "Option B could cause stale data if the setting changes."
RIGHT: Sep 1 the person agrees, Oct 1 an admin changes the setting, Oct 8 the record shows
something they never agreed to.

### 6. Settle on the page, keep the losing options

When the owner decides, mark the header "Decided <date>", say which options won, and note any
change from the recommendation. Keep the options that lost. They are the reasoning, and the next
person to question the choice will need them.

### 7. The ticket copies, it does not only link

A page can change after the fact. The ticket carries its own copy of:

- the decision table, one row per decision
- an evidence ledger: each fact with its file and line
- acceptance criteria with stable IDs, each paired with a test that fails on main today
- the exact customer-facing copy, every string
- non-goals, and any decision still open with its owner and the date it is needed
- a ready-to-paste loop prompt (see the `gauntlet-loop` skill) that stops for approval after a
  read-only step 0

The first lines of the ticket tell the assignee to read the page, and which view to use.

### 8. Ship what the customer is waiting for first

If a narrow fix answers the person who asked, it ships first and blocks the general one. The
general ticket builds on it and replaces nothing. Link the two both ways.

### 9. Show only what the audience may see

Anonymize customer data in mockups and mark examples as examples. Keep internal-only detail
behind the Engineering switch, or off the page when the page will be shared outside the team.

## Implementation Pattern

### Question format, in chat

```
Q4 - <short title>: <the question, with the options>
→ <recommended answer, and the one reason>
```

Number questions across rounds (round 2 starts at the next number), so "Q7" means one thing in
the chat, on the page and in the ticket.

### Page outline

```
Header     decision state: "Proposal for decision" → "Decided <date> · tracked in <KEY>"
Summary    the problem with one real number, step 1, step 2, the rule that stays fixed
Flows      comparison table of competing systems, then today / after 1 / after 2
Screens    one mock per audience: the end user, the internal team, the downstream tool
Round 1    decision cards (options, mock or timeline, recommended, why, engineering note)
Round 2    added when the facts land
Appendix   Engineering view only: data shapes, plug-in table, traps found in the code
```

### Ticket outline

```
TL;DR (with "<assignee>, start here: read the page, Engineering view")
Problem · Who is affected · Customer context (verbatim quotes)
Value and priority
Decisions table · Acceptance criteria (IDs) · Non-goals · Decisions still open
Experience and copy (exact strings)
Engineering: evidence ledger · approach in order · test plan per criterion
Support note · Sales claim and when it may be made · Risks and rollout
Loop prompt · Status and links (page, blockers, related)
```

## Anti-Patterns

- Decisions made in thread replies and a ticket written later from memory.
- A "business doc" and a "tech doc" for the same choice.
- Asking the human something the code can answer.
- Options described in prose when a mockup would show the difference in a glance.
- A recommendation without a reason, or every option marked "it depends".
- A ticket whose scope is only "see the page", so an edit to the page changes the scope.
- Rewriting a settled page with no dated note.
- Real customer names or data in a mockup.

## Audit Checklist

- [ ] Every question put to the human was a decision; every fact was looked up
- [ ] Every fact on the page cites where it was read
- [ ] The plain view reads with no code knowledge; the Engineering view adds detail and never contradicts it
- [ ] Each decision has options, a mockup or timeline, a recommendation and a reason
- [ ] The page shows the settled state, the date and the ticket key
- [ ] The ticket carries the decision table, the evidence ledger and the exact copy
- [ ] Every acceptance criterion has an ID and a test that fails on main today
- [ ] Blocking and related tickets are linked both ways
- [ ] The loop prompt stops for approval after a read-only step 0
