---
name: record-the-no-op
description: >
  A deliberate no-op (a sync skipped because a setting is off, a job that found
  nothing to do, a webhook ignored on purpose) is an outcome, and it needs a
  durable record: on the entity it concerns, deduplicated per reason and time
  window, labelled for any screen that lists it, and proven writable against
  the real store. Use when code returns early with a "skipped"/"ignored"/"noop"
  reason; when an acceptance criterion says a reason is "recorded" or "visible";
  when the only trace of a skip is a log line; when a never-throwing audit or
  history write is added; or when a support question "why didn't X happen?"
  has no answer in the data.
---

# Record the No-Op

A no-op that leaves no trace is indistinguishable from a bug. A no-op that
leaves a trace every time it fires is a different bug: it floods whatever
screen shows the table. This skill is about the narrow path between the two.

## When This Skill Activates

- A function returns early with a reason: `skipped`, `ignored`, `not_applicable`, `noop`
- An acceptance criterion says the reason is "recorded", "visible" or "on the record"
- The only evidence of a skip is a `logger.info` / `debug` line
- You add a history, audit or timeline write that catches its own errors
- Support asks "why didn't this sync/send/book?" and the database cannot say

## The One Question

> **If a customer asks tomorrow why this did not happen, where do I read the
> answer, and will it still be there?**

If the answer is "in the logs", it is probably not there: info-level lines are
the first thing sampled, dropped or expired. If the answer is "in a table", ask
the four follow-ups below before you trust it.

## Decision Tree

```
Code path deliberately does nothing
│
├─ Could a person later need to know it happened, or why?
│   NO  → a log line is fine (pure internal fast path). Stop.
│   YES ↓
│
├─ 1. WHERE: on the entity the question will be asked about
│      (the call, the order, the lead), in a table that outlives logs.
│      Not a log line. Not a metric alone (metrics lose the "which one").
│
├─ 2. HOW OFTEN: does the no-op repeat for the same entity?
│      (every sync, every webhook, every cron pass, every retry)
│      YES → dedup on entity + reason (+ variant) within a time window.
│            Write the first occurrence, skip the rest.
│
├─ 3. WHO SEES IT: does any customer-facing screen list this table?
│      (audit trail, activity feed, timeline)
│      YES → give the action a plain-language label; never ship the raw key.
│
└─ 4. CAN IT WRITE: does the write swallow its own errors?
       YES → prove the store accepts every value it writes (CHECK
             constraints, enums, NOT NULL, FKs) against the REAL schema,
             not a mock. A rejected write that is caught and logged looks
             exactly like a feature that works and records nothing.
```

## Core Rules

### 1. Record it where the question will be asked

```ts
// WRONG: the only trace is a log line production drops
if (!settings.leadCapture && !contact) {
  logger.info({ callId, reason: "lead_capture_off" }, "sync skipped");
  return { synced: false, reason: "lead_capture_off" };
}

// CORRECT: a durable row on the entity, plus the return value
if (!settings.leadCapture && !contact) {
  await recordSkip({ orgId, entityType: "call", entityId: callId,
    action: "crm_sync_skipped", metadata: { push: "note", reason: "lead_capture_off" } });
  return { synced: false, reason: "lead_capture_off" };
}
```

### 2. Await it, never throw from it

The record explains the skip; it must never become the reason the job fails
and retries. Await it (a fire-and-forget write can be lost when a serverless
step or worker returns), and catch inside the helper.

```ts
export async function recordSkip(input: SkipRecord): Promise<void> {
  try {
    if (await hasRecentSkip(input, { withinHours: 24 })) return; // rule 3
    await auditLogs.insert(toRow(input));
  } catch (err) {
    logger.error({ err, entityId: input.entityId }, "skip record failed"); // never rethrow
  }
}
```

### 3. Dedup by entity + reason + window

A deliberate skip usually repeats: the same lead skips on every booking,
outcome and reconciliation pass, and one event can reach the same skip
through two code paths. Without dedup the record grows forever and buries
real activity.

```ts
// CORRECT: one row per (org, entity, action, variant, reason) per window
const exists = await db.query.auditLogs.findFirst({
  where: and(
    eq(t.organizationId, input.orgId),
    eq(t.entityType, input.entityType),
    eq(t.entityId, input.entityId),
    eq(t.action, input.action),
    sql`${t.metadata}->>'reason' = ${input.metadata.reason}`,
    sql`${t.metadata}->>'push' = ${input.metadata.push}`,
    gte(t.createdAt, since),
  ),
  columns: { id: true },
});
```

Key on every dimension that makes two skips legitimately different (a
different `push` or `reason` is a new row). A row now means "skipped at least
once in this window", not a count; say so in the runbook. A small race can
still write two rows; that is acceptable, unbounded growth is not.

### 4. Label it before a customer sees it

If an audit trail or activity feed renders the table, the raw key
(`crm_sync_skipped`) reaches a customer. Add a label in the same change:
"CRM sync skipped: lead capture is off".

### 5. Prove the write against the real schema

Because rule 2 swallows errors, a constraint violation is silent. Before
shipping, read the live constraints and check every value you write:

```sql
select conname, pg_get_constraintdef(oid)
from pg_constraint
where conrelid = 'public.audit_logs'::regclass and contype = 'c';
```

A mocked insert in a unit test cannot catch this. Neither can a staging
database whose constraints drifted from production.

### 6. Give the guard a fixture it can actually see

If the record (or anything near it) passes values through a shape check (an
id regex, a numeric-code check), test fixtures must use the real shape.
`"req_1"` where production sends `"1234-uuid"` means the guard drops the
fixture, and switching the code to the guarded value breaks a test that was
never exercising the real path.

## Anti-Patterns

| Anti-pattern | Why it fails |
|---|---|
| `logger.info` as the record | Sampled, dropped or expired; nobody can answer "why" next week |
| One row per occurrence | The skip repeats on every sync; the feed fills with noise and real changes disappear |
| Fire-and-forget write in a short-lived worker | The process returns before the write lands; the record is lost intermittently |
| Throwing from the record | A deliberate skip becomes a failed job, a retry and an alert |
| Mocked insert as the only test | Never meets a CHECK, enum or FK; the silent rejection ships |
| Raw action key in a customer UI | `crm_sync_skipped` on a settings page reads as a bug |
| Metric only | Counts that it happened, cannot say for which record |

## Audit Checklist

- [ ] Every early return with a reason a person might ask about writes a durable record
- [ ] The record lives on the entity (id + type + org), not only in logs or metrics
- [ ] The write is awaited and cannot throw out of the helper
- [ ] Repeating skips are deduplicated on entity + action + every distinguishing field, within a window
- [ ] Every customer-facing screen that lists the table has a plain-language label for the action
- [ ] Every written value checked against the live schema's constraints
- [ ] Tests: the skip writes one row; the same skip again writes none; a different reason writes a second; a failed read or write never throws
- [ ] Fixtures use the production shape for any value a guard filters
- [ ] The runbook has the read-back query and says what one row means

## Related

- `return-a-refusal`-style handling: when a job *cannot* act, return a typed result and capture once; this skill covers the durable record that result should leave.
- `dedup-key-completeness`: choosing every dimension of the dedup key.
- `prove-your-telemetry`: broken instrumentation looks like a healthy system; read a real emitted row.
- `wire-shape-fixtures`: fixtures in the shape the boundary delivers.
