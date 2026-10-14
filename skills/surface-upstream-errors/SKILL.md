---
name: surface-upstream-errors
description: 'A third-party SDK throws a rich, structured error (HTTP status, machine code, human-readable long message, trace id, per-item failures) and your catch block flattens it into "Something went wrong. Please try again." Now the user can''t act on it and your logs can''t be queried by cause — you''ve thrown away the diagnosis at the exact moment it mattered. Parse the structured error, surface the real reason in the UI, and tag observability by the upstream code. Corollary: when the upstream call is an ATOMIC bulk endpoint, pre-filter known conflicts so one bad item can''t fail the whole batch. Triggers on any catch block around a call to an external API/SDK (Stripe, Clerk, Nylas, payment/auth/calendar/email providers), and on any use of a provider''s bulk/batch endpoint.'
---

# Surface Upstream Errors

## When This Skill Activates

- A `catch` around an external SDK/API call returns a generic string
  ("Failed. Please try again.") regardless of what actually failed
- An error is logged/captured as just `error.message` (e.g. "Forbidden",
  "Bad Request") with none of the provider's structured detail
- You're matching provider errors with `message.includes("already exists")`
  string sniffing instead of the provider's stable error `code`
- A bug is "failing in production" but the logs don't say *why* — the issue
  groups under one opaque title with no upstream code
- You're about to call a provider's **bulk / batch** endpoint with a
  user-supplied list
- A user reports a confusing or unhelpful error message from a third-party
  operation (checkout, invite, calendar sync, send)

## The Diagnostic Question

> **"When this external call fails, can the user see *why* — and can I query my
> logs by the upstream error code? If the answer to either is no, I'm swallowing
> the diagnosis."**

A generic catch-all message is a decision to be blind. The provider already
told you the cause in structured form; flattening it is throwing that away.

## Why This Happens

Mature providers return **structured** errors, not just a message:

| Field | Example | Use |
|-------|---------|-----|
| HTTP `status` | `403`, `409`, `422`, `429` | Branch on class (authz vs conflict vs validation vs rate-limit) |
| machine `code` | `not_allowed_access`, `resource_missing`, `duplicate_record` | Stable key for handling + observability grouping |
| `long_message` | "Your plan's member limit has been reached." | Already written for end users — show it |
| `trace_id` / request id | `trace_abc123` | Hand to support; correlate with provider dashboards |
| per-item errors | `meta.email_addresses`, index | Map a batch failure back to the offending item |

A naive `catch (e) { return "Please try again" }` discards all five. The
failure keeps happening, the user can't self-serve, and your Sentry/Datadog
issue is one undifferentiated bucket titled "Forbidden" — so you can't even
tell a plan-limit error from a transient blip.

## Decision Tree

```
catch (error) around an external SDK/API call
  │
  ├─ Is the thrown value the provider's structured error?
  │   (guard: isStripeError / isClerkAPIResponseError / instanceof XError)
  │     │
  │     ├─ YES → parse → { status, code, longMessage, traceId, entries[] }
  │     │           │
  │     │           ├─ UI: show longMessage (or your mapped copy for codes
  │     │           │       that deserve a specific CTA, e.g. limit → "upgrade")
  │     │           │
  │     │           └─ Observability: tag by `code` + `status`, fingerprint
  │     │                   by code, attach traceId. NEVER tag by IDs.
  │     │
  │     └─ NO  → structural fallback ({status, errors[]}) → else message-only.
  │              Still capture; don't pretend it's a known error.
  │
  └─ Is this call a BULK / batch endpoint that is ATOMIC + rejects on conflict?
        │
        └─ YES → pre-filter known conflicts BEFORE the single bulk call, and
                 map per-item errors back to items for partial-success UX.
                 (see "Atomic Bulk" section)
```

## Core Rules

### Rule 1 — Parse, don't flatten

Extract the provider's structured fields into a transport-agnostic shape, once,
in a reusable helper. Every call site reuses it.

```ts
// ✅ CORRECT — one parser, reused everywhere
interface ParsedError {
  status?: number;
  code?: string;
  message: string;
  longMessage?: string;   // provider's end-user copy
  traceId?: string;
  entries: { code: string; message: string; itemKeys?: string[] }[];
}

function parseProviderError(e: unknown): ParsedError {
  if (isProviderApiError(e)) {            // use the SDK's official guard
    const first = e.errors[0];
    return {
      status: e.status, code: first?.code, message: first?.message ?? e.message,
      longMessage: first?.longMessage, traceId: e.requestId,
      entries: e.errors.map(x => ({ code: x.code, message: x.message, itemKeys: x.meta?.ids })),
    };
  }
  return { message: e instanceof Error ? e.message : String(e), entries: [] };
}
```

