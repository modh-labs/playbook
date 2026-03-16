---
title: "Distributed Tracing"
subtitle: "Following a request across 6 services"
chapter: 18
section: "Observability"
seo_title: "Distributed Tracing for Next.js with OpenTelemetry and Sentry in 2026"
seo_description: "Trace a single user action from browser to server action to webhook to background job to AI agent — all connected in one waterfall."
keywords: ["distributed tracing", "opentelemetry", "sentry tracing", "trace propagation", "next.js observability", "ai agent tracing"]
reading_time: "9 min"
difficulty: "advanced"
tech_stack: ["Next.js", "Sentry", "TypeScript", "OpenTelemetry"]
business_case: "Connect disconnected logs and errors into a single trace waterfall, reducing cross-service debugging time by 90%."
---

# Distributed Tracing

> "A trace is a story. Each span is a chapter. Without the book, you are reading sentences in random order."

## The Problem

A user clicks "Place Order." That click triggers a server action, which calls a payment webhook, which spawns a background job, which invokes an AI agent to classify the order. When the AI agent fails silently and the order gets stuck, you have five separate systems to investigate — each with their own logs, their own timestamps, and no connection between them.

This is the observability gap that grows as your architecture matures. You moved from monolith to server actions, added webhooks for third-party integrations, introduced background jobs for heavy processing, and wired up AI agents for intelligent automation. Each layer has its own logging. None of them talk to each other.

The symptom is always the same: a bug takes four hours to debug because you spend three hours and fifty minutes correlating timestamps across systems, trying to reconstruct the sequence of events that led to the failure.

## The Principle

Distributed tracing solves this by threading a single trace ID through every layer of your stack. When the user clicks "Place Order," a trace is born. That trace ID follows the request through the server action, into the payment webhook, through the background job, and into the AI agent. Every operation along the way becomes a "span" — a timed segment of the trace.

The result is a waterfall view: one visualization that shows every operation, how long each took, and which one failed.

Three architectural decisions make this work in a modern Next.js stack:

**Use your observability SDK's built-in OpenTelemetry.** Sentry v10, for example, registers itself as the global OTEL tracer provider. You do not need a separate OTEL setup. Adding a second tracer (like `@vercel/otel`) will conflict with the first. One tracer provider, fully automatic.

**Propagate trace context explicitly across async boundaries.** Auto-instrumentation handles HTTP requests and database queries. But when you call an AI agent, dispatch a background job, or invoke a third-party SDK, you must pass the trace context yourself. This is a one-line call — but it is the line that most teams forget.

**Sample by business importance.** Tracing everything at 100% in production is expensive and unnecessary. Revenue-critical paths (checkout, booking, onboarding) get 100% sampling. Standard operations (server actions, database queries) get 50%. Health checks and static assets get 10%. A tiered sampling strategy gives you full visibility where it matters and cost control where it does not.

## The Pattern

### Extracting Trace Context

Build a small utility module that extracts the current trace and span IDs from the OpenTelemetry context. This is the foundation for all trace propagation.

```typescript
// lib/tracing/otel-context.ts
import { trace } from "@opentelemetry/api";

export function getCurrentTraceId(): string | undefined {
  const span = trace.getActiveSpan();
  return span?.spanContext().traceId;
}

export function getCurrentSpanId(): string | undefined {
  const span = trace.getActiveSpan();
  return span?.spanContext().spanId;
}

export function getSpanContext() {
  const span = trace.getActiveSpan();
  return span?.spanContext();
}
```

The `@opentelemetry/api` package is lightweight (~50KB). It provides the API surface without any implementation — your observability SDK provides the actual tracer.

### Propagating to AI Agents

AI agent calls are the most common place traces break. The agent runs in a separate execution context and has no way to discover the parent trace automatically. You must pass it.

```typescript
// lib/tracing/otel-context.ts (continued)
export function getTracingOptionsForAgent(): {
  traceId: string;
  parentSpanId: string;
} | undefined {
  const ctx = getSpanContext();
  if (!ctx) return undefined;
  return {
    traceId: ctx.traceId,
    parentSpanId: ctx.spanId,
  };
}
```

Then pass it to every AI agent call:

```typescript
import { getTracingOptionsForAgent } from "@/lib/tracing/otel-context";
import { runOrderClassification } from "@/lib/agents";

const result = await runOrderClassification({
  orderData: serializedOrder,
  tracingOptions: getTracingOptionsForAgent(),
});
```

The agent framework reads `tracingOptions` and creates its spans as children of the parent. The result is a connected waterfall:

```
[Transaction] api.placeOrder
  └── [Span] server-action.createOrder (320ms)
      ├── [Span] db.orders.insert (45ms)
      └── [Span] ai.order-classification (2100ms)
          └── [Span] openai.chat.completions (1850ms)
```

Without `tracingOptions`, the AI spans float as a disconnected trace. You see them in your dashboard, but you cannot connect them to the order that triggered them.

### Custom Spans for Business Operations

