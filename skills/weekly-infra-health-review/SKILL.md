---
name: weekly-infra-health-review
description: 'Stand up a recurring agent that READS your infra telemetry, DIFFS it against last week, and posts a short week-over-week digest ending in 1-3 prioritized "areas of improvement". A dashboard shows numbers but never says what CHANGED or what to DO — an interpreted weekly digest (signals -> recommended actions) is the difference between "we collect telemetry" and "we understand our system". Use when telemetry exists but nobody reads it, when "is our infra healthy?" has no one-glance answer, when costs/perf drift unnoticed until they break, or when standing up a scheduled health/cost review for any stack (Postgres advisors, connection capacity, telemetry quotas, deploy/config drift, web vitals, tracked-ticket movement).

'
---

# Weekly Infra Health Review

## The Core Principle

> **A dashboard shows numbers; it never says what CHANGED or what to DO.** The
> actual ask is never "collect telemetry" — it's "understand our system and tell
> me what to improve." That requires a reader who diffs this week against last
> week and recommends actions. A recurring interpretive digest is that reader.

You already have the data: Postgres advisors, connection stats, telemetry-quota
counters, deploy config, web vitals, ticket boards. The problem is nobody opens
five dashboards every Monday, mentally diffs each against memory, and decides
what to do. So drift is discovered *after* it breaks: the telemetry budget
silently exhausts and spans go dark; 118 indexes accrete with zero scans; a
function region quietly diverges from the database region.

The fix is a **fixed checklist, run on a cadence, that diffs against last
week's posted digest and ends in 1-3 prioritized actions.** Numbers are the
input; *areas of improvement* are the output.

## When This Skill Activates

- Telemetry exists across several tools but nobody reads it on a cadence.
- "Is our infrastructure healthy?" has no single one-glance answer.
- Cost or performance drifts unnoticed until an incident (quota exhaustion,
  connection ceiling hit, a slow route shipped).
- You're standing up a scheduled health/cost review for any stack.
- A leader asks for "areas of improvement," not another dashboard.

## The One Question

> **"If our infra got 20% worse this week, who or what would notice on Monday —
> and would they be told what to DO about it, or just shown a number?"**

If the honest answer is "a dashboard would show a higher number that nobody is
looking at," you need an interpreted digest, not another chart.

## Decision Tree

```
You want to know your infra is healthy / improving.
│
├─ Is there a recurring reader that DIFFS week-over-week and recommends actions?
│   │
│   ├─ NO → build this digest. A dashboard alone does not answer "what changed /
│   │        what to do". (this skill)
│   │
│   └─ YES → does it end in 1-3 prioritized, concrete actions (not just numbers)?
│           ├─ NO  → it's a status report, not a health review. Add the
│           │        "areas of improvement" tail; that's the whole point.
│           └─ YES → is the checklist in a SHARED runbook both the agent and
│                    humans run? If not, it will rot. Externalize it.
│
└─ Is this about detecting a job's NON-execution (did the cron run at all)?
    → that's a heartbeat monitor, NOT this. See `cron-monitor-checkin`.
```

## Core Rules

### 1. Report DELTAS + a recommended action, never bare absolutes

A number with no baseline and no action is noise. Every line is "this week vs
last week, and here's what to do about it." If nothing moved, say so in one line.

```
# CORRECT — delta + interpretation + action
Telemetry: spans accepted 0 days rate-limited (was 3 days last wk). ✅ quota healthy.
DB advisors: unused_index 118 (▲ from 110). → prune the 8 new zero-scan indexes (ticket).
```

```
# WRONG — a dashboard screenshot in text. What changed? What do I do?
spans: 4.1M. logs: 900k. unused_index: 118. max_connections: 90. LCP p75: 2.4s.
```

### 2. Interpret signals into causes — that's the value a dashboard can't add

The agent's edge is connecting two readings into a diagnosis a chart never
states. Real examples this pattern surfaced:

- **errors-live-but-spans-dead** → the telemetry *budget* is exhausted; spans
  are being dropped while error events still flow. A spans dashboard just looks
  empty; the digest says *why* and *what to do* (see `observability-cost-quota`
  for the diagnosis + fix when this canary trips).
