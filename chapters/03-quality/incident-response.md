---
title: "Incident Response"
subtitle: "When things break: our runbook"
chapter: 9
section: "Quality"
seo_title: "Incident Response for SaaS Teams — Severity Levels, Runbook, Post-Mortems — 2026"
seo_description: "A practical incident response framework: severity levels, step-by-step investigation, post-mortem templates, and common failure modes for SaaS applications."
keywords: ["incident response", "runbook", "post-mortem", "SaaS operations", "severity levels", "production debugging"]
reading_time: "9 min"
difficulty: "intermediate"
tech_stack: ["Next.js", "Supabase", "TypeScript", "Sentry"]
business_case: "Structured incident response turns a 4-hour panic into a 30-minute resolution. The difference is not luck — it is preparation."
---

# Incident Response

> "The quality of your response to a production incident is decided weeks before the incident happens."

## The Problem

It is 2 AM. Your payment webhook is silently dropping events. Customers are completing checkouts but their orders never appear. Support tickets are accumulating. Someone notices. They ping the team.

What happens next separates mature engineering organizations from chaotic ones.

Without a runbook, the response is ad hoc. Someone SSH-es into something. Someone else checks a dashboard. A third person starts reading code. Nobody knows who is driving. Nobody knows what has already been investigated. The same dead ends get explored twice. The actual root cause -- a rotated webhook secret that was not updated in production -- takes three hours to find when it should have taken ten minutes.

The cost is not just the downtime. It is the shattered confidence. The team starts fearing deployments. They slow down. They add manual checks. They stop shipping on Fridays. The incident creates a cultural debt that compounds for months.

## The Principle

Incident response is not heroism. It is a process. And like all processes, it works when it is practiced before it is needed.

We organize incidents around three ideas:

**Severity determines urgency, not emotion.** A broken export button and a broken payment webhook both feel urgent when a customer reports them. But they carry fundamentally different business risk. Severity levels force you to triage by impact, not by who shouted loudest.

**Response follows a script.** Acknowledge, assess, communicate, investigate, mitigate, verify, document. Every incident, every time. The script prevents the two most common failure modes: jumping to a fix before understanding the problem, and forgetting to communicate while you are deep in debugging.

**Post-mortems prevent recurrence, not assign blame.** The goal of a post-mortem is a system change that makes the class of failure impossible, not a name attached to the commit that caused it.

## The Pattern

### Severity Levels

| Level | Definition | Response Time | Example |
|-------|------------|---------------|---------|
| **P0 Critical** | Active data breach or system compromise | Immediate (< 1 hour) | Unauthorized data access, leaked credentials |
| **P1 High** | Service down, payment failures, data loss | < 4 hours | Payment processing broken, authentication outage |
| **P2 Medium** | Major feature broken, degraded performance | < 24 hours | Search not returning results, slow page loads |
| **P3 Low** | Minor feature broken, cosmetic issues | Next sprint | Export formatting issue, UI alignment bug |

The boundary between P1 and P2 is revenue. If the incident is actively losing money or actively exposing data, it is P1 or above. Everything else can wait for business hours.

### The Response Script

Every incident follows seven steps. No exceptions, no shortcuts.

**1. Acknowledge.** Respond in your team channel within the SLA. This is not about having a fix. It is about signaling that someone is on it.

**2. Assess.** Determine severity and blast radius. How many users are affected? Is data integrity at risk? Is revenue impacted?

**3. Communicate.** For P0/P1, notify stakeholders immediately. For P2, post a status update. Silence during an incident is worse than bad news.

**4. Investigate.** Follow the investigation playbook for the affected system. Check error tracking, check logs, check the external service status page.

**5. Mitigate.** Apply a fix or a workaround. A workaround that restores service in 5 minutes is better than a perfect fix that takes 2 hours.

**6. Verify.** Confirm the fix works. Check that error rates returned to baseline. Verify with the reporter if possible.

**7. Document.** Update the runbook. Create follow-up tickets. Schedule a post-mortem for P0/P1.

### Investigation Playbooks

The power of a runbook is in the specifics. Here are the common failure modes for a modern SaaS stack.

**Payment Processing Failures:**

```
Symptoms:
  - Webhook errors in error tracking
  - Customers report payments not going through
  - Orders not appearing after checkout

Investigation:
  1. Check payment provider status page
  2. Check webhook delivery logs in provider dashboard
  3. Search error tracking: "domain:payment is:unresolved"
  4. Verify webhook secret matches environment variable

Common causes:
  - Provider outage → wait for recovery
  - Webhook secret rotated → update environment variable
  - Database connection pool exhausted → increase pool size
```

**Database Connection Issues:**