Auto-instrumentation covers HTTP requests and database queries. For everything else — business logic, external API calls, multi-step workflows — create custom spans.

```typescript
import * as Sentry from "@sentry/nextjs";

const result = await Sentry.startSpan(
  {
    name: "order.process-payment",
    op: "function",
    attributes: {
      "order.id": orderId,
      "order.amount": amount,
      "order.currency": currency,
    },
  },
  async (span) => {
    const paymentResult = await chargePayment(orderId, amount);

    span.setAttributes({
      "payment.provider": paymentResult.provider,
      "payment.success": paymentResult.success,
      "payment.duration_ms": paymentResult.durationMs,
    });

    return paymentResult;
  }
);
```

Follow a consistent naming convention for span names:

| Pattern | Example | Use For |
|---------|---------|---------|
| `db.*` | `db.orders.list` | Database operations |
| `ai.*` | `ai.order-classification` | AI/ML operations |
| `http.*` | `http.payment-gateway` | External HTTP calls |
| `function.*` | `function.process-refund` | Business logic |

### Tiered Sampling Strategy

Not all operations deserve the same sampling rate. Build a sampling function that categorizes operations by business impact.

```typescript
// lib/tracing/sampling.ts

const CRITICAL_PATH_PATTERNS: RegExp[] = [
  /^checkout\./, /^onboarding\./,
  /^payment\./, /^subscription\./,
  /^order\.create/, /^order\.confirm/,
  /booking\.create/, /booking\.confirm/,
];

const IMPORTANT_PATTERNS: RegExp[] = [
  /^action\./, /^server\.action/,
  /^db\.query/, /^http\.client/,
];

const LOW_VALUE_PATTERNS: RegExp[] = [
  /health/, /^\/api\/health/,
  /_next\/static/, /favicon/,
];

export function tracesSampler(context: {
  name: string;
  attributes?: Record<string, unknown>;
}): number {
  const name = context.name;

  // Force 100% for critical paths
  if (CRITICAL_PATH_PATTERNS.some((p) => p.test(name))) return 1.0;

  // Force 100% if explicitly marked critical
  if (context.attributes?.critical_path === true) return 1.0;

  const isProduction = process.env.VERCEL_ENV === "production";

  if (IMPORTANT_PATTERNS.some((p) => p.test(name))) {
    return isProduction ? 0.5 : 0.5;
  }

  if (LOW_VALUE_PATTERNS.some((p) => p.test(name))) {
    return isProduction ? 0.1 : 1.0;
  }

  // Default rates
  return isProduction ? 0.1 : 1.0;
}
```

This gives you 100% visibility on checkout and onboarding (where bugs cost revenue), moderate visibility on server actions and database queries (where patterns matter more than individual traces), and minimal visibility on health checks and static assets (where traces are rarely useful).

### Log-Trace Correlation

Every log entry automatically includes `trace_id` and `span_id` (from the structured logging layer). This creates a two-way link:

```typescript
const traceId = getCurrentTraceId();
logger.info("Order payment processed", {
  trace_id: traceId,
  order_id: orderId,
  amount: total,
});
```

**From a log, find the trace:** Copy the `trace_id` from any log entry, search it in your observability platform's performance view to see the full waterfall.

**From a trace, find the logs:** Click any span in the waterfall, then click "View Logs" to see every log emitted during that span's lifetime.

**From an error, find everything:** An error captured during a traced operation carries the trace ID. Click through to see what happened before and after the failure, across every service boundary.

### Background Job Tracing

Background jobs (via Inngest, BullMQ, or similar) need explicit trace propagation. The job runner middleware creates Sentry transactions and tags them with job metadata.

```typescript
// When the job runs, the middleware creates:
// Tags: job.function_name, job.event_name, job.run_id
// Transaction: inngest.processOrder

// Cross-reference: find the Sentry issue, copy job.run_id,
// search in your job runner dashboard for that run ID
```

This bidirectional link lets you jump from an error in Sentry to the exact job execution, see its input payload, and view its retry history.

## The Business Case

**Cross-service debugging goes from 4 hours to 10 minutes.** The waterfall view shows you exactly which span failed, how long each step took, and what context was present. No more timestamp correlation across five different logging systems.

**AI agent failures become diagnosable.** Without trace propagation, a failed AI call is an orphan error with no parent context. With it, you see the exact user action that triggered the agent, the data it received, and where in the pipeline it failed.

**Sampling saves 60-80% on observability costs.** Tiered sampling ensures you pay for full visibility only on revenue-critical paths. Health checks and static assets, which generate the most trace volume, contribute the least cost.

**Performance bottlenecks surface automatically.** When every span has timing data, you can sort by duration and immediately see which operations are slowing down your user experience — before users report it.

## Try It

Install the [Modh Playbook](https://github.com/modh-ai/playbook) to get the complete distributed tracing setup with OpenTelemetry context extraction, AI agent propagation, tiered sampling, and background job correlation pre-configured for Next.js and Sentry.
