---
name: webhook-temporal-guard
description: 'Validate temporal relevance of webhook payloads at the handler boundary — webhooks arrive carrying a moment that has already passed, and acting on past-time payloads writes wrong-but-silent state into your DB and downstream systems. Use when handling any webhook whose payload contains a time the action depends on (start_time, expires_at, scheduled_at, deadline).

'
---

# Webhook Temporal Guard

## When This Skill Activates

- You're building a webhook handler whose payload carries a time the action depends on (`start_time`, `scheduled_at`, `expires_at`, `valid_until`, `due_date`, `deadline`)
- A webhook handler mutates DB state or fires side effects (emails, downstream webhooks, Zapier, CRM sync) based on a payload time
- You're auditing why customers received "your meeting was rescheduled" emails for meetings that already happened
- You're triaging a Sentry alert that fires for unfixable input — the error message is yours, not the upstream provider's
- You're integrating Nylas/Google Calendar/Microsoft Graph (calendar webhooks fire for past events constantly)
- You're integrating Stripe (refund/dispute webhooks for already-settled charges)
- You're integrating Twilio/SendGrid (delivery webhooks for messages already retried at higher level)

## The Diagnostic Question

> "If this webhook was delivered late, would acting on it produce wrong-but-silent state?"

If yes → the temporal guard applies. Read on.

## Critical Rule

**A webhook announces a moment that has already passed. Before mutating state on a payload time, validate that time against `now()` at the handler boundary.** If the payload time has moved into the past, the webhook is reporting an edit to history — don't propagate it as a current-state action.

## The Problem

Webhook delivery is asynchronous. Between the moment a state change occurs in the upstream system and the moment your handler processes it, anything from milliseconds to minutes (sometimes hours, on retry) can pass. During that gap:

- The payload's `start_time` can move from "near future" to "past"
- The entity's underlying state can change (cancelled → reinstated, paid → refunded, expired → renewed)
- A subsequent webhook for the same entity can already have processed
- The user can have edited a calendar event AFTER its scheduled time, and the upstream provider dutifully fires `event.updated` with the unchanged (now-past) `start_time`

When the payload contains a time your action depends on, this gap matters most:

```
Time T+0      ─ User schedules meeting for 19:00
Time T+0      ─ Calendar provider stores event with start_time = 19:00
...
Time T+19:00  ─ Meeting was supposed to start. User no-shows.
Time T+19:14  ─ User edits the event in calendar (extends end_time, adds notes)
Time T+19:14  ─ Provider dispatches event.updated webhook
Time T+19:15  ─ Webhook handler receives payload: start_time = 19:00
Time T+19:15  ─ Handler treats this as a "reschedule" — start_time differs
                from cached scheduled_at (which had drifted), updates DB,
                sends "Your meeting was rescheduled to 19:00" email to
                attendees. Meeting was 15 minutes ago.
```

The customer receives a reschedule notification for a meeting that already happened. Your CRM gets a `call.rescheduled` event for a no-show. Your DB now contains a past `scheduled_at`. Your Sentry fires a `booking.critical` alert because somewhere deep in the stack, a notetaker future-time guard catches the past time and throws — but by then, every other side effect has already fired.

## Decision Tree

```
Does the webhook payload contain a time my action depends on?
│
├─ YES → Could the payload time be in the past at delivery?
│   │
│   ├─ YES → You need a temporal guard at the handler boundary.
│   │        Skip to "Implementation Pattern" below.
│   │
│   └─ NO  (provider only fires for future events) → Verify upstream
│            documentation. Most providers fire for past events too —
│            event modifications, replays, retries.
│
└─ NO → The temporal guard doesn't apply. Idempotency, signature
         verification, and other guards still do.

Does my handler fire side effects (emails, downstream webhooks, CRM)?
│
├─ YES → Place the guard BEFORE side-effect dispatch. The DB write,
│        emails, and downstream webhooks must all gate on the same
│        check.
│
└─ NO  → Place the guard before the DB write. The cost of a past
          timestamp in your DB is corrupted analytics + downstream
          confusion later.
```

## Implementation Pattern

### Layer 1: Guard at the handler boundary

The cheapest place to short-circuit. Before entering the action branch:

```typescript
// In webhook handler — BEFORE acting on the time-dependent payload
if (when?.start_time && call.scheduledAt) {
  const newScheduledAtMs = when.start_time * 1000;
  const oldScheduledAtMs = new Date(call.scheduledAt).getTime();
  const timeDiffMs = Math.abs(newScheduledAtMs - oldScheduledAtMs);
  const isReschedule = timeDiffMs > 60000; // > 1 minute

  // Past-time guard: skip when the new start_time has already passed
  const isPastStartTime = newScheduledAtMs <= Date.now();

  if (isReschedule && !isPastStartTime) {
    // Legitimate future-time reschedule — proceed
    await rescheduleCall(call.id, new Date(newScheduledAtMs));
  } else if (isReschedule && isPastStartTime) {
    log.info(
      {
        old_scheduled_at: call.scheduledAt,
        new_scheduled_at: new Date(newScheduledAtMs).toISOString(),
        minutes_in_past: Math.round((Date.now() - newScheduledAtMs) / 60000),
      },
      "🛑 Reschedule skipped — new start_time is in the past",
    );
  }
}
```

### Layer 2: Defense-in-depth at the service layer

