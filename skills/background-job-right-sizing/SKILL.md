---
name: background-job-right-sizing
description: 'Choose the LIGHTEST durable mechanism a background/async/side-effect job actually needs, instead of reaching for a full workflow engine by reflex. A four-rung ladder — in-process fire-and-forget → durable queue → workflow engine → dedicated orchestrator — routed by four axes: durability, step count, concurrency shape, and cross-app/bus membership. Activates when adding any background job, emitting a side-effect from a request handler, choosing between Vercel Queues / Workflows / Inngest / Temporal / SQS, or auditing an existing job fleet for over-engineering ("do we still need the orchestrator for this?").'
---

# Background-Job Right-Sizing

Every async job gets shoved onto whatever durable-execution tool the team already
runs — usually a workflow engine or a dedicated orchestrator. But **most
"background jobs" are single-step fire-and-forget side-effects** (post a message,
fire a pixel, upsert a contact, send an email). Wrapping those in a full workflow
engine — with per-run event-sourcing, replay machinery, and per-event billing —
is over-engineering. The discipline is to pick the **lightest rung that provides
exactly what the job needs and nothing more.**

## When This Skill Activates

- Adding any background/async job or emitting a side-effect out of a request handler.
- Choosing between `after()`/`waitUntil()`, a durable queue (Vercel Queues, SQS),
  a workflow engine (Vercel Workflows, Temporal), or a dedicated orchestrator (Inngest).
- Auditing an existing job fleet: "which of these still need the orchestrator?"
- A platform migration question framed as all-or-nothing ("should we move off X?") —
  reframe it per-job with this ladder.

## The One Question

> **"What does this job actually NEED — durability, more than one step, per-tenant
> fairness, a cross-app bus — and what is the lightest rung that provides exactly
> that?"**

Answer the four axes, then take the lowest rung that clears all of them. Reaching
higher "to be safe" is the default failure mode, not caution.

## The Four Axes (answer these first)

1. **Durability** — if this job silently drops, is that tolerable, or does a
   reconcile cron already backstop it? (drop-tolerable → rung 1; must-not-drop → rung 2+)
2. **Step count** — one unit of work, several dependent steps, or long-lived with
   waits (sleep hours/days, wait-for-signal/human)? (single → rung 2; multi/long → rung 3)
