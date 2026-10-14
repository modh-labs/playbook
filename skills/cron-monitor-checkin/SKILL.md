---
name: cron-monitor-checkin
description: 'A cron monitor is only as real as the check-ins that feed it. Vercel''s Sentry integration auto-registers a monitor per cron that EXPECTS check-ins; if the route never calls captureCheckIn, the monitor reports "missed check-in" on every tick forever — a permanent phantom outage that trains your team to ignore alerts. Use when adding/auditing any scheduled job (Vercel cron, GitHub Action schedule, k8s CronJob) wired to a heartbeat monitor (Sentry Crons, Cronitor, Healthchecks.io, Better Stack).

'
---

# Cron Monitor Check-Ins

## The Core Principle

> **A monitor is only as real as the producer feeding it.** A heartbeat monitor
> with no producer doesn't fail safe — it cries wolf on every interval until
> your team mutes it, and then it can't warn you about the real outage either.

Heartbeat / "dead man's switch" monitors (Sentry Crons, Cronitor,
Healthchecks.io, Better Stack Heartbeats) work by *expecting a check-in* on a
schedule. The monitor is the **consumer**. Your job's code is the **producer**.
If you register the consumer but never wire the producer, the monitor is
**orphaned**: it reports `missed check-in` forever.

This is insidious because the monitor *looks* like it's doing its job — it's
red, it's firing, it has a slug that matches a real cron. But it's pure noise.
Worse than no monitoring, because it manufactures alert fatigue.

## When This Skill Activates

- Adding a new scheduled job (Vercel cron, GitHub Actions `schedule`, k8s
  CronJob, Inngest/Trigger.dev cron) that is or will be monitored.
- A heartbeat monitor is firing `missed check-in` / `monitor_check_in_failure`
  and you can't find where the code checks in.
- Auditing existing crons for "is this monitor real or orphaned?"
- A platform integration auto-creates monitors (Vercel↔Sentry does this from
  your cron config) and you're surprised by red monitors you never wired.

## Decision Tree

```
A heartbeat monitor exists for a scheduled job.
│
├─ Does the job's code send a check-in (captureCheckIn / ping URL)?
│   │
│   ├─ NO → the monitor is ORPHANED. Pick one:
│   │       ├─ Keep the monitoring → wire the producer (this skill).
│   │       └─ Don't want it → DELETE the monitor (don't just mute the issue;
│   │                          it regenerates on the next missed interval).
│   │
│   └─ YES → does the check-in slug EXACTLY match the monitor's slug?
│           ├─ NO  → you're feeding a DIFFERENT monitor; the original is still
│           │        orphaned and a duplicate now exists. Fix the slug.
│           └─ YES → does it report ok/error correctly (not always ok)? → audit.
```

## The One Question

> **"If this job silently stopped running tonight, what code would notice — and
> would the thing that notices itself stop running?"**

A breadcrumb, a log line, or a span is NOT a check-in — it only surfaces
attached to some other event, so it can't detect *absence*. Only a real
check-in (or an external ping) detects "the job didn't run."

## Core Rules

### 1. Every monitored cron sends a check-in lifecycle

Open `in_progress` when work starts, close `ok`/`error` when it ends.

```ts
// CORRECT — full lifecycle
const checkInId = Sentry.captureCheckIn(
  { monitorSlug: "apicronpayment-sync", status: "in_progress" },
  // monitorConfig upserts the schedule so the monitor is CODE-OWNED,
  // not an orphaned auto-registration.
  { schedule: { type: "crontab", value: "0 7 * * *" }, maxRuntime: 5, checkinMargin: 10 },
);
try {
  const result = await doWork();
  Sentry.captureCheckIn({ checkInId, monitorSlug: "apicronpayment-sync", status: "ok" });
} catch (err) {
  Sentry.captureCheckIn({ checkInId, monitorSlug: "apicronpayment-sync", status: "error" });
  throw err;
}
```

```ts
// WRONG — a breadcrumb is not a check-in. The monitor never hears from you.
Sentry.addBreadcrumb({ category: "cron", message: "ran" }); // monitor still "missed"
```

### 2. The slug MUST match the monitor's slug exactly

