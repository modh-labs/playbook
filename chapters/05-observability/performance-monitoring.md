---
title: "Performance Monitoring"
subtitle: "Measuring what matters"
chapter: 19
section: "Observability"
seo_title: "Performance Monitoring for Next.js — Web Vitals, Custom Metrics, and Alerting in 2026"
seo_description: "Set performance thresholds per operation type, track Web Vitals, and alert on regressions before users notice them."
keywords: ["performance monitoring", "web vitals", "custom metrics", "sentry performance", "next.js performance", "alerting thresholds"]
reading_time: "7 min"
difficulty: "intermediate"
tech_stack: ["Next.js", "Sentry", "TypeScript", "Vercel"]
business_case: "Catch performance regressions within minutes of deployment instead of discovering them from user complaints weeks later."
---

# Performance Monitoring

> "If you cannot measure it, you cannot improve it. If you do not alert on it, you will not notice it degraded."

## The Problem

Your application is fast. You know this because it was fast when you shipped it. But three months and forty deployments later, a database query that used to take 200ms now takes 3 seconds. A server action that was snappy at launch now blocks for 8 seconds on large datasets. The AI analysis pipeline that averaged 5 seconds now regularly exceeds 30.

Nobody noticed because nobody was watching.

Performance degrades gradually. Each deployment adds a small amount of latency — an extra join here, a missing index there, an N+1 query that only manifests with real data volumes. By the time a user complains, the regression has been compounding for weeks, and the offending commit is buried under dozens of subsequent changes.

The second failure mode is worse: alert fatigue. Teams that do monitor performance often configure alerts that fire on every slow request. Slow database queries generate warnings that flood the error feed. Engineers stop reading alerts because most of them are noise. When a real regression lands, the alert is lost in the pile.

## The Principle

Performance monitoring works when it measures the right things at the right granularity with the right severity.

**Operation-specific thresholds.** A database query and an AI agent call have fundamentally different performance profiles. A 3-second database query is a warning. A 3-second AI call is perfectly normal. Thresholds must be calibrated per operation type, or they produce garbage alerts.

**Warnings, not errors.** Slow operations are performance observations, not application failures. Reporting them as errors pollutes the error feed and trains engineers to ignore Sentry. Report them as warnings — visible in the performance dashboard without drowning real bugs.

**Web Vitals as the north star.** Server-side metrics tell you how your infrastructure is performing. Web Vitals tell you how your users experience the application. Both matter, but user experience is the ultimate measure. A server that responds in 100ms means nothing if the page takes 4 seconds to become interactive.

## The Pattern

### Operation-Specific Thresholds

Define warning and critical thresholds for each category of operation. These numbers come from real-world observation, not theory.

| Operation | Warning | Critical | Sentry Level |
|-----------|---------|----------|--------------|
| Database Query | >3s | >10s | `warning` |
| Server Action | >5s | >20s | `warning` |
| External API Call | >5s | >15s | `warning` |
| API Route | >2s | >8s | `warning` |
| AI Agent Call | >10s | >30s | `warning` |
| Media Processing | >60s | >180s | `warning` |

Every threshold emits at `level: "warning"`, not `level: "error"`. This is a deliberate design decision. Slow operations belong in the performance feed, not the error feed.

```typescript
// lib/performance/thresholds.ts

interface PerformanceThreshold {
  warning: number;  // milliseconds
  critical: number; // milliseconds
}

const THRESHOLDS: Record<string, PerformanceThreshold> = {
  "db.query": { warning: 3000, critical: 10000 },
  "server.action": { warning: 5000, critical: 20000 },
  "http.external": { warning: 5000, critical: 15000 },
  "api.route": { warning: 2000, critical: 8000 },
  "ai.agent": { warning: 10000, critical: 30000 },
  "media.process": { warning: 60000, critical: 180000 },
};

export function checkPerformance(
  operation: string,
  durationMs: number
): "ok" | "warning" | "critical" {
  const threshold = THRESHOLDS[operation];
  if (!threshold) return "ok";
  if (durationMs >= threshold.critical) return "critical";
  if (durationMs >= threshold.warning) return "warning";
  return "ok";
}
```

### Custom Metrics

Use your observability platform's metrics API to track numeric values you want to aggregate and chart over time. Metrics are distinct from logs — they are designed for histograms, percentiles, and trend analysis.