- **118 indexes with scan count 0** → write-amplification and storage waste;
  prune them. The advisor lists them every week; the digest is what finally
  *acts* on the trend.

### 3. End with 1-3 PRIORITIZED areas of improvement, lead with red

The digest's last line is the deliverable. Cap it at three so it stays
actionable; order by impact; put anything red at the top of the whole digest so
a 10-second scan catches it.

### 4. The checklist lives in a SHARED runbook, not in the agent prompt

Write the checks once in a doc both the scheduled agent AND a human can run.
The agent prompt says "follow this runbook verbatim." This keeps it
maintainable (one place to add a check), auditable (humans can reproduce), and
survivable (the agent config isn't the only copy).

### 5. Cover the drift classes that bite silently

A useful infra checklist spans, at minimum, these four drift classes — plus
tracked-ticket movement as the tie-back to the work:

- **Database health & capacity** — advisor lints (missing/unused indexes,
  per-row RLS, unindexed FKs, security), plus **connection headroom vs the tier
  ceiling** (spikes, not steady-state, are the concern).
- **Telemetry-quota canary** — is any category (spans/logs/traces) being
  *rate-limited / dropped*? The day this flips, you lose observability silently.
- **Deploy/config drift vs documented posture** — does live config still match
  the posture you wrote down (function region co-located with the DB, compute
  mode, timeouts)? Note deploy frequency — a long gap means shipped work isn't
  live.
- **Field performance** — p75 of your real-user vitals (TTFB/LCP/INP) on the
  worst routes vs recorded targets, movement vs last week.
- **Tracked-ticket movement** — tie the metrics to the work (done / in-progress
  / newly-filed) so the digest connects signal to action.

### 6. Fresh session per run, headless-capable auth

Run as a fresh-session scheduled trigger (no carried context to bias the diff;
last week's truth comes from the posted digest, not chat memory). Use
token-backed access for every source so it runs unattended — and note which
tool needs which token in the runbook.

### 7. Separate the INFRA review from the ENGINEERING-output review

A git+tickets "what did we ship" report answers a different question than "is
the infra healthy and cheap." Keep them as two digests; don't fold infra health
into the velocity report or it gets lost.

## Anti-Patterns

- **A dashboard counts as "done".** It shows the number; it never says what
  changed or what to do. The interpretation is the whole job.
- **Posting absolutes with no week-over-week baseline.** Without "vs last week"
  there is no signal — only a wall of figures nobody acts on.
- **No action tail.** A health review that ends in numbers is a status report.
  The 1-3 prioritized "areas of improvement" ARE the deliverable.
- **Checklist embedded only in the agent prompt.** It rots, can't be reproduced
  by a human, and dies with the trigger. Put it in a shared runbook.
- **Carrying chat context across runs to "remember" last week.** Last week's
  baseline must be the durable posted digest, not session memory — otherwise the
  diff is unreproducible and drifts.
- **Confusing this with a heartbeat monitor.** This interprets telemetry that
  exists; a heartbeat detects a job that didn't run. Different tools, different
  failure modes (see `cron-monitor-checkin`).

## Related Skills

- `observability-cost-quota` — when the telemetry-quota canary (Rule 5) trips,
  this is the diagnosis + fix (cut emission before buying budget).
- `cron-monitor-checkin` — the complement: detects a scheduled job that did NOT
  run. This skill assumes the job runs and interprets what it reads.

## Audit Checklist

- [ ] Does a recurring trigger run a fixed checklist on a cadence (e.g. weekly)?
- [ ] Is the checklist in a SHARED runbook doc, referenced verbatim by the agent?
- [ ] Does every line report a week-over-week DELTA, not a bare absolute?
- [ ] Does the agent INTERPRET (signal → cause), not just transcribe numbers?
- [ ] Does the digest END in 1-3 prioritized, concrete areas of improvement?
- [ ] Is anything red surfaced at the top for a 10-second scan?
- [ ] Are the four drift classes covered: DB health+capacity, telemetry-quota
      canary, config-drift-vs-posture, field perf — plus ticket movement?
- [ ] Is the baseline the prior POSTED digest (durable), not session memory?
- [ ] Is auth token-backed so the run is fully headless/unattended?
- [ ] Is infra health a SEPARATE digest from the engineering-output report?