Auto-registered monitors derive their slug from the job. Vercel→Sentry strips
the slashes from the route path: `/api/cron/payment-sync` →
`apicronpayment-sync`. A typo or rename **spawns a second monitor** and leaves
the original screaming. Pin the slug in a constant; never compute it ad hoc.

### 3. Unauthorized hits do NOT check in

Scheduled-job endpoints are usually public URLs guarded by a shared secret.
A probe with no/wrong secret is **not a run** — returning 401 must happen
*before* any check-in, or random internet traffic registers as job executions.

### 4. Report `error` on failure, not just on exceptions

If the job catches its own failure and returns a non-2xx (common: "log it and
return 500"), that path must still check in `error`. Keying purely off thrown
exceptions marks a self-handled failure as `ok`.

### 5. `error` means "the job failed," not "a sub-item failed"

For batch jobs (loop over N tenants), one tenant failing usually shouldn't flip
the whole monitor red — that's what per-item `captureException` is for. The
monitor answers "did the scheduled run complete," not "was every item perfect."
Decide deliberately and document which you mean.

## Implementation Pattern: one wrapper, every cron

Don't hand-roll the lifecycle in each route — centralize it so the producer
*cannot* be forgotten:

```ts
export function withCronMonitor(
  opts: { monitorSlug: string; schedule: string; maxRuntime?: number; checkinMargin?: number },
  handler: (request: Request) => Promise<Response>,
) {
  return async (request: Request) => {
    if (request.headers.get("authorization") !== `Bearer ${process.env.CRON_SECRET}`) {
      return new Response("Unauthorized", { status: 401 }); // no check-in
    }
    const checkInId = Sentry.captureCheckIn(
      { monitorSlug: opts.monitorSlug, status: "in_progress" },
      { schedule: { type: "crontab", value: opts.schedule },
        maxRuntime: opts.maxRuntime ?? 10, checkinMargin: opts.checkinMargin ?? 10,
        timezone: "Etc/UTC" },
    );
    try {
      const res = await handler(request);
      Sentry.captureCheckIn({ checkInId, monitorSlug: opts.monitorSlug, status: res.ok ? "ok" : "error" });
      return res;
    } catch (err) {
      Sentry.captureCheckIn({ checkInId, monitorSlug: opts.monitorSlug, status: "error" });
      throw err;
    }
  };
}

// usage — the lifecycle is now structurally impossible to omit
export const GET = withCronMonitor(
  { monitorSlug: "apicronpayment-sync", schedule: "0 7 * * *", maxRuntime: 5 },
  async () => { /* job */ return Response.json({ ok: true }); },
);
```

## Anti-Patterns

- **Muting/resolving the Sentry issue instead of fixing the producer.** A
  `monitor_check_in_failure` issue regenerates on the next missed interval. You
  must either feed the monitor or delete the monitor — resolving the *issue* is
  a no-op that hides nothing for more than one tick.
- **Relying on a breadcrumb/log "absence alert."** Breadcrumbs don't stand
  alone; you can't alert on their absence. Only check-ins (or external pings)
  detect non-execution.
- **Deleting the cron to silence the monitor.** If the monitor is orphaned but
  the job is valuable, you've now removed a working job to kill a false alarm.
  Delete the *monitor*, keep the job (or wire it).
- **Per-route inline check-ins with copy-pasted slugs.** Drift guaranteed.
  One wrapper, slug pinned per route.

## Audit Checklist

- [ ] List every scheduled job (cron config, Actions schedules, CronJobs).
- [ ] List every heartbeat monitor (Sentry Crons UI, Cronitor, etc.).
- [ ] Diff the two lists. **Monitors with no producer = orphaned → wire or delete.**
- [ ] For each producer: slug matches monitor slug exactly?
- [ ] For each producer: opens `in_progress`, closes `ok` AND `error`?
- [ ] Failure-by-return-code path checks in `error` (not just thrown path)?
- [ ] Unauthorized requests return before any check-in?
- [ ] Jobs with no monitor at all: do they deserve one? (Silent non-execution of
      a billing/sync job is usually worth a heartbeat.)
```
