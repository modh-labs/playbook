---
name: observability-cost-quota
description: 'Observability data (spans, traces, logs, profiles) is a METERED cost with a silent failure mode: when the quota is exhausted the provider drops that category while errors keep flowing, so a perf dashboard goes empty and nobody notices. Activates when traces/spans "stopped", a perf dashboard is empty, there''s "no recent performance data", or you''re about to raise a telemetry bill. Teaches the diagnosis (errors-live + spans-dead = quota, not outage) and the counterintuitive fix order: cut low-value emission BEFORE buying headroom.'
---

# Observability Cost & Quota

Observability vendors (Sentry, Datadog, Honeycomb, …) meter **each telemetry
category separately** — errors, transactions/spans, logs, profiles, replays.
When one category's budget is exhausted, the vendor silently `rate_limited`-drops
**all** of that category for the rest of the billing period, while the others
keep flowing. The result is a failure that looks like nothing: errors still
arrive, the app is fine, but your performance dashboard is empty and your RUM
"stopped" — and because there's no error, no alert fires.

## When This Skill Activates

- A performance/RUM dashboard is unexpectedly empty or stale.
- "Traces/spans stopped", "no recent performance data", "metrics gap".
- You're about to **raise an observability bill** or buy a bigger tier to fix slowness visibility.
- Setting up or reviewing telemetry sampling / log levels.
- A cost review of the observability line item.

## The One Question

> **"Are errors still arriving while spans / traces / logs went to zero?"**

If **yes**, it is **quota exhaustion**, not an outage or an SDK bug. Stop looking
at the code; look at the provider's usage meter.

## Decision Tree

```
Perf dashboard empty / traces "stopped"?
│
├─ Are ERRORS still being accepted in the same window?
│   ├─ NO  → real outage / SDK / DSN problem → debug the integration
│   └─ YES → category-specific drop. Pull provider usage by outcome × category:
│            accepted vs rate_limited vs filtered, per day.
│            │
│            └─ rate_limited > 0 (esp. accepted == 0)?  → QUOTA EXHAUSTED
│                 │
│                 ├─ 1. CUT emission to fit  (do this FIRST)
│                 ├─ 2. THEN add headroom (on-demand cap OR cycle reset)
│                 └─ 3. DEPLOY (sampling/log-level live in the built bundle)
```

## Core Rules

### 1. Diagnose from the usage meter, not the code
Pull **accepted vs rate_limited by category, per day**. A clean cliff to
`accepted=0`/`rate_limited>0` on a date is quota exhaustion. (Sentry:
`GET /organizations/{org}/stats_v2/?field=sum(quantity)&groupBy=outcome&category=span&interval=1d&statsPeriod=14d`.)
**Scope the query to the right project** — an unscoped/wrong-project query returns
a false "no data" and sends you down a rabbit hole.

### 2. There is no environment escape
One org = **one shared plan quota** across all environments and projects.
Staging spans are rate-limited by the same budget prod blew. This *confirms* it's
a plan-level budget problem, not a per-env config bug.

### 3. Cut emission BEFORE buying budget — order is the whole game
The expensive, low-value volume is almost always **high-frequency, low-diagnostic
transactions** (visitor-scale public flows, health checks, chatty background
jobs) — and each spawns a **tree of child spans**.

```
# WRONG — raise the budget first
on_demand_budget += $$$        # now paying full price for noise; re-blows anyway

# RIGHT — cut to fit, then top up
sample(public_high_freq_txns) = 2%   # ~16x less volume
log_to_provider_threshold = "warn"   # stop shipping info-level noise
# THEN: small on-demand cap or wait for the reset → covers the now-tiny volume
```

**Child spans inherit the root transaction's sampling decision.** You don't
sample sub-spans individually — cut the *parent* transaction's rate and the whole
subtree (HTTP client calls, framework spans, DB spans) drops with it. That's the
multiplier that makes a small sampling change collapse most of the volume.

### 4. The signal you want is a rounding error in the volume
The spans you actually act on (DB queries, page loads, slow endpoints) are
typically **<0.1%** of total span volume; visitor-tracking + framework child
spans are the bulk. So "cut volume" and "keep the useful signal" are the same
move — you're trimming noise that was crowding out signal.

### 5. Sampling/log-level changes need a DEPLOY
`tracesSampler` and log thresholds are read from the **running build**. Editing
them does nothing until deployed. Until then the old volume keeps blowing any
headroom you add.

## Implementation Pattern

```ts
// Dynamic trace sampler — bucket by value, not a flat rate.
function tracesSampler(ctx) {
  const { name, op, environment } = read(ctx)
  if (isCriticalPath(name, op)) return 1.0            // revenue/booking/checkout
  if (isHighFreqLowValue(name)) return env === "prod" ? 0.02 : 0.1  // visitor/public flow + Zapier-style fanout
  if (isPageloadOrNavigation(op)) return env === "prod" ? 0.5 : 1.0 // RUM web-vitals: tiny volume, high value
  return env === "prod" ? 0.1 : 1.0                   // conservative default
}

// Log forwarding: keep verbose logs in stdout/host logs, ship only warn+ to the
// metered provider in prod.
const MIN_PROVIDER_LOG_LEVEL = isProd ? "warn" : "debug"  // NOT "info" — info is the flood
```

## Anti-Patterns

- **Buy first, cut later** — pays for noise and re-exhausts.
- **Treating an empty perf board as "no traffic" or "broken SDK"** — check the meter first.
- **Flat high sampling on visitor-scale routes** — one chatty public endpoint + its child spans can be most of your bill.
- **Shipping `info` logs to the metered log product** — info is high-volume, low-signal; warn+ is the alertable tier.
- **No usage alert** — without an on-demand cap + ~80% alert, the category dies silently and you find out via an empty dashboard weeks later.

## Audit Checklist

- [ ] Usage pulled by **outcome × category, per day**; any `rate_limited > 0`?
- [ ] Critical paths at 100%, high-frequency/public flows sampled low (≤5%), pageloads modest-but-present.
- [ ] Child-span multiplier understood (parent rate governs the tree).
- [ ] Provider log threshold = `warn+` in prod (not `info`).
- [ ] On-demand **cap + usage alert (~80%)** configured (no silent death).
- [ ] A recurring digest watches the `rate_limited` canary.
- [ ] Sampling/log changes scheduled with a **deploy** (they're build-time).
