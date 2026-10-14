---
name: observability
description: >
  Enforce structured logging, Sentry integration, and distributed tracing patterns.
  Use when adding logging, error tracking, Sentry tags, custom spans, metrics,
  webhook observability, or debugging production issues. Prevents console.log
  usage and ensures trace correlation.
---

# Observability & Logging Skill

## When This Skill Activates

- Adding logging to any code (server actions, repositories, webhooks, API routes)
- Working with error tracking or performance monitoring (e.g., Sentry)
- Adding tracing, custom spans, or distributed trace propagation
- Handling errors that need to be captured and alerted on
- Discussing debugging, metrics, or alerting strategy

---

## Decision Tree -- "What Do I Use?"

```
Error in webhook handler?     -> logger.error() + webhook failure capture
Error in server action?       -> logger.error() + domain-specific capture
Error in background job?      -> middleware auto-captures + logger.error()
Error in AI agent call?       -> AI exception capture (or instrumented wrapper)
Need to track duration?       -> startSpan() or webhook logger lifecycle
Need to filter in dashboard?  -> setTag() (low cardinality only)
Need debug data?              -> setContext() (not searchable)
Need charts/dashboards?       -> metrics.distribution() or .count()
Client-side error?            -> Error boundary component
Non-critical info log?        -> logger.info() (may not reach error tracker in prod)
```

---

## Core Rules

### 1. ALWAYS Use a Structured Logger Factory -- Never console.log

```typescript
// WRONG - Raw console
console.log("Processing order", orderId);

// CORRECT - Structured logger
import { createModuleLogger } from "@/lib/logger";
const logger = createModuleLogger("orders");

logger.info("Processing order", { order_id: orderId });
logger.error("Payment failed", { error, payment_id: paymentId });
```

Create module-specific loggers for each domain: `webhookLogger`, `aiLogger`, `schedulerLogger`, `apiLogger`, etc.

### 2. NEVER Double-Log -- logger.error() OR captureException(), Not Both Internally

Domain capture functions create **error tracker issues** (alerts). They do NOT log internally.
The **caller** decides whether to also log for debugging:

```typescript
// CORRECT -- log for debugging, then capture for alerting
logger.error("Order processing failed at payment gateway", {
  session_id: sessionId,
  stage: "payment_gateway",
});
void captureOrderException(error, {
  organizationId,
  stage: "payment_gateway",
});

// WRONG -- capture function already handles error tracker, don't also log inside it
// (causes 3-5x duplicate events)
```

**Why this matters:**
- `logger.error()` -> sends to structured logs + console (deployment logs)
- `captureException()` -> sends to error tracker issues (alerts, fingerprinting, grouping)
- If both are inside the capture function AND the caller also logs, you get duplicates

### 3. Use Built-in OpenTelemetry -- Never Add Conflicting OTEL Packages

If your error tracking SDK has native OTEL support, use it. Adding separate OTEL packages (e.g., `@vercel/otel`) causes span conflicts and duplicate traces.

Only add `@opentelemetry/api` (lightweight API package) for `trace.getActiveSpan()`.

### 4. Do Not Re-Add Console Interception After Removal

If you have removed console log interception from your error tracker config (because your logger sends directly), do NOT re-add it. It intercepts `console.warn/error` and re-sends them, causing duplicates with what the logger already sent.

### 5. Tags (Searchable) vs Context (Debug) vs Metrics (Charts)

```typescript
import * as Sentry from "@sentry/nextjs"; // or your error tracker SDK

// Tags: Categorical, filterable in dashboard (low cardinality)
Sentry.setTag("webhook.source", "stripe");
Sentry.setTag("ai.verdict", "approved");

// Context: Structured debugging data (NOT searchable)
Sentry.setContext("analysis_result", {
  overallScore: 65,
  verdict: "approved",
  durationMs: 4500,
});

// Metrics: Numeric data for charts and dashboards
Sentry.metrics.distribution("ai.analysis.duration_ms", 4500, {
  unit: "millisecond",
});
Sentry.metrics.count("webhook.processed", 1, {
  attributes: { provider: "stripe" },
});
```

| Concept | Searchable? | Cardinality | Use For |
|---------|-------------|-------------|---------|
| Tags | Yes | Low (enum-like) | Filtering issues/traces in dashboard |
| Context | No | Any | Debug data attached to an event |
| Metrics | Charts only | N/A | Distributions, counts, dashboards |