```typescript
import * as Sentry from "@sentry/nextjs";

// Distribution: Track ranges (scores, durations, sizes)
Sentry.metrics.distribution("order.processing_duration_ms", elapsed, {
  unit: "millisecond",
  attributes: { status: "success", payment_method: method },
});

// Count: Track occurrences
Sentry.metrics.count("order.completed", 1, {
  attributes: { plan: "pro", source: "web" },
});

// Gauge: Track current values
Sentry.metrics.gauge("queue.depth", currentDepth, {
  attributes: { queue: "order-processing" },
});
```

The rule of thumb: if you want to filter and search, use **tags**. If you want to chart and aggregate, use **metrics**. If you want to debug a specific incident, use **context**.

| Use Case | Primitive | Example |
|----------|-----------|---------|
| Filter issues by category | `setTag()` | `order.status:failed` |
| Chart numeric distributions | `metrics.distribution()` | Processing time histograms |
| Count occurrences | `metrics.count()` | Success/failure rates |
| Debug data (not searchable) | `setContext()` | Full order payload |

### Web Vitals Targets

Define target metrics for every route in your application. These are the numbers your users actually experience.

| Metric | Target | What It Measures |
|--------|--------|-----------------|
| First Contentful Paint (FCP) | <1s | Time until skeleton/structure is visible |
| Largest Contentful Paint (LCP) | <2.5s | Time until main content is loaded |
| Time to Interactive (TTI) | <3s | Time until page responds to input |
| Cumulative Layout Shift (CLS) | <0.1 | Visual stability (no unexpected movement) |

Track these via your analytics platform (Vercel Analytics, Sentry Performance, or similar). Set up dashboards that show trends over time, grouped by route, so you can spot regressions the day they deploy.

### Alerting Configuration

Configure alerts at three levels:

**Error rate alerts** fire when the percentage of failed requests exceeds a threshold. This catches application bugs, not performance regressions.

```yaml
# Error rate alert
Condition: Error rate > 1% over 5 minutes
Action: Slack notification to #engineering-alerts
```

**Latency alerts** fire when the P95 response time exceeds the warning threshold for a specific operation type. This catches performance regressions.

```yaml
# Latency alert
Condition: P95 latency > 5s for server actions over 10 minutes
Action: Slack notification to #performance-alerts
```

**Business metric alerts** fire when domain-specific failure rates spike. This catches problems that affect revenue.

```yaml
# Business metric alert
Condition: AI analysis failure rate > 5% over 15 minutes
Action: Slack notification to #ops-alerts
```

### Release Tracking

Link every deployment to its performance impact. When you tag releases with the git commit SHA, your observability platform can show:

- **Issues introduced:** New errors that appeared for the first time in this release
- **Issues resolved:** Errors that stopped occurring after this release
- **Issues regressed:** Previously resolved errors that reappeared
- **Performance delta:** How P50/P95 latency changed compared to the previous release

```typescript
// sentry.server.config.ts
Sentry.init({
  release: process.env.VERCEL_GIT_COMMIT_SHA || "local-dev",
  dist: process.env.VERCEL_GIT_COMMIT_REF || "local",
});
```

After each deploy, check the release dashboard. If P95 latency increased, you know exactly which commit to investigate.

### Error Filtering for Signal Quality

Not every error is actionable. Network timeouts, browser extension interference, and framework noise generate events that obscure real problems. Filter them aggressively.

```typescript
// Pattern-based filtering (fast, applied before processing)
ignoreErrors: [
  "ECONNRESET", "EPIPE", "ETIMEDOUT",
  /^NEXT_/,  // Next.js framework errors
],

// Surgical event filtering (full event inspection)
beforeSend(event) {
  const message = event.exception?.values?.[0]?.value || "";
  // Duplicate key races are retried automatically
  if (message.includes("duplicate key value violates unique constraint")) {
    return null;
  }
  return event;
}
```

But never filter real application bugs, payment failures, or auth errors. If an error has a clear fix path, it belongs in your error feed.

## The Business Case

**Performance regressions are caught on deploy day.** Release tracking shows the latency delta for every deployment. A 2x regression in database query time is visible within minutes, not weeks.

**Alert fatigue drops by 90%.** Separating performance warnings from errors means engineers see real bugs in the error feed and performance trends in the performance feed. Neither drowns the other.

**Web Vitals become a shipping gate.** When every route has a target FCP, LCP, and CLS, teams can measure whether a change makes the user experience better or worse before it reaches production.

**Revenue impact becomes measurable.** When checkout and onboarding are sampled at 100% with business metric alerts, you know within 15 minutes if a deployment broke the payment flow — not when a customer emails support.

## Try It

Install the [Modh Playbook](https://github.com/modh-ai/playbook) to get the complete performance monitoring setup with operation-specific thresholds, Web Vitals tracking, release correlation, and tiered alerting pre-configured for Next.js and Sentry.
