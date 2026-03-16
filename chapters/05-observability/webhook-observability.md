---
title: "Webhook Observability"
subtitle: "Every webhook traced end-to-end with searchable tags"
chapter: 15
section: "Observability"
seo_title: "Webhook Observability — End-to-End Tracing, Searchable Tags, Duration Tracking 2026"
seo_description: "Trace every webhook from arrival to completion with searchable tags, duration tracking, and idempotency verification. Debug production webhook issues in minutes."
keywords: ["webhook observability", "webhook tracing", "structured logging", "Sentry", "webhook debugging", "distributed tracing"]
reading_time: "9 min"
difficulty: "advanced"
tech_stack: ["Next.js", "Supabase", "TypeScript"]
business_case: "Reduces webhook debugging from hours of log-scrubbing to minutes of tag-filtered searching — directly impacting revenue when payment or calendar events go missing."
---

# Webhook Observability

> "The webhook that fails silently is worse than the webhook that fails loudly. Silence means you don't know it's broken until a customer tells you."

## The Problem

A customer calls support. "My payment went through but my account doesn't show it." The support agent checks the payment provider's dashboard — yes, the payment succeeded and the webhook was sent. Status: delivered. The provider did its job.

Now begins the investigation. The engineer checks the application logs. There are thousands of webhook events. They search for the payment ID — nothing. They search for the customer's email — three results, all from different days, none related to this payment. They search for the event type — hundreds of results. They start scrolling.

Two hours later, they discover the webhook was received but hit a database timeout on the insert. The error was caught, logged as a generic "Database error" with no payment ID, no customer ID, no organization ID — just a stack trace pointing to line 47 of the webhook handler. The retry arrived 30 seconds later, succeeded, but the customer's aggregate stats weren't updated because the retry skipped the stats update (a logic bug introduced during a refactor).

This is the reality of webhook debugging without observability. The events arrive. They succeed or fail. And the only evidence is a wall of undifferentiated text that requires human pattern-matching to extract meaning.

The cost compounds. Every webhook failure investigation follows the same painful pattern: identify the event, find the log entry, trace the execution path, determine the failure point, identify the downstream impact. Without structured, searchable, correlated logs, each step requires manual work. Teams that handle payment, calendar, and auth webhooks spend hours per week on investigations that should take minutes.

## The Principle

Every webhook handler must produce a single, wide log event at completion that captures the full context of what happened: which provider sent it, which event type, which organization, which entity was affected, how long it took, and whether it succeeded or failed. This log must be searchable by any of those dimensions.

We call this the "wide event" pattern. Instead of many thin log lines scattered through the execution path, you emit one rich log entry at the end that tells the complete story. Debug-level logs can exist for intermediate steps, but the wide event at completion is the primary artifact for production debugging.

## The Pattern

### The webhook logger

Create a structured logger that captures the context once and carries it through the entire handler:

```typescript
// lib/webhooks/webhook-logger.ts
import { logger } from "@/lib/logger";

interface WebhookLogContext {
  provider: string;        // "stripe" | "clerk" | "nylas" | "custom"
  handler: string;         // "handlePaymentCompleted" | "handleUserCreated"
  eventType: string;       // "payment.completed" | "user.created"
  eventId: string;         // Provider's event ID for deduplication lookup
  organizationId?: string; // Tenant context
  requestId: string;       // Unique per-request for log correlation
}

export function createWebhookLogger(context: WebhookLogContext) {
  const startTime = performance.now();

  return {
    start() {
      logger.info("Webhook received", {
        ...context,
        stage: "received",
      });
    },

    success(extra?: Record<string, unknown>) {
      const durationMs = Math.round(performance.now() - startTime);
      logger.info("Webhook processed", {
        ...context,
        stage: "complete",
        outcome: "success",
        duration_ms: durationMs,
        ...extra,
      });
    },

    skipped(reason: string) {
      const durationMs = Math.round(performance.now() - startTime);
      logger.info("Webhook skipped", {
        ...context,
        stage: "complete",
        outcome: "skipped",
        skip_reason: reason,
        duration_ms: durationMs,
      });
    },

    failure(error: Error, extra?: Record<string, unknown>) {
      const durationMs = Math.round(performance.now() - startTime);
      logger.error("Webhook failed", {
        ...context,
        stage: "complete",
        outcome: "failure",
        duration_ms: durationMs,
        error_message: error.message,
        error_name: error.name,
        ...extra,
      });
    },
  };
}
```

### Using the logger in handlers

Every webhook handler creates a logger at the top and calls exactly one completion method at the end:

```typescript
// app/api/webhooks/payments/route.ts
export async function POST(req: Request) {
  const requestId = `wh_${Date.now()}_${crypto.randomUUID().slice(0, 8)}`;
  const body = await req.text();
  const event = verifySignature(body, req.headers);

  const wh = createWebhookLogger({
    provider: "stripe",
    handler: `handle_${event.type}`,
    eventType: event.type,
    eventId: event.id,
    organizationId: event.metadata?.org_id,
    requestId,
  });

  wh.start();

  try {
    switch (event.type) {
      case "payment.completed":
        await handlePaymentCompleted(supabase, event, requestId);
        wh.success({ payment_id: event.data.payment_id });
        break;

      case "payment.refunded":
        await handlePaymentRefunded(supabase, event, requestId);
        wh.success({ refund_id: event.data.refund_id });
        break;

      default:
        wh.skipped(`Unhandled event type: ${event.type}`);
    }
  } catch (error) {
    wh.failure(error instanceof Error ? error : new Error(String(error)), {
      payment_id: event.data?.payment_id,
    });
    return Response.json({ error: "Processing failed" }, { status: 500 });
  }

  return Response.json({ received: true });
}
```

