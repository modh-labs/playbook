---
name: cost-to-serve-audit
description: >
  Cost to serve: what one customer costs in vendor fees, measured from the vendor's own meter.
  Use when pricing a plan, a reseller or partner deal, or a usage add-on; when a vendor invoice
  does not match the usage your app records; when asked for gross margin or unit economics per
  customer; when deciding whether to stay with a vendor or move; or before a deal that multiplies
  volume on usage-billed vendors.
---

# Cost to serve audit

A vendor bills by its own **meter**: connected accounts, bot minutes, tokens, GB-months,
message segments. Your app records something nearby: calendars a user connected, minutes of
recording, the estimate in a code comment, rows in a table. The two drift apart, and the invoice
follows the meter. Cost models built from app records come out low, sometimes by multiples, and
the gap hides inside setup leaks nobody owns.

## The one question

> **If I count this vendor's billing unit from my own data, does the total match the invoice?**

No, or "I don't know", means the cost model is a guess. Read the meter before pricing anything.

## Decision tree

```
For each usage-billed vendor:
│
├─ 1. What is the billing unit? Read it off the invoice or contract.
│     The pricing page is the list price. A contract or a volume tier changes the rate.
│
├─ 2. Where does the vendor record that unit?
│     ├─ Vendor events or webhooks you store (joined/left, created/deleted) → count from those
│     ├─ Vendor list API (accounts, grants, numbers, buckets)              → list it, diff with your table
│     ├─ Vendor usage report or provider-reported tokens                   → read it, not your estimate
│     └─ Nowhere you can reach                                            → mark the line "estimate"
│
├─ 3. Does your app's count match the meter?
│     ├─ Yes → use either; label the source
│     └─ No  → the gap is a LEAK. Find the code path that makes it before modelling price.
│
└─ 4. Price by the same unit the vendor bills you.
      A flat fee per customer cannot carry a per-hour or per-account cost for heavy users.
```

## Core rules

1. **Meter first.** Take the billing unit and rate from the invoice or contract. A list price is
   a placeholder and says so in the model.
2. **Count from the vendor's signal.** Billable time comes from the vendor's join and leave
   events, not from the length of the recording you kept. Billable accounts come from the
   vendor's list, not from your connections table. AI spend comes from provider-reported tokens,
   not from a comment that says "about two cents a call".
3. **Every number carries a label:** real (invoice, contract, measured), list price, or estimate.
   A reader must be able to tell which numbers would move if a bill arrived.
4. **Archetypes from medians of real usage.** Bucket paying customers by how they use the product
   (seats, connections, recorded hours, messages), take 30-day medians, and add a projected
   archetype only when a deal promises customers you do not have, labeled as projected.
5. **Break-even per pricing unit.** For each proposed price, compute the usage at which one
   customer stops paying for itself. Compare it with the typical customer's usage.
6. **Leaks before rates before vendors.** Fix setup leaks first (settings, lifecycle bugs, gates
   that skip a check). Negotiate rates second. Switch vendors last, and only when the saving is
   large, the switch is cheap, or the vendor is failing you.
7. **Prove a zero before trusting it.** A usage metric that reads zero or null may be the wrong
   query shape (a distribution queried as a counter, the wrong unit). Pull a sample row first.

## Where meters drift (the usual leaks)

| Meter | App record that undercounts it | Typical cause |
|---|---|---|
| Meeting bot minutes | Recording length | Bots wait in lobbies, join no-shows, stay after everyone leaves |
| Connected accounts or grants | Rows in your connections table | Reconnect replaces a row without revoking the old account; user deletion drops the row only |
| LLM tokens | A per-call estimate in code | Prompts grew, retries stack in two layers, reviews run on calls with nothing to review |
| Object storage GB-months | Rows that point at files | Deleting a record leaves the file; no retention rule; every view downloads from a metered bucket |
| Message segments | Messages sent | Long messages split into several segments; carrier fees on top of the base rate |

## Procedure

1. **List usage-billed vendors** from the subprocessor list, dependencies and env vars.
   Done when each has a billing unit, a rate with its source, and a place the meter is visible.
2. **Measure 30 days of real usage per customer** for each meter, from the vendor's signal.
   Done when every meter has a total and a per-customer breakdown, or is marked estimate.
3. **Reconcile against the invoice.** Done when each vendor's measured total is within a few
   percent of the billed quantity, or the gap has a named cause.
4. **Build archetypes** (rule 4) and the cost per archetype per month.
   Done when each archetype row shows usage, cost, retail revenue and margin.
5. **Test each proposed price** (rule 5). Done when every tier shows break-even usage and the
   archetypes that lose money at it.
6. **Score the setup leaks** found in step 3: cost per month today, cost at the target volume,
   effort to fix. Done when each leak has an owner or a ticket.
7. **Stay or leave per vendor** (rule 6): current cost, levers not pulled, alternatives with
   their price source, switching effort. Done when each vendor has a call.

## Anti-patterns

| Shortcut | Consequence | Do this |
|---|---|---|
| Model cost per seat when the vendor bills per connection | Teams with many connections look cheap | Count the vendor's unit per customer |
| Price from the pricing page while on a contract | Margin wrong in both directions | Read the invoice or contract rate |
| Use averages for archetypes | One heavy customer sets the typical cost | Use medians and show the heavy customer as its own archetype |
| Trust a cost comment in code | Underestimates hide for months | Read provider-reported usage |
| Fix a cost leak by deleting customer resources | Breaks customers who come back; a product decision made by accident | Fix the code path that leaks; take deletions of customer data to the owner |
| Switch vendors to save a few percent | Months of work, new failure modes | Pull the vendor's own levers first |

## Audit checklist

- [ ] Every usage-billed vendor has a billing unit, a rate and the rate's source.
- [ ] Every meter is counted from the vendor's signal, or labeled estimate.
- [ ] Measured totals reconcile with the latest invoice, or each gap has a named cause.
- [ ] Archetypes use medians of real usage; projected ones are labeled.
- [ ] Every proposed price has a break-even usage per unit.
- [ ] The price unit matches the cost unit for every vendor that dominates cost.
- [ ] Every leak has a monthly cost, a cost at target volume and an owner.
- [ ] Every vendor has a stay or leave call with the reason.
- [ ] Confidential contract rates stay out of anything shared outside the company.
