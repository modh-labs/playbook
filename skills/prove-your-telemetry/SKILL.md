---
name: prove-your-telemetry
description: >
  Instrumentation fails silently, and its failure looks exactly like good news.
  An absent field reads as "nothing to report", a quiet dashboard reads as
  "nothing is wrong", a low issue count reads as "we fixed it". Before trusting
  any of those, read a real emitted event and confirm it carries what you think.
  Use when adding or changing logging/error capture, when an error report has no
  useful detail, when a metric or dashboard is suspiciously quiet, when an error
  "stopped happening" on its own, or when a shipped fix cannot be confirmed.
---

# Prove Your Telemetry

## When This Skill Activates

- You are adding or changing a log line, error capture, tag, or metric
- An error report exists at volume but says nothing useful: "storing failed",
  an `Error` with an empty title, a field that is always `undefined`
- An error stopped happening and nobody changed anything
- A dashboard, alert, or issue count is quieter than you expected
- You shipped a fix and cannot tell from the data whether it landed
- You are about to write "this is fine, we'd see it in Sentry if it weren't"
- Someone asks "how do we know this is working?"

## The Diagnostic Question

> **"If this instrumentation were completely broken, would it look any
> different from what I'm seeing right now?"**

If the answer is no, you have not measured anything. You have measured your
own silence. Every mechanism below produces the same visible result as a
healthy system, which is precisely why they survive for months.

The corollary, which is the part people skip: **the only way to answer that
question is to go and read a real emitted event.** Not the code that emits it.
The event, in the tool, in production.

## Why This Is Its Own Failure Class

Normal bugs announce themselves. Broken telemetry does the opposite: it
**consumes the evidence of its own failure.** Nobody gets paged because a log
line is empty. Nobody investigates a dashboard that shows zero. The instrument
that would tell you the instrument is broken is the broken instrument.

So this cannot be caught by the usual reflexes (tests, code review, alerting).
It is caught by one habit: after wiring instrumentation, go look at what it
actually produced.

## The Five Mechanisms

### 1. The wrapper: the real error is on `cause`

Modern frameworks wrap rather than replace. Your `catch` receives a generic
outer error; the one with the diagnosis hangs off `cause`, sometimes several
levels down.

Known wrappers: ORMs (Drizzle, Prisma) wrapping driver errors, server-side
rendering frameworks wrapping render failures, AI/HTTP SDKs wrapping provider
responses, and any `new Error(msg, { cause })` in your own code.

```ts
// WRONG: finds nothing, forever, and reports `undefined` as if it were a fact
catch (error) {
    logger.error({ code: (error as { code?: string }).code }, "Write failed");
}

// CORRECT: walk the chain, depth-capped (chains can be cyclic)
function findErrorInChain<T>(
    error: unknown,
    match: (candidate: unknown) => candidate is T,
    maxDepth = 5,
): T | undefined {
    let current: unknown = error;
    for (let depth = 0; depth < maxDepth && current; depth += 1) {
        if (match(current)) return current;
        if (typeof current !== "object" || current === null) return undefined;
        current = (current as { cause?: unknown }).cause;
    }
    return undefined;
}
```

**The tell:** a field that is absent on *100%* of events. A field that is
genuinely sometimes-absent varies. A field never present once, across thousands
of events, is not a rare case. It is a read that never matches.

### 2. The scrubber: the field is present but redacted

Error trackers redact values that pattern-match as sensitive. A SQL query
string, a URL with credentials, anything resembling a token or an email will
come back as `[Filtered]`, `[REDACTED]`, or an empty string. The field exists.
It carries nothing.

```ts
// FRAGILE: one scrubbing rule away from useless
logger.error({ errorMessage: error.message }, "Write failed");

// ROBUST: short structured facts survive scrubbing, group better, and are
// what you would search on anyway
logger.error({
    errorName: error.name,
    errorCode: postgres?.code,          // SQLSTATE
    errorConstraint: postgres?.constraint_name,
    errorTable: postgres?.table_name,
    errorMessage: error.message,        // keep it, but never depend on it
}, "Write failed");
```

**The rule:** never let a free-text message be the *only* thing that explains a
failure.

### 3. The upstream filter: the event never reached your handler

Deny-lists, sample rates, rate limits and quota backoff drop events *before*
your `beforeSend`/processor runs. The drop is invisible: no log, no event, and
in aggregate reporting it appears only as an undifferentiated count.

The danger is a pattern broad enough to match your own code. Minified-bundle
messages are the canonical trap. `this.xy is not a function` describes a
vendor SDK on an old browser *and* a real bug in your own minified bundle,
identically.

```ts
// WRONG: evaluated before beforeSend. Matches leave no trace and cannot be
// audited, and this one also matches your own minified frames.
ignoreErrors: [/this\.\w{1,3} is not a function/]

// CORRECT: same intent, gated on provenance, visible and unit-testable
beforeSend(event) {
    if (isVendorNoise(tagErrorOrigin(event))) return null;
    return event;
}
```

**Check the ratio.** Pull your client-report / quota outcomes and compare
`accepted` against `filtered` + `discarded`. A 98%-to-2% split is not
self-evidently wrong, but it is self-evidently worth reading entry by entry.

### 4. The wrong hook: you instrumented a path the events don't take

