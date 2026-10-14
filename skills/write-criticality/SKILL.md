---
name: write-criticality
description: >
  Classify database writes by durability requirement (tracking vs critical) to eliminate
  false-positive data-loss alarms. Use when adding error handling for DB writes, Sentry
  alerting for failed operations, or designing retry logic. Prevents noisy alerts from
  fire-and-forget writes while ensuring real data loss is caught and retried.
---

# Write Criticality

## When This Skill Activates

- Adding error handling around database writes
- Deciding whether a failed write should trigger a Sentry alarm
- Adding retry logic to write operations
- Reviewing code that captures "data lost" exceptions
- Auditing alerting noise from transient infrastructure errors

---

## The Core Principle

**Alarm severity must match durability requirement, not payload content.**

A write that carries user data is NOT necessarily critical — it depends on whether another write path captures the same data downstream.

```
WRONG:  if (payload has data && write failed) → alarm "DATA LOST"
RIGHT:  if (write is last chance to save data && write failed) → alarm "DATA LOST"
```

---

## Decision Tree — "Is This Write Critical?"

```
Write failed. Should I alarm?

1. Is there a downstream write that captures the same data?
   YES → This is a TRACKING write. Log warning + breadcrumb. No alarm.
   NO  → Go to 2.

2. Can the user retry the operation (form still open, request can be resent)?
   YES → This is a RETRIABLE write. Return error to user. No alarm.
   NO  → Go to 3.

3. Will the upstream system retry (webhook provider, queue, cron)?
   YES → This is an IDEMPOTENT write. Log warning. No alarm.
   NO  → This is a CRITICAL write. Retry once + alarm on final failure.
```

---

## The Three Tiers

### Tier 1: Tracking Writes (default)

**Definition:** Analytics, funnel tracking, stage progression — data that is also captured by a downstream critical write.

**On failure:**
- `logger.warn()` with structured context
- Sentry breadcrumb (visible if a later error occurs in the same request)
- Metric counter with `write_criticality: "tracking"` tag

**Do NOT:**
- Fire `captureException()`
- Log at error level
- Trigger PagerDuty or alert channels

**Example:** Updating an intent call's stage as the user fills a form — `save-form-data` captures the complete data later.

### Tier 2: Retriable Writes

**Definition:** User-facing operations where the client can retry — form submissions, API calls, checkout flows.

**On failure:**
- Return `{ success: false, error: "..." }` to the caller
- `logger.error()` for server-side visibility
- Sentry breadcrumb (not exception — the user will retry)

**Example:** Lead creation from a public form — the user's browser still has the form state and can resubmit.

### Tier 3: Critical Writes

**Definition:** The last chance to persist data. No downstream write, no user retry, no webhook re-delivery.

**On failure:**
- Retry once with 1s backoff (transient errors only)
- If still fails: `captureException()` with `write_criticality: "critical"` tag
- `logger.error()` with full context
- Metric counter for dashboards

**Example:** Final form data persistence to the database after the user has moved past the form step.

---

## Implementation Pattern

### Add a `critical` flag to write functions

```typescript
interface WriteParams {
  // ... existing params ...
  /**
   * When true, failures fire Sentry alarms ("DATA LOST").
   * When false (default), failures log warnings only —
   * data is expected to be captured by a downstream critical write.
   */
  critical?: boolean;
}
```

### Error handling branching

```typescript
if (error) {
  const isCritical = params.critical === true;

  if (isCritical && hasData) {
    logger.error({ error, ...context }, "Write failed — DATA LOST");
    captureException(new Error(`${operation} failed: ${error.message}`), {
      tags: { write_criticality: "critical" },
    });
  } else {
    logger.warn({ error, ...context }, "Write failed (tracking, non-critical)");
    addBreadcrumb({
      category: module,
      message: `${operation} tracking write failed: ${error.message}`,
      level: "warning",
    });
  }
}
```

### Transient error detection

```typescript
function isTransientFetchError(error: unknown): boolean {
  if (error && typeof error === "object" && "message" in error) {
    const msg = String((error as { message: string }).message);
    return msg.includes("fetch failed") || msg.includes("ECONNRESET");
  }
  return false;
}
```

Common transient error signatures:
| Error | Cause |
|-------|-------|
| `TypeError: fetch failed` + `UND_ERR_SOCKET` | TCP connection closed by server (keep-alive timeout) |
| `TypeError: fetch failed` + `UND_ERR_CONNECT_TIMEOUT` | DNS or connection timeout |
| `ECONNRESET` | Network reset mid-request |
| `certificate has expired` | TLS cert issue on upstream |

### Retry wrapper for critical writes

```typescript
async function withTransientRetry<
  T extends { error: { message: string } | null }
>(operation: () => PromiseLike<T>, label: string): Promise<T> {
  const result = await operation();
  if (result.error && isTransientFetchError(result.error)) {
    logger.warn({ error: result.error, label },
      `Transient error on ${label} — retrying once after 1s`);
    await new Promise((resolve) => setTimeout(resolve, 1000));
    return operation();
  }
  return result;
}
```

**Rules for retry:**
- Only retry transport-level errors (fetch failed, socket closed)
- Never retry application errors (constraint violation, RLS denial, validation)
- Maximum 1 retry with 1s backoff (not exponential — this is a single-shot recovery)
- The retry must be idempotent (same data, same where clause)

---

## Sentry Queryability

Tag all write failure metrics with `write_criticality`:

```typescript
metrics.count("write.failed", 1, {
  attributes: {
    write_criticality: isCritical ? "critical" : "tracking",
    module: "...",
  },
});
```

This enables dashboard filters:
- `write_criticality:critical` → real data loss events (alert on these)
- `write_criticality:tracking` → noise (monitor volume, don't alert)

---

## Anti-Patterns

### 1. Alarming on payload presence

```typescript
// WRONG — triggers false alarms for tracking writes
if (hasFormDataContent(params.formData)) {
  captureException(new Error("FORM DATA LOST"));
}
```

The data being present in the payload doesn't mean it's lost — it may be saved by a downstream write.

### 2. All writes treated equally

```typescript
// WRONG — every failed write fires the same alarm
if (error) {
  captureException(error);
}
```

A funnel analytics write and a payment confirmation write have vastly different severity.

### 3. Retry everything

```typescript
// WRONG — retrying a constraint violation wastes time
if (error) {
  await sleep(1000);
  return operation(); // Will fail with the same error
}
```

Only retry transient transport errors. Application errors need different handling.

### 4. Silencing everything

```typescript
// WRONG — real data loss goes undetected
try { await write(); } catch { /* swallow */ }
```

Fire-and-forget is fine for tracking writes, but critical writes MUST alarm on failure.

---

## Audit Checklist

When reviewing a codebase for write criticality issues:

- [ ] Are there `captureException` calls triggered by `hasData && error`? (likely false alarms)
- [ ] Do fire-and-forget writes pass data that's also saved elsewhere? (tracking, not critical)
- [ ] Is the critical durability boundary identified? (the ONE place where data must persist)
- [ ] Does the critical write have retry logic for transient errors?
- [ ] Are Sentry alarms tagged with `write_criticality` for filterability?
- [ ] Can you answer: "If write X fails, where else is the data captured?"
