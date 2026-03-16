---
title: "Structured Logging"
subtitle: "Logs that tell a story"
chapter: 17
section: "Observability"
seo_title: "Structured Logging Patterns for Next.js and Sentry in 2026"
seo_description: "Replace console.log chaos with domain loggers, wide events, automatic context injection, and PII redaction in TypeScript."
keywords: ["structured logging", "sentry logging", "domain loggers", "wide events", "observability", "typescript logging"]
reading_time: "8 min"
difficulty: "intermediate"
tech_stack: ["Next.js", "Sentry", "TypeScript"]
business_case: "Reduce mean-time-to-resolution from hours to minutes by making every log searchable, correlated, and enriched with business context."
---

# Structured Logging

> "A log without context is just noise with a timestamp."

## The Problem

Open any production codebase and you will find the same graveyard: thousands of `console.log` statements scattered across server actions, webhook handlers, and background jobs. When something breaks at 2 AM, you grep through Vercel logs praying that the person who wrote `console.log("here")` left enough breadcrumbs to reconstruct what happened.

They never did.

Unstructured logs fail in three specific ways. First, they are unsearchable. You cannot filter `console.log("Payment failed")` by organization, user, or request ID because none of that context was attached. Second, they are uncorrelated. A single user action might touch a server action, a webhook handler, and a background job, producing three separate log lines with no way to connect them. Third, they leak secrets. Without automatic redaction, someone eventually logs a full request body containing an API token, a password, or a credit card number.

The result is an observability system that only works when you already know where the problem is.

## The Principle

Structured logging inverts the debugging model. Instead of hunting for clues after a failure, every log entry arrives pre-enriched with the context you need to understand it. The log tells a story: who did what, in which organization, during which request, and how long it took.

Three ideas make this work:

**Domain loggers.** A generic `logger.info()` call forces you to manually attach context every time. A domain logger — `webhookLogger`, `paymentLogger`, `schedulerLogger` — automatically tags every log with its module, so you can filter an entire subsystem in one query.

**Wide events.** Prefer fewer, attribute-rich log entries over many thin ones. Instead of five logs tracing a booking through each step, emit one "wide event" at the end that captures the full story: booking ID, duration, outcome, timezone, and organization. One searchable entry replaces five noisy ones.

**Automatic context injection.** The logger reads the current user, organization, request ID, and trace ID from the request context and attaches them to every log automatically. You never have to remember to add `organization_id` — it is always there.

## The Pattern

### The Logger Architecture

Build a centralized logger module that wraps your observability provider. Every log passes through this module, which injects context, redacts secrets, and dispatches to both your observability platform and console output.

```typescript
// lib/logger.ts
import * as Sentry from "@sentry/nextjs";

type LogLevel = "debug" | "info" | "warn" | "error";
type LogAttributes = Record<string, unknown>;

function getContextAttributes(): LogAttributes {
  // Read from AsyncLocalStorage or your auth provider
  // Returns: user_id, organization_id, request_id, trace_id, span_id
  return {};
}

const REDACT_PATTERNS = [
  "password", "token", "secret", "api_key",
  "access_token", "refresh_token", "authorization",
  "credit_card", "card_number", "cvv", "ssn",
];

function redactSensitive(attrs: LogAttributes): LogAttributes {
  const result: LogAttributes = {};
  for (const [key, value] of Object.entries(attrs)) {
    const lower = key.toLowerCase();
    const shouldRedact = REDACT_PATTERNS.some((p) => lower.includes(p));
    result[key] = shouldRedact ? "[REDACTED]" : value;
  }
  return result;
}

function createLogFn(level: LogLevel, bindings: LogAttributes = {}) {
  return (message: string, attrs: LogAttributes = {}) => {
    const merged = redactSensitive({
      ...getContextAttributes(),
      ...bindings,
      ...attrs,
    });

    // Send to observability platform
    Sentry.logger[level](message, merged);

    // Dual output for local development
    if (process.env.NODE_ENV === "development") {
      console.log(JSON.stringify({ level, message, ...merged }));
    }
  };
}
```

### Domain Loggers

Create pre-configured loggers for each subsystem. The `module` tag is baked in so every log from that domain is instantly filterable.