A framework usually offers several places to observe an error, and only some of
them are on the path a given event takes. Instrument the wrong one and your
code runs, your tests pass, and the annotation attaches to nothing.

**The tell is the mismatched shape:** the event carries *some* of what your
handler sets but not the rest, or its context does not match what your handler
would have written. That means a different producer emitted it.

The fix is structural, not a bigger patch. **Put rules that must hold for every
event at the single point every producer converges on**: the one consumer hook
(`beforeSend` and equivalents), not one of many producers.

### 5. The dead subject: the thing being measured got switched off

Error volume returning to zero has at least three causes, and they are
indistinguishable from the graph alone:

1. It was fixed.
2. It self-healed (the transient condition passed).
3. **The thing that was erroring got disabled.**

Case 3 is the dangerous one, and it is common. A provider auto-pauses a webhook
endpoint that keeps failing, a feature flag turns off, a job stops being
scheduled, a queue stops being drained. The integration is now completely dead
and every error-rate alert reads healthy.

> **Health checks must assert movement, not configuration.**

Do not check that the subscription exists. Check that something arrived
through it recently. Do not check that the credential is stored. Check that a
call using it succeeded. "Configured" and "working" diverge silently, and only
the second one is what you care about.

## Decision Tree

```
You are about to trust a piece of telemetry.
│
├─ Is a field you rely on absent?
│   ├─ Absent on 100% of events?  ====> Mechanism 1 (wrapper). Walk `cause`.
│   └─ Present but empty/[Filtered]? ==> Mechanism 2 (scrubber). Log
│                                        structured facts instead.
│
├─ Are events missing entirely?
│   ├─ Dropped before your handler?  ==> Mechanism 3 (filter). Audit the
│   │                                    deny-list; check accepted vs filtered.
│   └─ Handler runs but doesn't stick? => Mechanism 4 (wrong hook). Move the
│                                        rule to the single consumer.
│
└─ Did the signal go quiet on its own?
    └─ Nobody deployed a fix?  =========> Mechanism 5 (dead subject). Check the
                                         subject is still alive and moving.
```

## Core Rules

1. **After wiring instrumentation, read one real emitted event.** In the tool,
   in the environment that matters. This single habit catches all five
   mechanisms and takes two minutes.
2. **An absent field is a hypothesis, not a fact.** Before you conclude the
   information does not exist, confirm your read can find it when it does.
3. **Structured facts over free text.** Codes, names, constraints, enums.
   Unscrubbable, groupable, queryable.
4. **One rule, one place.** Anything that must hold for every event belongs at
   the single point every producer converges on.
5. **Deny-lists must be provenance-gated.** If a pattern could match your own
   code, it does not belong in a pre-handler filter.
6. **Assert movement, not configuration.** A health check that reads settings
   is testing your database, not your integration.
7. **Never write "we'd have seen it" without having looked.** That sentence is
   the failure mode saying its own name.

## Anti-Patterns

```ts
// BAD: concluding from absence
// "errorCode is always undefined, so these aren't database errors."
// It was always undefined because the read never matched. They were all
// database errors.

// BAD: trusting a quiet graph
// "That issue dropped to zero after the deploy, so it is fixed."
// The provider had auto-paused the endpoint. The integration was dead.

// BAD: verifying instrumentation by reading the code that emits it
// The code was fine. It was attached to a path the events never took.

// BAD: broad pre-handler deny-list entries
ignoreErrors: ["Method not found", /clickId/i, "InvariantError"]
// Each of these can match your own code. You will never find out.

// BAD: a health check that reads configuration
const healthy = Boolean(connection.webhookSubscriptionId);
// Present is not delivering. Check for a recent inbound event instead.
```

## Audit Checklist

Run this against any instrumentation you depend on:

- [ ] I have opened a real emitted event and confirmed each field I rely on
      carries a value
- [ ] No field I rely on is absent on 100% of events
- [ ] No field I rely on arrives redacted, and no diagnosis depends only on a
      free-text message
- [ ] I know the accepted-vs-filtered-vs-discarded ratio for this stream, and
      have read the deny-list entries responsible for the discards
- [ ] No deny-list pattern could match my own (possibly minified) code
- [ ] Rules that must hold for every event live at the single consumer, not in
      one of several producers
- [ ] Every "this went quiet" conclusion has been checked against the subject
      still being alive
- [ ] Health checks assert recent movement, not stored configuration

## Related

This skill is the **presence** case: events are arriving, your instrumentation
is running, and it reports nothing anyway. Mechanisms 1, 2 and 4 are unique to
it. For the **absence** case (no events at all) and the cost case, the
neighbours below own the depth, and this skill only summarises them.

- `zero-errors-vs-nothing-firing`: mechanism 5 in full. Zero events means either
  healthy or dead, and every tool renders them identically. Read that one before
  concluding anything from a quiet query.
- `observability-cost-quota`: mechanism 3 when the cause is billing rather than
  a deny-list. Telemetry is metered per category, so traces can vanish entirely
  while errors keep flowing.
- `surface-upstream-errors`: the adjacent failure, where you *have* the rich
  error and flatten it at the catch boundary. This skill is the next question.
  Once you keep it, does it actually arrive?
- `observability`: the structured-logging and capture conventions this assumes
- `cron-monitor-checkin`: mechanism 5 applied to scheduled work
