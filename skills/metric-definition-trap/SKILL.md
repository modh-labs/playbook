---
name: metric-definition-trap
description: >
  Before any metric reaches a report, dashboard, exec deck, or stakeholder, name its
  population and definition, then adversarially re-query the number against live data.
  Use when reporting revenue/MRR/conversions/churn/ROAS/signups, building a KPI surface,
  auditing analytics, or repeating a "we can source this metric" claim. Catches two
  traps: one label hiding two incompatible populations (e.g. our SaaS revenue vs our
  customers' deal revenue), and an un-verified number that is silently 8x off because
  it includes gating/skipped rows or used the wrong constant.
---

# The Metric Definition Trap

## When This Skill Activates

- Putting a number on a report, dashboard, exec deck, board update, or investor email
- Building or reviewing a KPI / analytics surface (weekly metrics, growth dashboard)
- Reporting revenue, MRR/ARR, conversions, churn, ROAS/CAC, signups, activation
- Auditing what metrics a system can produce, or repeating a "we can source X" claim
- Anytime two different teams use the same word ("revenue", "active", "signups") and
  you are about to add up or compare their numbers

This is the **number-integrity** companion to `project-charter`. The charter's "Metric
Readiness" gate asks *can we query a baseline at all*. This skill asks the next two
questions: *what exactly does this number count* and *is the number we're about to
report actually true*. (For the narrower case of re-verifying codebase-audit counts —
grep totals inflated by test/markdown/comment matches — that specialization lives
separately; this skill is about reported business metrics.)

## The Two Questions

> **1. What population and definition does this number count?**
> **2. Have I re-queried it against live data, trying to prove it wrong?**

A metric with no named population is a rumor. A metric you have not tried to falsify is a
guess. Neither belongs in a report.

## Decision Tree

```
About to report a number?
  Does the label uniquely name ONE population + ONE definition?
    NO  -> rename it. "Revenue" -> "our SaaS subscription revenue" vs
           "GMV processed for our customers". Never one label, two worlds.
    YES -> continue.

  Is the number a raw aggregate / GROUP BY / dashboard tile / someone's claim?
    YES -> re-query the SOURCE yourself. Strip gating rows (skipped / draft /
           test / soft-deleted). Confirm the denominator. Check every constant
           (price, rate, FX) against the real value. Compare to your expectation —
           if it's off by >2x, assume YOU are wrong until you've explained the gap.
    NO (you derived it from live rows just now) -> still sanity-check the magnitude.

  Could this number be read as a DIFFERENT, bigger/scarier metric by the audience?
    YES -> annotate the population inline so it cannot be re-interpreted as
           something it is not (e.g. customers' GMV read as our revenue).
```

## Core Rules

### 1. One label, one population — never two worlds under one word

A single label routinely hides two incompatible populations. The dangerous case is when
the wrong one is bigger and flatters you. (Illustrative:)

- WRONG: an exec "Revenue" line shows **$3.9M**, sourced from the deal-revenue table —
  which is *the volume our customers processed through us* (GMV over a handful of
  connected accounts), not money we earned. Our actual product revenue is the active
  subscriptions. The deck now claims ~$3.9M of revenue we do not have.
- RIGHT: two separate, named lines. **"Our SaaS revenue"** = subscription count / MRR.
  **"GMV processed for customers"** = the deal-revenue table, explicitly labelled as
  customer volume, never summed into our P&L.

The same trap appears with "active" (logged-in vs paying vs not-churned), "signups"
(users vs orgs vs leads), and "bookings" (created-at vs scheduled-at). **Every reported
metric names its population and its date/definition axis. If two teams say the same word
and mean different rows, they are two metrics, not one.**

### 2. Verify before claim — re-query live, trying to falsify

A "we can source this metric" claim and a tile's headline number are hypotheses, not
facts. Before reporting, pull the source yourself and adversarially check it.

- WRONG: report the conversion-events headline of **1,812** straight off a `GROUP BY
  status` total. **88%** of those rows are intentional `skipped` (the event was gated,
  not sent). The honest number is **220 sent / 0 failed** — the raw count overstated
  reality ~8x.
- RIGHT: filter to the rows that mean what the label says (`status IN ('success',
  'failed')`), report 220/0, and note the skipped rows separately if they matter.

The pattern is universal: gross aggregates fold in **gating / skipped / draft / test /
soft-deleted** rows. Always ask "what rows does this total include that the label does
not?" and re-query with the right filter.

### 3. Check every constant against the real value

A formula is only as honest as its inputs. The classic miss: an MRR estimate built on a
**$49** seat price when the real plan is **$97/mo** — a ~2x error baked into a "computed"
number that looked authoritative.

- Verify the price/rate/FX/headcount constant against the live source, not memory or a
  stale comment. One wrong constant silently scales the whole metric.

### 4. Denominator and date-axis integrity

- A rate needs its denominator named and queried from the same population as the
  numerator (a churn count over a different base than the active count is meaningless).
- Pick ONE date axis and say which: created-at (when it was made) vs occurred-at (when
  it happened). Mixing them double-shifts a funnel.
- If two divergent implementations of the same rate exist (one in SQL, one in app code),
  lock ONE definition before reporting either.

### 5. Report blocked metrics honestly

If the number cannot be sourced truthfully, say "not available" and name the unblock —
do not substitute a guess or a proxy that reads like the real thing. A labelled gap is
trustworthy; a confident wrong number poisons every other number on the page.

## Anti-Patterns

- **The flattering bigger number.** Reaching for the table that produces the largest
  figure without checking whether it counts *your* money or *someone else's volume*.
- **Tile-trust.** Quoting a dashboard's headline as fact without re-querying the source;
  the tile may already bake in gating rows or a stale constant.
- **Gross-as-net.** Reporting a `GROUP BY total` or a raw count as "sent / done / won"
  when most rows are skipped/draft/test.
- **Constant from memory.** Plugging a remembered price/rate into a formula instead of
  reading the live value.
- **Word-collision sum.** Adding or comparing two teams' "revenue" / "active" / "signups"
  without confirming they count the same population.
- **Silent proxy.** Substituting a guessable proxy ($49 × seats) for an unavailable true
  metric ($MRR) without labelling it an estimate.

## Audit Checklist

Before any number ships in a report, dashboard, or stakeholder message:

- [ ] Every metric label names its **population** and its **definition / date axis**
- [ ] No single label maps to two incompatible populations (our-money vs customer-volume,
      users vs orgs, created-at vs occurred-at)
- [ ] The headline number was **re-queried from the source**, not copied from a tile/claim
- [ ] Gating rows (skipped/draft/test/soft-deleted) are excluded or reported separately
- [ ] Every constant (price, rate, FX, headcount) checked against the live value
- [ ] Each rate's denominator is named and drawn from the same population as the numerator
- [ ] Any metric off by >2x from expectation was reconciled before reporting
- [ ] Metrics that cannot be sourced truthfully are reported as "not available" + unblock,
      never as a guess dressed as a fact