```typescript
// lib/logger.ts (continued)
export function createModuleLogger(module: string) {
  const bindings = { module };
  return {
    debug: createLogFn("debug", bindings),
    info: createLogFn("info", bindings),
    warn: createLogFn("warn", bindings),
    error: createLogFn("error", bindings),
  };
}

// Pre-configured domain loggers
export const webhookLogger = createModuleLogger("webhooks");
export const paymentLogger = createModuleLogger("payments");
export const schedulerLogger = createModuleLogger("scheduler");
export const aiLogger = createModuleLogger("ai");
```

Usage is frictionless. Import the domain logger and call it:

```typescript
import { webhookLogger } from "@/lib/logger";

webhookLogger.info("Stripe webhook received", {
  event_type: "payment_intent.succeeded",
  payment_id: "pi_abc123",
});
```

In your observability dashboard, filter by `module:webhooks` to see every webhook log, or narrow down with `module:webhooks payment_id:pi_abc123` to find the exact event.

### Wide Events Over Thin Logs

```typescript
// BAD: Five thin logs for one operation
logger.info("Order started", { order_id: id });
logger.info("Checking inventory", { order_id: id });
logger.info("Payment charged", { order_id: id });
logger.info("Shipping label created", { order_id: id });
logger.info("Order complete", { order_id: id });

// GOOD: One wide event that captures the full story
logger.info("Order completed", {
  order_id: id,
  stage: "complete",
  duration_ms: elapsed,
  organization_id: orgId,
  payment_id: paymentId,
  outcome: "confirmed",
  shipping_method: method,
  item_count: items.length,
});
```

Use `logger.debug()` for intermediate steps that are only useful during local development. These are filtered out in production automatically.

### Domain-Specific Error Capture

For failures that should trigger alerts, create typed capture functions that set proper tags and fingerprints:

```typescript
// lib/error-capture.ts
import * as Sentry from "@sentry/nextjs";

interface PaymentErrorContext {
  organizationId: string;
  stage: "webhook" | "storage" | "matching";
  paymentId?: string;
  amount?: number;
}

export function capturePaymentException(
  error: Error,
  context: PaymentErrorContext
) {
  Sentry.withScope((scope) => {
    scope.setFingerprint([
      "payment-failure",
      context.stage,
      context.organizationId,
    ]);
    scope.setTag("payment.critical", "true");
    scope.setTag("payment.stage", context.stage);
    scope.setContext("payment", context);
    Sentry.captureException(error);
  });
}
```

The fingerprint groups errors by business context — same failure stage in the same organization — rather than by stack trace. This prevents one bug from generating hundreds of unrelated issues.

### Attribute Naming Conventions

Consistency makes logs searchable. Namespace attributes by domain using `snake_case`:

| Domain | Prefix | Examples |
|--------|--------|---------|
| Order | `order_*` | `order_id`, `order_stage`, `order_total` |
| Webhook | `webhook_*` | `webhook_provider`, `webhook_event_type` |
| Payment | `payment_*` | `payment_intent_id`, `payment_amount` |
| AI | `ai_*` | `ai.model.id`, `ai.duration.ms`, `ai.tokens.prompt` |
| General | no prefix | `user_id`, `organization_id`, `trace_id` |

One naming convention means one query syntax works everywhere: `organization_id:org_xyz` finds logs, errors, and traces simultaneously.

### Log Level Filtering by Environment

| Environment | Observability Platform | Console |
|-------------|----------------------|---------|
| Production | `info` and above | `info` and above |
| Preview | `debug` and above | `debug` and above |
| Development | `debug` and above | `debug` and above |

Production filters out `debug` to keep signal-to-noise high. Use `logger.debug()` for verbose development tracing, `logger.info()` for operational events you need in production.

## The Business Case

**Mean-time-to-resolution drops from hours to minutes.** When a customer reports "my payment failed," you search `organization_id:org_xyz module:payments level:error` and see the exact failure, the exact stage, and the exact trace — in one query.

**PII incidents drop to zero.** Automatic redaction catches secrets before they reach your log storage. You do not depend on every engineer remembering to sanitize their logs.

**Alert fatigue drops by 80%.** Custom fingerprints group errors by business context instead of stack trace, eliminating duplicate noise. Domain-specific capture functions ensure alerts only fire for failures that actually impact users.

**Debugging crosses service boundaries.** Because every log carries `trace_id`, you can follow a single user action from the browser through a server action, into a webhook handler, and through a background job — all connected by one identifier.

## Try It

Install the [Modh Playbook](https://github.com/modh-ai/playbook) to get the complete structured logging setup with domain loggers, PII redaction, and wide event patterns pre-configured for Next.js and Sentry.
