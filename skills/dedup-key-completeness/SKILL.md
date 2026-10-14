---
name: dedup-key-completeness
description: 'A de-duplication, idempotency, or uniqueness guard must key on every dimension that makes two records legitimately distinct. A missing dimension silently collapses separate records into one (a lost write with no error). Use when writing an upsert, an onConflict target, a unique constraint, a "have we seen this already?" time window, or any "skip if it exists" guard — and when a bug report says "my second booking/order/ticket disappeared or merged into the first."

'
---

# Dedup Key Completeness

## When This Skill Activates
- Writing an upsert / `onConflict` target, a unique constraint, or a "uniqueness" index.
- Building a "have we already processed this?" guard — a time window, a "skip if exists" check, an in-flight claim.
- A bug report: "I created a second {booking, order, ticket, subscription} and it never appeared / it reverted to the first one."
- Reviewing idempotency on a webhook, a booking flow, an import, or any create path that can fire twice.

## The One Question
> "If two records that SHOULD coexist both matched this key, what dimension is missing from it?"

If you can name such a pair, the key is too broad — it will silently merge them.

## Decision Tree
```
Defining a dedup / idempotency / uniqueness key?
  │
  ├─ Enumerate what makes two rows the SAME action (a true duplicate / a retry).
  ├─ Enumerate what makes two rows DIFFERENT but look alike
  │     (same actor, same minute, same email…).
  │
  └─ key = exactly the "same-action" dimensions — nothing more, nothing less.
        Missing a "same-action" dimension   → real duplicates leak    (TOO NARROW)
        Including a "different" dimension    → distinct rows collapse  (TOO BROAD)
```

## Core Rules

### 1. The key must contain every dimension of record identity
Two records are the same iff they share ALL the dimensions that define them. A
guard scoped to `(actor, time-window)` but not the *resource / route / parent /
variant* will merge two legitimately-different records made by the same actor at
the same time.

```ts
// ❌ WRONG — collapses two distinct records the same actor made in the window
const existing = await db.select().from(records).where(and(
  eq(records.actorId, actorId),
  gte(records.createdAt, windowStart),
  lte(records.createdAt, windowEnd),
)).limit(1);
if (existing) return existing; // a second record via a DIFFERENT parent is lost

// ✅ RIGHT — also scope to the parent/variant that makes them distinct
const conditions = [
  eq(records.actorId, actorId),
  gte(records.createdAt, windowStart),
  lte(records.createdAt, windowEnd),
];
if (parentId) conditions.push(eq(records.parentId, parentId));
const existing = await db.select().from(records).where(and(...conditions)).limit(1);
```

### 2. Separate true-retry idempotency from heuristic windows
A delivery retry or double-submit produces the SAME upstream id. Dedup THAT with
a globally-unique token (provider event id, request id, idempotency key) backed
by a unique constraint or `onConflict`. The fuzzy "±N seconds" window is only a
*secondary* guard for near-duplicates that lack a shared id — never let it stand
in for real idempotency.

### 3. Handle null key dimensions explicitly
In SQL, `col = NULL` is never true. If a key dimension can be null (an external
record with no parent), `eq(col, null)` silently matches nothing. Decide whether
null means "no scope — fall back to the broader guard" or "its own bucket," and
write it deliberately rather than discovering it in production.

## Anti-Patterns
- **The "0.1% edge case" dismissal.** "Two records, same slot, same person, different parent" sounds rare — but it's a *silent lost write*: no error, no log, the user just loses data and the support thread is unfalsifiable. Severity is about the failure mode, not the frequency.
- **One key doing two jobs.** Using the fuzzy time window AS the idempotency key. Retries need an exact shared id; near-dupes need a heuristic. Conflating them makes both wrong.
- **Widening blindly.** Adding columns to the key until the symptom stops, without naming which pair of records must stay distinct. Name the pair first; the missing dimension falls out.

## Audit Checklist
- [ ] Every dimension of record identity is in the key (parent / resource / variant id included).
- [ ] True-retry dedup uses a globally-unique token, separate from any heuristic window.
- [ ] Null-valued key dimensions are handled deliberately (`col = NULL` never matches).
- [ ] A test asserts two legitimately-distinct records do NOT collapse, and a true duplicate DOES.
- [ ] The DB unique constraint / index columns match the application-layer dedup key (no drift between them).