The same check, repeated at the next layer down. Protects callers who didn't (or forgot to) guard at the boundary. UI flows, server actions, and other webhooks all benefit:

```typescript
// In rescheduleCall service (called by UI + booking.rescheduled + event.updated)
export async function rescheduleCall(callId: string, newScheduledAt: Date) {
  const call = await getCallById(callId);

  // Past-time guard at service layer (defense in depth)
  const nowMs = Date.now();
  if (newScheduledAt.getTime() <= nowMs) {
    const minutesInPast = Math.round((nowMs - newScheduledAt.getTime()) / 60000);

    logger.warn("[SERVICE] Reschedule blocked — new time is in the past", {
      call_id: callId,
      new_scheduled_at: newScheduledAt.toISOString(),
      minutes_in_past: minutesInPast,
    });

    // Capture as warning (NOT critical) — input is unfixable
    Sentry.captureMessage("Reschedule blocked: new time is in the past", {
      level: "warning",
      tags: { "reschedule.blocked_reason": "past_time" },
      extra: {
        call_id: callId,
        old_scheduled_at: call.scheduledAt,
        new_scheduled_at: newScheduledAt.toISOString(),
        minutes_in_past: minutesInPast,
      },
    });

    return { sideEffectsTriggered: false };
  }

  // ... proceed with normal reschedule ...
}
```

### Layer 3: Severity calibration

The Sentry capture above is `level: "warning"`, NOT `level: "error"` or `tags: { critical: true }`. This is intentional:

- The input is **unfixable** — the upstream system already delivered a stale payload
- Critical-tagged alerts page on-call. Past-time webhook deliveries are not on-call situations
- Warning-level captures are still queryable in Sentry (`reschedule.blocked_reason:past_time`) for triage
- Rich `extra` data (entity IDs, both timestamps, minutes in past) gives the next investigator everything they need

## Anti-Patterns

### ❌ Trusting the payload time

```typescript
// BAD: writes a past timestamp into the DB
await rescheduleCall(callId, new Date(payload.when.start_time * 1000));
```

### ❌ Fire-and-forget side effects without guarding

```typescript
// BAD: emails fire even if reschedule is to a past time
async function rescheduleCall(callId, newTime) {
  await db.update(calls).set({ scheduledAt: newTime });
  await sendRescheduleEmails(callId);
  await emitZapierEvent("call.rescheduled", { callId });
  // No past-time check anywhere
}
```

### ❌ Critical-tagged Sentry capture for unfixable input

```typescript
// BAD: pages on-call for an unfixable upstream condition
Sentry.captureException(
  new Error("Reschedule failed: new time in the past"),
  { tags: { critical: true } },
);
```

### ❌ Throwing instead of returning

```typescript
// BAD: throws unwind the call stack, may bubble past idempotency guards,
// and the outer webhook framework may retry — re-amplifying the problem
if (newTime <= Date.now()) {
  throw new Error("Past time");
}
```

### ❌ Silent skip with no observability

```typescript
// BAD: future-you has no idea this is happening
if (newTime <= Date.now()) {
  return; // good intent, no breadcrumb
}
```

## Audit Checklist

Run this against any webhook handler that mutates state based on a payload time:

- [ ] Handler validates payload time against `now()` BEFORE mutating state
- [ ] Side effects (emails, downstream webhooks, CRM) are gated by the same check
- [ ] Service-layer functions called from the handler have their own past-time guard (defense in depth)
- [ ] Past-time captures are `level: "warning"`, not `error`/`critical`
- [ ] Sentry captures include rich `extra` data: both old and new timestamps, minutes-in-past, entity IDs
- [ ] Skip path returns `{ sideEffectsTriggered: false }` (or equivalent) so callers can branch on it
- [ ] Tests cover: past time blocks (verify no DB write, no side effects), exactly-now blocks, future time proceeds
- [ ] Tests use future-relative dates (`Date.now() + offset`) or `vi.setSystemTime()` so they don't drift into the past

## Origin Story

WorldBranding (Aura customer) hit this on 2026-05-08. Their closer Ricky edited a Google Calendar event 17 minutes after its scheduled start time — likely extending the meeting end_time to capture overrun. Nylas dispatched `event.updated` with the unchanged `start_time` (now 17 minutes in the past).

Aura's reschedule pipeline:
1. Detected a time delta > 1 minute → entered the reschedule branch
2. Wrote the past timestamp into `calls.scheduled_at`
3. Dispatched reschedule emails to attendees about a meeting that had already happened
4. Fired Zapier `call.rescheduled` event into the customer's CRM
5. Tripped Aura's own future-time guard inside `update-join-time.ts`
6. Captured a `booking.critical:true` Sentry alert pointing at an unfixable upstream condition

The error message ("New join time must be in the future") was Aura's own, not Nylas's. Nylas was never even called.

The fix added a past-time guard at the entry point AND at the service layer, downgraded the Sentry capture from `booking.critical` to `level: warning` with rich extras, and added 6 unit tests covering the guard's behavior. Sentry alert frequency dropped to zero.

## Related

- **`webhook-architecture`** — handler registry, idempotency, signature verification
- **`webhook-observability`** — structured logging, Sentry integration, duration tracking
- **`auth-webhook-race`** — different webhook timing problem (FK race on first signup)
- **`write-criticality`** — severity classification for DB writes (informs the warning-vs-critical decision)
