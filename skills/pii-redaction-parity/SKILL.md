---
name: pii-redaction-parity
description: >
  Use when an app sends errors/logs/traces to more than one sink (Sentry events,
  spans, and logs; a structured logger like pino/winston; an APM). Enforce ONE
  sensitive-key list across EVERY egress path, and watch structured-logger
  key-path shapes — a flat dotted key like record["user.email"] is NOT redacted
  by the path "user.email" in pino (it reads that as nested user→email). Triggers
  on: adding a log/trace sink, declaring a PII posture ("id + org only"), writing
  a redact/scrub/beforeSend config, or a "PII showed up in logs even though
  Sentry scrubbed it" report.
---

# PII Redaction Egress Parity

One principle: **PII redaction is only as strong as your weakest egress path.** If you scrub email from Sentry events but your structured logger writes it to stdout (and on to Logflare/Datadog/CloudWatch), you've leaked. Redaction is a property of the whole fan-out, not of one sink.

## When this activates

- Adding a second place errors/logs/traces leave the process (Sentry, pino/winston, an APM, an OTel exporter).
- Establishing a PII posture ("id + organization only", "no email/ip").
- Writing or reviewing a `redact` / `beforeSend` / `scrub` config.
- A "PII appeared in logs even though [Sentry/X] scrubbed it" incident.

## Two failure modes

### 1. Drift between egress paths

Each sink keeps its own copy of the "sensitive keys" list. They drift. One scrubs `email`; another never got the update. Fix: **one exported list, consumed everywhere.**

```
How many places define "what is sensitive"?
  ONE shared list → good. Derive every redactor from it.
  MORE than one  → they will drift. Consolidate now.

Does redaction run on EVERY sink?
  Sentry: beforeSend (events) + beforeSendSpan + beforeSendLog
  Logger: redact paths
  APM/exporter: its own scrubber
  Any sink without a scrubber = an open leak.
```

### 2. The structured-logger key-path-shape trap (the counterintuitive one)

Redaction in pino (and similar path-based redactors) is **path-shaped and case-sensitive**. How you WROTE the key decides which redact path matches:

- A nested object `{ user: { email } }` → matched by `user.email` or `*.email`.
- A **flat dotted key** — one key literally named `"user.email"`, e.g. `record["user.email"] = x` — is matched **only** by the bracket-literal path `["user.email"]`. The path `"user.email"` does **not** match it (pino reads that as nested `user`→`email`, which doesn't exist).

This bites hardest when an instrumentation hook copies OTel span attributes — which arrive as flat dotted keys (`user.email`, `organization.id`) — straight into the log record. Your redact list says `user.email`, you believe you're covered, and you're not.

Fix: for each sensitive name, emit every shape you actually write:

```ts
const redactPaths = SENSITIVE_KEY_NAMES.flatMap((name) => [
  name,                // bare:        { email }
  `*.${name}`,         // nested:      { user: { email } }
  `["user.${name}"]`,  // flat dotted: record["user.email"]
]);
```

## Core rules

1. **One source of truth.** Export a single `SENSITIVE_KEY_NAMES`; derive both the structured-logger redact config AND the Sentry/APM scrubber from it.
2. **Cover every egress.** For Sentry that's three hooks — `beforeSend`, `beforeSendSpan`, `beforeSendLog`. Spans and logs are not covered by the event hook.
3. **Fix leaks at the source, not just the sink.** If you set `user.email` as a span attribute and a hook fans it into logs, the real fix is to stop emitting it. Redaction is the backstop, not the primary control.
4. **Match the shape you write.** Audit how keys actually land (flat dotted vs nested) and redact that shape.
5. **Key-based redaction misses message bodies.** A PII value inside `error.message` ("duplicate for foo@bar.com") is not caught by key-based scrubbing — see `pii-safe-error-logs` for the call-site split.

## Anti-patterns

- Two copies of the sensitive-key list (logger + scrubber) — they WILL drift.
- Trusting `redact: ["user.email"]` to catch a flat `record["user.email"]` — it doesn't; verify empirically.
- Scrubbing events but not spans/logs.
- Redacting at the sink while still EMITTING PII onto spans that fan out to multiple sinks.

## Verify empirically

Redaction config is easy to get subtly wrong, and a wrong config fails silently. Write a test that logs each shape through the REAL config and asserts the value is gone:

```ts
it("redacts a flat dotted user.email key", () => {
  const out = captureLog({ "user.email": "a@b.com" });
  expect(out).toContain("[REDACTED]");
  expect(out).not.toContain("a@b.com");
});
```

Also assert the shipped logger uses the same path list (export it and compare), so a test that rebuilds its own logger can't pass while the real one leaks.

## Audit checklist

- [ ] One sensitive-key list, imported by every redactor.
- [ ] Logger redact covers bare + nested + any flat-dotted keys you write.
- [ ] Sentry `beforeSend` + `beforeSendSpan` + `beforeSendLog` all scrub.
- [ ] No PII set as a span attribute that fans out to logs.
- [ ] A test exercises each key shape through the real config.

## Cross-references

- `pii-safe-error-logs` — the call-site half: don't put PII in the message string you log.
- `observability` — structured logging + tracing basics.
- `security-and-compliance` — PII classification / GDPR.