3. **Concurrency shape** — none, **account-scope** (one global cap protecting a
   rate-limited downstream), or **per-tenant-keyed** (a fairness cap so one noisy
   tenant can't starve others)? (account-scope → rung 2 can do it; per-tenant-keyed → rung 3+/4)
4. **Cross-app / bus** — is this consumed across app or project boundaries via a
   named, typed event contract, or does it need typed pub/sub or browser realtime?
   (yes → rung 4)

## Decision Tree

```
New background job / side-effect
├─ Drop tolerable OR a reconcile cron already backstops it, AND no retries needed?
│     → RUNG 1: after() / waitUntil() (in-process, non-durable)
├─ Must not drop, single step, concurrency none or ACCOUNT-scope only?
│     → RUNG 2: durable queue (at-least-once + idempotency dedup + consumer-group concurrency)
├─ Multi-step OR long-lived (sleep / wait-for-signal / human-in-loop)?
│     → RUNG 3: workflow engine (durable steps, sleep, hooks)
└─ Needs PER-TENANT keyed concurrency (fairness) OR a named cross-app event bus
  OR typed pub/sub / browser realtime?
      → RUNG 4: dedicated orchestrator (Inngest / Temporal)
```

## The Rungs

**Rung 1 — In-process fire-and-forget** (`after()`, `waitUntil()`).
No durability, no retries. Correct only when a dropped job is acceptable, or a
cron/reconcile job independently heals the missed work. Cheapest, zero infra.

**Rung 2 — Durable queue** (Vercel Queues, SQS, etc.).
At-least-once delivery, retries/visibility-timeout, **producer idempotency
(dedup-by-id)**, and a **consumer-group max-concurrency**. That concurrency cap is
*global to the consumer* — it covers an **account-scope** cap (protect a
rate-limited API), but it is **NOT keyed by a message attribute**, so it cannot
give per-tenant fairness. This is the right-sized home for durable single-step
side-effects — the bulk of a typical fleet.

**Rung 3 — Workflow engine** (Vercel Workflows, Temporal).
Durable checkpointed steps, `sleep` for minutes→months at no compute cost, and
hooks/signals for human-in-the-loop. Reserve for genuinely multi-step or
long-lived orchestration. Costs per-event/step machinery — do not pay it for a
one-step side-effect.

**Rung 4 — Dedicated orchestrator** (Inngest, Temporal with custom primitives).
Keep here only for what the lighter rungs cannot express: **per-tenant keyed
concurrency** (`key: tenantId, limit: N` fairness caps), a **named cross-app event
bus** with a typed contract, typed pub/sub, or browser realtime channels.

## Core Rules

1. **Right-size DOWN, not up.** The reflex is to reach for the heaviest durable
   tool. Default the other way: start at the lowest rung that clears all four axes.
2. **A single-step side-effect is a queue job, not a workflow.** If it has one
   `step.run` and no sleep/branch, a workflow engine is over-engineering — a
   durable queue message is the fit.
3. **Account-scope concurrency ≠ per-tenant fairness.** A consumer-group cap
   protects a downstream globally; it does NOT stop one tenant's burst from
   starving others. Per-tenant fairness needs a *keyed* concurrency primitive
   (rung 3 lock / rung 4 orchestrator). Don't assume a queue's max-concurrency
   gives you fairness.
4. **Idempotency is non-optional above rung 1.** At-least-once means
   double-delivery happens. Dedup by a stable id at the producer (`enqueue({ id })`)
   AND make the consumer naturally idempotent (set, don't increment; upsert, don't insert).
5. **Prefer a build-time registry over a hand-synced manifest.** A mechanism where
   jobs are discovered by the compiler (directives/file conventions) removes an
   entire failure class: "new job ships but is never registered, and its events
   are silently dropped." If your orchestrator needs a manual resync step, that
   gap is a standing incident risk — automate the resync or prefer build-time discovery.

## Anti-Patterns

- **Everything-is-a-workflow.** Wrapping one HTTP POST in a durable workflow for
  the "observability and retries." A queue gives retries + observability at a
  fraction of the machinery.
- **Fire-and-forget for must-not-drop work.** `await`-less `fetch` (or `after()`)
  for a payment webhook / pixel / email with no reconcile backstop. Silent data
  loss with no trace. Use rung 2.
- **Assuming a queue gives per-tenant fairness.** Setting consumer max-concurrency
  and believing one tenant can't monopolize it. It's a global cap, not per-key.
- **All-or-nothing platform migrations.** "Should we move off the orchestrator?"
  answered as one binary. Answer it per-job with the ladder; usually a subset
  drops to rungs 1–2 while the per-tenant/bus jobs stay at rung 4.
- **Blocking the request on a side-effect** to get durability. Emit/enqueue and
  return; never `await` a non-response-critical side-effect in the handler.

## Audit Checklist

For each existing background job:

- [ ] What is its **run-time shape** — single-step, multi-step, or long-lived (sleep)?
- [ ] Does it truly need **durability**, or is it drop-tolerable / cron-reconciled?
- [ ] Concurrency: none, account-scope, or **per-tenant-keyed**? (only the last pins it to rung 3+/4)
- [ ] Does it cross an **app/project boundary** via a named event bus, or use realtime?
- [ ] Given the above, what is the **lowest rung** that clears every box — and is it currently over-provisioned?
- [ ] Is it **idempotent** (producer dedup-by-id + naturally-idempotent consumer)?
- [ ] Is it registered by a **build-time mechanism**, or is there a manual sync that can silently drop it?

Jobs that clear at rung 1–2 but sit on a rung-4 orchestrator are your consolidation
candidates. Jobs with per-tenant fairness or a cross-app bus are correctly at rung 4 —
leave them until the lighter rungs gain those primitives.