```ts
// 🔴 WRONG — the diagnosis is gone the instant you write this
catch (e) { return { ok: false, error: "Something went wrong. Please try again." }; }
```

### Rule 2 — The user-facing message comes FROM the error

Default to the provider's `longMessage` (it's already user-friendly). Only
override with custom copy for codes where you want a specific next step.

```ts
function toUserMessage(p: ParsedError): string {
  if (isLimitReached(p))  return "Your plan's limit has been reached. Upgrade or remove one first.";
  if (p.status === 429)   return "Too many requests. Please wait a moment and try again.";
  return p.longMessage || p.message || "We couldn't complete that. Please try again.";
  //     ^ provider copy first — even UNKNOWN codes degrade to a helpful message
}
```

### Rule 3 — Tag observability by the upstream code, fingerprint by it

```ts
// ✅ low-cardinality CODE + STATUS as tags; IDs go in context/extra, never tags
captureException(error, {
  tags: { provider_code: p.code, provider_status: String(p.status) },
  fingerprint: p.code ? [stage, p.code] : [stage],   // limit-error ≠ transient blip
  extra: { traceId: p.traceId, entityId },
});
```

Without this, every failure mode groups under one issue ("Forbidden") and you
can't alert on, count, or triage the one that matters.

### Rule 4 — Match on `code`, never on `message.includes(...)`

Provider messages are localized and reworded without notice; codes are a stable
contract. String-sniffing the message is a silent time bomb.

## Atomic Bulk

Many providers expose a bulk/batch endpoint that is **all-or-nothing**: if any
one item conflicts (already exists, invalid), the *entire* request is rejected
and nothing is created. Handing it a raw user list means one stale item nukes
the whole batch.

```
1. Normalize + de-duplicate the input list.
2. Look up KNOWN conflicts up front (existing records, pending state) and
   partition: { conflicts[] (report as skipped), toSend[] }.
3. Send toSend[] in ONE bulk call.
4. On throw: parse the error; map per-item errors (meta) back to specific
   items; report the rest with the batch-level reason. Partial success ⇒
   still a "success" response carrying per-item statuses, so the user sees
   exactly which items went through and which didn't.
```

The pre-filter is what turns "one duplicate fails everyone" into "duplicates
are skipped, the rest go through." The per-item mapping handles the race where
something became a conflict between your check and the call.

## Anti-Patterns

- **The generic catch-all.** `catch { return "Please try again" }` — the single
  most common way a recurring production bug stays invisible for days.
- **Logging `error.message` only.** "Forbidden" tells you nothing; the `code`
  and `trace_id` sitting next to it tell you everything.
- **`message.includes("...")` branching.** Breaks the day the provider rewords
  the string. Use the code.
- **IDs as tags.** Tagging by `user_id`/`order_id` explodes your observability
  index. Codes/statuses are tags; IDs are context/log attributes.
- **Trusting `.d.ts` over the wire contract.** SDK types sometimes mark a
  required field optional (or vice versa). When a call 4xxs unexpectedly, read
  the provider's API docs, not just the type.
- **Raw list → atomic bulk endpoint.** No pre-filter ⇒ one known conflict fails
  the whole batch.

## Audit Checklist

- [ ] Every `catch` around an external call parses the structured error (via a
      shared helper), not just `error.message`
- [ ] User-facing copy derives from the provider's `longMessage`, with custom
      overrides only for codes that warrant a specific CTA
- [ ] Error captures tag by `code` + `status` and fingerprint by `code`
- [ ] `trace_id` / request id is attached to the capture
- [ ] No `message.includes(...)` branching on provider errors — match on `code`
- [ ] No IDs used as tags (IDs → context/log attributes)
- [ ] Bulk endpoints pre-filter known conflicts and return per-item statuses
- [ ] A reusable `parseProviderError` helper exists per provider, unit-tested
      against a real constructed SDK error + a structural fallback + a plain Error

## Related Skills

- `pii-safe-error-logs` — keep the structured detail you surface PII-safe
- `control-flow-exceptions` — some "errors" are navigation signals; re-throw them
- `observability` — tag vs log-attribute vs context discipline
- `webhook-observability` — the inbound-direction sibling of this pattern