### Searchable tags on error captures

When a webhook fails in a way that should trigger an alert, the error capture must include searchable tags — not just log context. Tags are indexed and filterable in your error tracking system.

```typescript
import * as Sentry from "@sentry/nextjs";

function captureWebhookException(
  error: Error,
  context: {
    provider: string;
    eventType: string;
    handler: string;
    organizationId?: string;
    entityId?: string;
  }
) {
  Sentry.withScope((scope) => {
    scope.setTag("webhook.provider", context.provider);
    scope.setTag("webhook.event_type", context.eventType);
    scope.setTag("webhook.handler", context.handler);

    if (context.organizationId) {
      scope.setTag("webhook.organization_id", context.organizationId);
    }

    // Custom fingerprint groups by provider + event type + org
    // instead of by stack trace
    scope.setFingerprint([
      "webhook-failure",
      context.provider,
      context.eventType,
      context.organizationId ?? "unknown",
    ]);

    scope.setContext("webhook_event", {
      provider: context.provider,
      eventType: context.eventType,
      handler: context.handler,
      entityId: context.entityId,
    });

    Sentry.captureException(error);
  });
}
```

Custom fingerprinting is critical. Without it, every webhook failure with a different stack trace creates a separate issue. With it, all failures for the same provider + event type + organization group together. You see "Stripe payment.completed failures for org_abc" as a single issue with a count, not fifty separate noise entries.

### Idempotency tracking

Log whether the event was processed or skipped due to idempotency. This is the single most useful piece of debugging information for webhook investigations.

```typescript
async function handlePaymentCompleted(
  supabase: ServiceClient,
  event: PaymentEvent,
  requestId: string
) {
  // Attempt idempotent insert
  const { created, record } = await createPaymentIdempotent(supabase, {
    provider_payment_id: event.data.payment_id,
    amount_cents: event.data.amount,
    organization_id: event.metadata.org_id,
  });

  if (!created) {
    // Log that we skipped — this is NOT an error, it's expected on retries
    logger.info("Payment already processed (idempotent skip)", {
      requestId,
      provider_payment_id: event.data.payment_id,
      existing_record_id: record.id,
      idempotent_skip: true,
    });
    return;
  }

  // First time processing — update downstream entities
  logger.info("Payment created, updating aggregates", {
    requestId,
    payment_id: record.id,
    customer_id: record.customer_id,
    amount_cents: event.data.amount,
    idempotent_skip: false,
  });

  await updateCustomerStats(supabase, record.customer_id, event.data.amount);
}
```

### Duration tracking for performance visibility

Webhook handlers have implicit SLAs. Payment providers expect a response within 5-10 seconds. Calendar providers timeout at 30 seconds. If your handler regularly takes 8 seconds, you're one slow database query away from timeouts and cascading retries.

The webhook logger already tracks duration. Surface slow handlers as warnings:

```typescript
const SLOW_THRESHOLD_MS = 3000;
const VERY_SLOW_THRESHOLD_MS = 10000;

// In the success() method of the webhook logger
success(extra?: Record<string, unknown>) {
  const durationMs = Math.round(performance.now() - startTime);
  const level = durationMs > VERY_SLOW_THRESHOLD_MS
    ? "warn"
    : "info";

  logger[level]("Webhook processed", {
    ...context,
    stage: "complete",
    outcome: "success",
    duration_ms: durationMs,
    is_slow: durationMs > SLOW_THRESHOLD_MS,
    ...extra,
  });
}
```

Now you can query: "Show me all webhook events where `is_slow: true` in the last 24 hours." Performance degradation becomes visible before it causes timeouts.

### The debugging workflow

With all of this in place, debugging a webhook issue follows a predictable, fast path:

**Step 1: Find the event.** Search by the entity the customer is asking about — payment ID, booking ID, user email. The wide event log includes the entity context.

```
provider:stripe payment_id:pay_abc123
```

**Step 2: Check the outcome.** The log entry shows `outcome: success`, `outcome: skipped`, or `outcome: failure`. If skipped, the `skip_reason` or `idempotent_skip` field tells you why.

**Step 3: Trace related events.** Use the `request_id` to find all log entries from the same webhook invocation. Use the `organization_id` to find all events for the same tenant.

```
request_id:wh_1710000000_abc12345
```

**Step 4: Check timing.** The `duration_ms` field shows whether the handler was unusually slow. If it was, check for database contention or external API latency during that window.

What used to take two hours of log-scrolling now takes five minutes of tag-filtered queries.

## The Business Case

- **Revenue protection.** When payment webhooks fail, you lose money — either from missed charges or duplicate refunds. Structured logging with idempotency tracking lets you identify and resolve payment issues in minutes, not hours.
- **Support deflection.** Support agents can search webhook logs by customer ID or payment ID themselves, without escalating to engineering. This cuts escalation volume and improves resolution time.
- **Proactive detection.** Slow webhook alerts catch performance degradation before providers start timing out. You fix the bottleneck before customers notice their payments aren't being confirmed.

## Try It

Install the Modh Playbook skills to enforce this pattern automatically:
```bash
# Add to your project
git submodule add https://github.com/modh-labs/playbook .agents/modh-playbook
./.agents/modh-playbook/install.sh
```
