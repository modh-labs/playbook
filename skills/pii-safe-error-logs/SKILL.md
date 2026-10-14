---
name: pii-safe-error-logs
description: >
  Use whenever a server error with a structured payload flows into a UI
  error handler. Separate errorMessage (human-readable, may carry PII)
  from errorCode (machine-readable, log-safe). The errorCode goes into
  structured logs, Sentry tags, and metric dimensions; the errorMessage
  goes into the toast / banner the user sees. Skipping this split is how
  email addresses and phone numbers end up in Logflare.
---

# PII-Safe Error Logs

Server-side error handlers often encode the triggering user's email,
phone, or name into the message string:

```json
{
  "error": "DUPLICATE_BOOKING",
  "message": "A booking already exists for user@example.com on 2026-04-20"
}
```

That payload reaches the client, gets parsed, and flows into a pattern
like this:

```ts
// ❌ PII leaked into structured logs
const errorMessage = parsed.message ?? parsed.error ?? fallback;
clientLogger.error(error, { context: "Booking failed", errorMessage });
toast.error(errorMessage);
```

The toast is fine — the user typed that email, they know it. The log
line is not fine — it's now indexed in Logflare / Sentry / any log
aggregator with PII searchable as free text. That's a GDPR exposure
surface and makes log-driven debugging noisier.

## The split

Treat `error` (the code) and `message` (the body) as different things:

```ts
// ✅ PII-safe split
let errorMessage = "Failed. Please try again.";   // user-facing
let errorCode: string | null = null;              // log-safe

if (error instanceof Error) {
  try {
    const parsed = JSON.parse(error.message) as {
      message?: string;
      error?: string;
    };
    errorMessage = parsed.message || parsed.error || error.message;
    errorCode = parsed.error ?? null;
  } catch {
    errorMessage = error.message;
  }
}

// Toast gets the human-readable message.
toast.error(errorMessage);

// Log context gets the CODE only — never the message.
clientLogger.warn("Booking failed", {
  error_code: errorCode,
  is_recoverable: isRecoverableError(errorCode),
  // plus entity context (booking_link_id, organization_id)
});

// Sentry gets the Error + the code as a tag/metadata.
captureSchedulerException(error, {
  stage: "nylas_api",
  organizationId,
  linkId,
  metadata: { errorCode },  // NOT errorMessage
});
```

## When this applies

Any client-side catch block that receives a structured-error payload
from a server action, fetch, or RPC. Common cases:

- Booking / payment / checkout confirmations
- Form submissions that hit a server action
- Inline mutations from data tables
- Webhook-receiver ack paths that surface errors to the admin

## When this does NOT apply

- Plain `new Error("...")` with a hand-written message you control — if
  you wrote the string, you already chose what's in it. Just don't put
  PII in it.
- Zod validation errors — the paths are safe, but the `input` often has
  PII. Log the error code, not the parsed input.
- Frontend-only errors (React render errors, etc.) — these rarely carry
  PII, but check before logging the full error object.

## Red flags in code review

- `clientLogger.error(error, { ..., errorMessage })` — the raw message
  should not sit in the log context alongside other fields.
- `JSON.stringify(error)` inside a logger call — dumps everything
  including nested PII.
- Sentry `captureException(error, { extra: { email } })` — `extra` is
  searchable in Sentry; if the value can be a PII field, move it to a
  tag (hashed) or omit.
- Toast + log from the same string without parsing — if you're pulling
  from one variable to both UI and logs, one of them is wrong.

## Testing

A renderHook / unit test that:

1. Rejects the mocked server call with a PII-bearing message
2. Asserts the log payload does NOT contain the PII substring

```ts
it("scrubs PII from the log context", async () => {
  onBookingConfirm.mockRejectedValue(
    new Error(JSON.stringify({
      error: "DUPLICATE_BOOKING",
      message: "Duplicate for imran@modh.ca",
    }))
  );

  await act(() => result.current.handleConfirmBooking(slot));

  const [, payload] = vi.mocked(clientLogger.warn).mock.calls[0];
  expect(JSON.stringify(payload)).not.toContain("imran@modh.ca");
  expect(payload).toMatchObject({ error_code: "DUPLICATE_BOOKING" });
});
```

## Reference implementation

- `apps/web/app/_shared/components/booking-scheduler/internal/hooks/use-booking-scheduler-state.ts`
  — `handleConfirmBooking` error path uses this pattern.
- Test: `__tests__/use-booking-scheduler-state.test.ts` — "scrubs PII
  from the log context".

## Cross-references

- `observability-logging` skill — structured logging basics
- `security-and-compliance` chapter — PII classification + GDPR
- `code-review` skill — catches missing splits in review
