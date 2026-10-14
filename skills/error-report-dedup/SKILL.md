---
name: error-report-dedup
description: 'Use when two error handlers sit on the same throw path and each can report to your error tracker (e.g. an inner span/critical-path/retry wrapper that captures-and-rethrows, wrapped by an outer action wrapper that also captures). Tag the Error with a non-enumerable Symbol.for marker so the second handler skips a duplicate event. Triggers on: nested try/catch that both captureException, duplicate issues for one failure, a capture-and-rethrow wrapper, "why are we getting two Sentry events per error".

'
---

# Error Report Dedup Marker

When an error passes through two handlers that each report it, your error tracker logs the same failure twice — noisy issues, inflated counts, double alerts. This happens whenever a capture-and-rethrow wrapper (span tracker, critical-path timer, retry helper) is nested inside an outer catch that also captures.

## When this activates

- A capture-and-rethrow wrapper nested inside an outer catch that also captures.
- Duplicate issues in Sentry/Bugsnag/Rollbar for a single failure.
- Any "report once, no matter how many handlers see it" requirement.

## The pattern

Mark the Error object once; check the mark before reporting.

```ts
// error-reported.ts
const REPORTED = Symbol.for("myapp.errorReported");

export function markReported(e: Error): void {
  Object.defineProperty(e, REPORTED, {
    value: true,
    enumerable: false, // never serializes into logs / JSON / the tracker payload
    configurable: true,
    writable: true,
  });
}

export function wasReported(e: Error): boolean {
  return (e as unknown as Record<symbol, unknown>)[REPORTED] === true;
}
```

Producer (inner wrapper):

```ts
catch (error) {
  const err = error instanceof Error ? error : new Error(String(error));
  markReported(err);
  reportToTracker(err);
  throw err; // ← rethrow the MARKED err, not the original `error`
}
```

Consumer (outer wrapper):

```ts
catch (error) {
  const err = error instanceof Error ? error : new Error(String(error));
  if (!wasReported(err)) {
    markReported(err);
    reportToTracker(err);
  }
  return genericResponse;
}
```

## Core rules

1. **Non-enumerable + `Symbol.for`.** Non-enumerable so the marker never serializes into logs, JSON, or the tracker payload. `Symbol.for` (the global registry) so it's the same symbol across module instances/bundles.
2. **The marker is identity-bound — rethrow the SAME object.** This is THE subtle bug. If the producer normalizes a non-Error throw into a fresh Error, marks THAT, but then does `throw error` (the original raw value), the marker is lost. The outer handler re-normalizes into yet another Error with no marker and reports again. Always rethrow the normalized, marked Error.
3. **Mark before reporting**, so a re-entrant or concurrent path sees it.

## Anti-patterns

- A plain field (`error.__reported = true`) — enumerable, leaks into serialized payloads and can confuse the tracker's grouping.
- A module-local `Symbol()` — different module instances don't share it, so the check silently always misses.
- `throw error` after marking a different normalized object — the headline bug above.
- Deduping by message/stack string — fragile and collides across distinct failures.

## Test both sides

- **Consumer** honors a pre-marked error (no second report).
- **Producer** marks AND rethrows the marked error — *including the non-Error-throw case*: assert the rethrown value is an Error and `wasReported` is true. Teams forget the producer test, and without it, deleting the producer's `mark` stays green while prod double-reports.

## Audit checklist

- [ ] Marker is a non-enumerable `Symbol.for`.
- [ ] Producer rethrows the marked (normalized) Error, not the raw original.
- [ ] Both producer and consumer have tests, including a non-Error throw.

## Cross-references

- `surface-upstream-errors` — don't swallow the real error while deduping.
- `control-flow-exceptions` — rethrow framework control-flow signals (e.g. Next.js `unstable_rethrow`) as the FIRST line of the catch, before any capture or dedup.
- `observability` — error-tracker setup and grouping.