### 6. PII Auto-Redaction

Configure your logger to automatically redact sensitive fields: `password`, `token`, `secret`, `apikey`, `api_key`, `accesstoken`, `access_token`, `refreshtoken`, `refresh_token`, `bearer`, `authorization`, `creditcard`, `credit_card`, `cardnumber`, `card_number`, `cvv`, `ssn`, `social_security`, `name`.

**Never interpolate PII into log message strings.** Always pass PII as structured attributes where the redaction layer can catch it:

```typescript
// CORRECT -- structured attribute (auto-redacted)
logger.info("Order created", { guest_email: email });

// WRONG -- PII in unstructured string (bypasses redaction)
logger.info(`Order created for ${email}`);
```

### 7. Log Levels Per Environment

| Environment | Minimum Level | Notes |
|-------------|--------------|-------|
| Production | `info` | Only `debug` is filtered out |
| Preview/Staging | `debug` | Full verbosity |
| Development | `debug` | Full verbosity |

Use `logger.debug()` for verbose tracing you only need locally. All `info`, `warn`, and `error` logs appear in production.

### 8. Domain-Specific Error Capture

For alertable failures (error tracker issues, not just logs), use factory-generated typed capture functions:

```typescript
// Factory pattern for domain capture functions
function createDomainCapture(domain: string) {
  return (error: unknown, context: DomainContext) => {
    const normalized = normalizeError(error);
    Sentry.captureException(normalized, {
      tags: {
        [`${domain}.critical`]: "true",
        [`${domain}.stage`]: context.stage,
        [`${domain}.organization_id`]: context.organizationId,
      },
      fingerprint: [`${domain}-failure`, context.stage, context.organizationId],
    });
  };
}

// Generated capture functions per domain
const captureOrderException = createDomainCapture("order");
const capturePaymentException = createDomainCapture("payment");
const captureWebhookException = createDomainCapture("webhook");
const captureAIException = createDomainCapture("ai");
```

These functions: (1) normalize errors, (2) auto-inject request context tags, (3) set domain-prefixed tags, (4) apply custom fingerprinting. They do NOT log internally.

See `references/sentry-patterns.md` for full factory pattern, tag constants, and interfaces.

### 9. Centralized Tag & Metric Constants

All tag keys and metric names should be centralized constants -- never hardcode tag strings:

```typescript
import { ORDER_TAGS } from "@/lib/sentry/tags";
Sentry.setTag(ORDER_TAGS.STAGE, "payment_gateway");

import { METRICS } from "@/lib/sentry/metrics";
Sentry.metrics.count(METRICS.WEBHOOK.PROCESSED, 1, { ... });
```

### 10. Span Naming Conventions

| Pattern | Example | Use For |
|---------|---------|---------|
| `db.*` | `db.orders.list` | Database operations |
| `ai.*` | `ai.sentiment-analysis` | AI/ML operations |
| `http.*` | `http.external-api` | External HTTP calls |
| `function.*` | `function.process-payment` | Business logic |

---

## Error Handling Patterns

### Server Action / Repository Error

```typescript
try {
  await processPayment(paymentId);
} catch (error) {
  logger.error("Payment processing failed", { payment_id: paymentId, error });
  void capturePaymentException(error, {
    organizationId,
    stage: "payment_storage",
    paymentIntentId,
  });
  return { success: false, error: "Payment failed" };
}
```

### Webhook Error (Use Webhook Logger)

```typescript
import { createWebhookLogger } from "@/lib/webhooks/webhook-logger";

const wLogger = createWebhookLogger({
  provider: "stripe",
  eventType,
  eventId,
});
wLogger.start();
try {
  // ... handle webhook
  wLogger.success();
} catch (error) {
  wLogger.failure(error);
  // webhook logger's failure() already calls error tracker capture
}
```

See `references/webhook-logger.md` for the full webhook logger lifecycle, handler template, and `withWebhookTracing` wrapper.

### logError() Utility

```typescript
import { logError } from "@/lib/logger";
logError("Payment processing failed", error, { payment_id: paymentId });
```

---

## Custom Span Pattern

```typescript
import * as Sentry from "@sentry/nextjs";

const result = await Sentry.startSpan(
  { name: "function.process-media", op: "function" },
  async (span) => {
    const result = await processMedia(input);
    span.setAttributes({ "custom.output_size": result.length });
    return result;
  }
);
```

---

## Wide Events