```
Symptoms:
  - Multiple features returning errors simultaneously
  - "Connection refused" or timeout errors in error tracking
  - Health check endpoint returning 503

Investigation:
  1. Check database provider status page
  2. Check connection pool usage in database dashboard
  3. Look for slow query logs
  4. Verify user JWT claims are valid

Common causes:
  - Connection pool exhausted → increase pool size
  - Provider outage → wait for recovery, check status page
  - Runaway query holding connections → identify and kill
```

**Authentication Failures:**

```
Symptoms:
  - Users cannot sign in
  - "Unauthorized" errors spike across multiple endpoints
  - Auth webhook delivery failures

Investigation:
  1. Check auth provider status page
  2. Search error tracking: "domain:auth is:unresolved"
  3. Check auth webhook logs in provider dashboard
  4. Verify signing keys and secrets

Common causes:
  - Auth provider outage → wait for recovery
  - Webhook secret mismatch → update environment variable
  - JWT configuration change → verify provider settings
```

**External Service Degradation:**

When a third-party API degrades, the response depends on whether you have circuit breakers in place.

```typescript
// Circuit breaker protects your app from cascading failures
// If the breaker is open, the service is degraded but stable

// Investigation:
// 1. Check error tracking for "Circuit breaker OPENED"
// 2. Check the affected service's status page
// 3. Wait for auto-recovery (breakers typically close after 30-60s)

// Manual reset if needed:
import { resetCircuitBreaker } from "@/lib/circuit-breaker";
await resetCircuitBreaker("payment-provider");
```

**Deployment Failures:**

```
Symptoms:
  - New deploy not live
  - Build errors in deployment platform
  - CI checks failing

Investigation:
  1. Check deployment platform build logs
  2. Run locally: bun typecheck && bun test:ci
  3. Check for missing environment variables
  4. Check for dependency conflicts

Rollback:
  - Promote the last working deployment in your platform dashboard
  - Do NOT rush a forward fix under pressure — rollback first, then fix
```

### Post-Mortem Template

For P0 and P1 incidents, we write a post-mortem within 48 hours. The template is non-negotiable.

```markdown
## Incident: [Title]

**Date:** YYYY-MM-DD
**Duration:** X hours
**Severity:** P0/P1
**Impact:** [Number of affected users, revenue impact, data impact]

### Timeline
- HH:MM — Alert received / incident detected
- HH:MM — Investigation started by [who]
- HH:MM — Root cause identified
- HH:MM — Fix deployed
- HH:MM — Verified resolved, stakeholders notified

### Root Cause
[One paragraph. What broke and why.]

### Resolution
[What was done to fix it. Include the specific change.]

### What Went Well
- [Things that worked in the response]

### What Could Be Improved
- [Gaps in monitoring, communication, tooling]

### Action Items
- [ ] [Preventive measure with owner and deadline]
- [ ] [Monitoring improvement with owner and deadline]
- [ ] [Runbook update with owner and deadline]
```

The "What Went Well" section is not optional. It reinforces behaviors you want to repeat.

### Communication Matrix

| Audience | When | Channel |
|----------|------|---------|
| Engineering team | Immediately on detection | Team chat |
| Leadership | P0/P1 within 1 hour | Direct message + email |
| Affected customers | After containment, if data was exposed | Email |
| Legal/compliance | P0 within 24 hours | Email |

The most common communication failure is not communicating bad news. It is not communicating _progress_. A message that says "still investigating, no new findings, next update in 30 minutes" is more valuable than silence.

### Post-Incident Checklist

After every incident:

- [ ] Incident resolved and verified
- [ ] Stakeholders notified of resolution
- [ ] Root cause identified
- [ ] Post-mortem written (P0/P1)
- [ ] Runbook updated if this was a new failure mode
- [ ] Preventive measures documented as tickets
- [ ] Monitoring updated to detect this class of failure earlier

## The Business Case

**Reduced downtime.** Teams with structured incident response resolve P1 incidents 3-5x faster than teams without one. The difference is not skill. It is knowing where to look first.

**Customer trust.** Customers forgive outages. They do not forgive silence. A team that communicates proactively during an incident builds more trust than a team that never has incidents but goes dark when they do.

**Engineering velocity.** Post-mortems that produce systemic fixes reduce repeat incidents. Teams that run post-mortems consistently see incident rates drop 30-40% year over year. That is engineering time reclaimed for building, not firefighting.

**Hiring and retention.** Engineers want to work on teams that handle incidents calmly and learn from them. The alternative -- a culture of blame, panic, and ad hoc responses -- drives people out.

The investment is small: a severity table, a response script, a post-mortem template, and a commitment to updating the runbook after every new failure mode. The return is measured in hours of sleep recovered and customers retained.

## Try It

```bash
npx modh-playbook init incident-response
```
