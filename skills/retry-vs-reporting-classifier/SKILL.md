---
name: retry-vs-reporting-classifier
description: >
  Keep two error questions apart: "should I retry this?" and "is this the code's
  fault?". One classifier decides retries and must stay narrow; a separate,
  reporting-only classifier recognises an unreachable dependency (database pool
  full, connection refused, connect timeout) and files it as a degradation in its
  own error-tracker group. Triggers on: an error-tracker issue for one query or
  endpoint that fires during every outage, "this was fixed but the issue came
  back", adding a catch around a DB or provider call, widening a transient-error
  or retry classifier, EMAXCONN / too many connections / pool exhaustion in a
  feature's error stream.
---

# Retry Classifier vs Reporting Classifier

A failed database call can mean two very different things. Either **your code
did something wrong** (a slow query, a bad parameter, a constraint violation), or
**the dependency was not there** (the connection pool was full, the connection
timed out, it dropped). The second says nothing about your code. Treat it like
the first and every feature-level error issue becomes another alarm for the same
outage, and a real regression hides in the noise.

The fix is two classifiers that answer two different questions, and never one
classifier stretched to answer both.

## When This Skill Activates

- An error issue tied to one query, endpoint or feature keeps firing after its fix
  shipped, and the new events are pool-full or connection errors
- You are writing a `catch` around a database or provider call that reports to an
  error tracker
- Someone proposes adding "max connections" or "connection refused" to the
  transient/retry classifier so a feature's errors "go away"
- A post-incident review finds ten feature issues that all fired at once during
  one database overload

## The Two Questions

```
A DB / provider call threw. Two independent decisions:

Q1: Should I retry it?                 (RETRY classifier, drives behaviour)
    ├─ Brief blip that a second attempt usually clears
    │  (connect timeout on a healthy pool, connection reset)  → retry once
    ├─ Dependency saturated (pool full, too many connections)  → DO NOT retry
    │      retrying adds load at the worst possible moment
    └─ Real failure (constraint, bad input, schema drift)      → DO NOT retry

Q2: Is this the code's fault?          (REPORTING classifier, drives where it is filed)
    ├─ Dependency unreachable: pool full, connection refused,
    │  connect timeout, connection dropped                     → NOT the code's fault
    │      file as a warning, in its own group ("db_unavailable")
    ├─ Statement timeout                                       → the code's own signal
    │      the query DID run; its cost is exactly what this issue watches
    └─ Everything else                                         → the code's fault
           file as an error, in the feature's normal group
```

The two trees disagree on purpose. "Pool full" is the clearest example: Q1 says
never retry it, Q2 says it is not the code's fault. One classifier cannot give
both answers.

## Core Rules

### 1. Never widen the retry classifier to fix a reporting problem

```ts
// WRONG: makes pool exhaustion "transient", so every caller now retries
// against a full pool and doubles the load during the overload.
const RETRYABLE = /CONNECT_TIMEOUT|ECONNRESET|max client connections/i;
```

```ts
// CORRECT: retry classifier stays narrow (blips that recover)...
const RETRYABLE_CODES = new Set(["CONNECT_TIMEOUT", "ECONNRESET"]);

// ...and a SEPARATE reporting-only predicate covers "unreachable".
export function isDependencyUnavailable(error: unknown): boolean { /* below */ }
```

### 2. Walk the cause chain, depth-capped

ORMs and query builders throw a generic `Failed query: ...` and hang the driver
error on `cause`. A classifier that reads only the thrown error matches nothing.

```ts
const UNAVAILABLE_CODES = new Set([
  "CONNECT_TIMEOUT", "CONNECTION_CLOSED", "CONNECTION_ENDED",
  "ECONNRESET", "ECONNREFUSED", "ETIMEDOUT",
  "53300", // Postgres SQLSTATE too_many_connections
]);
const UNAVAILABLE_MESSAGE =
  /max client connections|too many connections|failed to connect to database|connection (?:closed|terminated|reset)/i;

export function isDependencyUnavailable(error: unknown): boolean {
  let current: unknown = error;
  for (let depth = 0; depth < 5; depth += 1) {        // chains can be cyclic
    if (typeof current !== "object" || current === null) return false;
    const code = "code" in current ? current.code : undefined;
    if (typeof code === "string" && UNAVAILABLE_CODES.has(code)) return true;
    const message = "message" in current ? current.message : undefined;
    if (typeof message === "string" && UNAVAILABLE_MESSAGE.test(message)) return true;
    current = "cause" in current ? current.cause : undefined;
  }
  return false;
}
```

### 3. Keep statement timeouts as the code's own signal

A statement timeout means the query reached the database and ran too long. That
is exactly the regression a query-level issue exists to catch. Excluding it
"because it also happens during overloads" hides the one failure the issue is for.

### 4. File unavailability as a degradation in its own group

```ts
} catch (error) {
  const unavailable = isDependencyUnavailable(error);
  reportError(error, {
    feature: "member-filter",
    // own group, so the feature's issue only fires for the feature's failures
    fingerprint: unavailable ? ["member-filter", "db_unavailable"] : ["member-filter"],
    // the page absorbed it (empty dropdown); this is not a broken feature
    level: unavailable ? "warning" : "error",
  });
  return [];
}
```

The overload itself belongs to whatever watches the pool (connection-count alert,
pooler dashboard). The feature should not page as a second copy of that alarm.

### 5. Prove the cause before re-opening a "fixed" ticket

When an issue fires again after a fix, read the error type before concluding the
fix failed:

1. Read the recent events' error messages, not just the issue title.
2. Measure the operation directly in production (`EXPLAIN ANALYZE` a read).
3. Date when the fix actually reached production (migration ledger, deployed SHA).

A one-millisecond query that "timed out" during a known overload window is the
overload, not the query.

## Anti-Patterns

| Anti-pattern | Why it hurts |
|---|---|
| One `isTransientError` used for both retry and reporting | Either it retries against a full pool, or it reports blips as bugs |
| Matching only the thrown error, not its `cause` | Wrappers hide the driver code; the classifier never matches |
| Folding statement timeouts into "unavailable" | Hides the query's own regression |
| Muting the feature issue entirely during overloads | You lose the record that users saw a degraded page |
| Re-opening a fixed ticket on issue count alone | Overload events look identical to a regression until you read them |

## Audit Checklist

- [ ] Is there exactly one retry classifier, and does it exclude pool exhaustion?
- [ ] Is there a separate, reporting-only "dependency unavailable" predicate?
- [ ] Do both walk the error cause chain with a depth cap?
- [ ] Do feature catches file unavailability as a warning in its own fingerprint group?
- [ ] Do statement timeouts still report as the feature's own error?
- [ ] Does something else (pool/connection alert) own the overload signal itself?
- [ ] Before re-opening a "fixed" issue: were event error types read and the operation measured?