Prefer fewer, attribute-rich logs over many thin logs:

```typescript
// Wide event -- one complete, searchable log
logger.info("Order completed", {
  order_id: id,
  stage: "complete",
  duration_ms: elapsed,
  organization_id: orgId,
  outcome: "confirmed",
});

// Use logger.debug() for intermediate steps (filtered in production)
```

---

## Webhook Handlers

Webhook handlers require specialized observability. Use a dedicated webhook logger factory that provides:

1. **Lifecycle methods**: `start()` -> `success()` / `failure()`
2. **Automatic duration tracking** with configurable slow-operation thresholds
3. **Early Sentry tag application** for dashboard filtering
4. **Idempotency awareness** -- webhooks are delivered multiple times

```typescript
const log = createWebhookLogger({
  provider: "stripe",
  handler: "handlePaymentSucceeded",
  eventType: "payment_intent.succeeded",
  organizationId,
  durationThresholdMs: 5000, // warn if slower
});

log.start();  // starts timer, applies tags
try {
  // 1. Idempotency check
  const existing = await findExisting(payload.id);
  if (existing) {
    log.info({}, "Already processed (idempotent skip)");
    log.success({ reason: "already_processed" });
    return { success: true };
  }

  // 2. Business logic
  const result = await processEvent(payload);

  // 3. Update tags with created entity IDs
  log.setEntityId("order_id", result.id);

  log.success({ entity_id: result.id });
} catch (error) {
  log.failure(error);  // logs error + captures to error tracker
  throw error;
}
```

Full webhook logger reference, handler template, and `withWebhookTracing` wrapper: `references/webhook-logger.md`

---

## AI Instrumentation

Use instrumented wrappers for AI agent calls with automatic spans and token tracking:

```typescript
import { instrumentedAgentGenerate } from "@/lib/ai/instrumentation";

const result = await instrumentedAgentGenerate(
  agent, messages, options,
  {
    operation: "sentiment-analysis",
    modelName: "claude-sonnet-4-5-20250929",
    organizationId,
  },
);
// Auto-emits: ai.tokens.prompt, ai.tokens.completion, ai.duration metrics
```

For non-agent AI calls, use `trackAIOperation()` for lighter-weight metrics tracking.

See `references/sentry-patterns.md` for full AI instrumentation patterns.

---

## Error Boundaries

Every route MUST have an error boundary component:

```typescript
"use client";
import { PageErrorBoundary } from "@/components/PageErrorBoundary";

export default function Error({ error, reset }: { error: Error; reset: () => void }) {
  return <PageErrorBoundary error={error} reset={reset} title="Page" loggerModule="route-name" />;
}
```

---

## Performance Thresholds

| Metric | Warning | Error |
|--------|---------|-------|
| DB Query | >1s | >5s |
| Server Action | >3s | >10s |
| API Route | >2s | >8s |
| AI Agent Call | >10s | >30s |

---

## Anti-Patterns

| Anti-Pattern | Why It's Wrong | Correct Alternative |
|-------------|---------------|-------------------|
| `console.log` / `console.error` | No structure, no redaction, no correlation | `logger.info()` / `logger.error()` |
| Direct `Sentry.captureException` | No domain tags, no fingerprinting | Domain `capture*Exception()` functions |
| Conflicting OTEL packages | Span conflicts, duplicate traces | Use SDK built-in OTEL |
| Console interception integration | Duplicates with direct logger sends | Remove it |
| `logger.error()` inside capture function | Caller handles logging separately | Only `captureException` inside |
| High-cardinality tags (order_id, user_id) | Bloats tag index, not filterable | Use context instead |
| `logger.info()` for production alerts | Info is not alertable | Use `warn` or `captureException` |
| Missing trace propagation in AI calls | Traces won't connect across services | Always pass tracing options |
| PII interpolated in log strings | Bypasses auto-redaction | Pass as structured attributes |

---

## Debugging Workflow

```
1. Search issues by keyword or tag
2. Get issue details -> check tags, context, stacktrace
3. Get trace details -> view span waterfall
4. Search structured logs by trace_id for full context
5. For background jobs -> copy run_id -> check job dashboard
6. Fix -> deploy -> verify issue resolves
```

---

## Detailed References

- Domain exception factory, tag constants, tracing, AI instrumentation: `references/sentry-patterns.md`
- Webhook logger lifecycle, handler template, withWebhookTracing: `references/webhook-logger.md`
