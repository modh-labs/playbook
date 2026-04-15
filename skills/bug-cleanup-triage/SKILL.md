---
name: bug-cleanup-triage
description: >
  Framework for backlog bug cleanup sessions. Triage is three sequential activities — Linear hygiene, root-cause investigation, and code fixing — that must be executed in order as a hard phase gate. Includes git log pre-flight, Sentry module-tag verification, and umbrella breakdown auto-detection. Use when planning to clean up N bugs from a backlog, before dispatching research agents, or when a ticket has been In Progress for weeks without shipping.
---

# Bug Cleanup Triage

## The Core Principle

Bug cleanup is three distinct activities that get conflated and lose efficiency when mixed:

1. **Linear hygiene** — closing tickets whose fixes already shipped. Cost: seconds per ticket.
2. **Root-cause investigation** — understanding why an open bug happens. Cost: 5–30 min per ticket.
3. **Code fixing** — writing the fix + tests. Cost: 0.5–2 days per ticket.

**These must happen in order, as a hard phase gate.** Mixing them up front is the #1 waste mode in backlog cleanup sessions.

## The Diagnostic Question

Before dispatching any research agent, reading any code, or writing any fix, ask:

> "Have I checked `git log --grep=<TICKET-ID>` AND `count() where module:<X>` in Sentry for this ticket?"

If no → you're about to burn tokens on work that may already be done. Run Step 0 first.
If yes → proceed to investigation.

## Decision Tree

```
You have N bug tickets to clean up
  ↓
PHASE 1: LINEAR HYGIENE (cheapest, do for ALL N first)
  ├─ For each ticket ID, run: git log --all --grep="<TICKET-ID>" -i
  │   ├─ Commit found on main?
  │   │   ├─ Yes → Read commit body (git show <sha>)
  │   │   │         ↓
  │   │   │   Does the fix add Sentry/logger instrumentation?
  │   │   │         ├─ Yes → Run: count() where module:<module-name> in last 7d
  │   │   │         │         ├─ >0 events → FIX IS LIVE → close ticket (Strategy D)
  │   │   │         │         └─ 0 events  → SHIPPED BUT SILENT → do NOT close
  │   │   │         │                         Post investigation comment
  │   │   │         │                         Flag likely config gap (missing env var,
  │   │   │         │                         feature flag, upstream webhook not firing)
  │   │   │         │                         Escalate to user for config fix
  │   │   │         └─ No (pure UI fix) → close ticket with commit reference
  │   │   └─ No → proceed to Phase 2 for this ticket
  │   │
  │   └─ Also check: does this ticket have `Needs Breakdown` or `Epic` label,
  │                    >60 days in current state, ≥5 distinct symptoms in description?
  │         └─ Yes → UMBRELLA → switch to breakdown mode (see Rule 3)
  │
PHASE 2: ROOT-CAUSE INVESTIGATION (only on tickets that survived Phase 1)
  ├─ Dispatch research agent OR read code directly
  ├─ Identify root cause
  └─ Scope the fix
  ↓
PHASE 3: CODE FIXING (only on tickets with confirmed root cause)
  ├─ Write code + tests
  ├─ Run CI
  └─ Ship
```

## Core Rules

### Rule 1: Phase gate enforcement — hygiene MUST complete for the entire candidate set before any agent dispatch

**WHY:** Research agents cannot distinguish "this is the bug" from "this is the fix that resolved the bug" because the code comments read identically. If the fix has already shipped, the agent will describe the fix code as if it were the original bug — confidently wrong. Only `git log` + Sentry can distinguish.

**CORRECT:**
```bash
# Phase 1: hygiene pass for ALL 14 candidate tickets
for id in TICKET-901 TICKET-910 TICKET-916 TICKET-930 ...; do
  echo "=== $id ==="
  git log --oneline --all --grep="$id" -i
done

# Read any commits found. Close already-fixed tickets.
# THEN dispatch research agents only on tickets that remain.
```

**WRONG:**
```
# Dispatching 5 parallel research agents immediately
Task(subagent_type=Explore, prompt="Investigate TICKET-916 overbooking bug...")
Task(subagent_type=Explore, prompt="Investigate TICKET-910 status resolution...")
# ...agents return "root cause found at file:line X" — but the fix shipped yesterday
# and file:line X IS the fix, not the bug. 30 minutes wasted.
```

### Rule 2: Shipped ≠ live — always verify with Sentry module-tag count

**WHY:** A fix can be on `main` and still be completely silent in production. Missing env var, unset feature flag, upstream webhook not firing, silent no-op client — any of these leaves instrumented code dormant. The commit is green; the fix is not.

**CORRECT — verify before closing:**
```
# Fix claims to touch module:meta-capi
mcp__sentry__search_events(
  organizationSlug: "<org>",
  naturalLanguageQuery: "count of events tagged module:meta-capi in the last 7 days"
)
# Returns count() = 42 → fix is live → close ticket
# Returns count() = 0  → fix is silent → do NOT close, escalate config gap
```

**WRONG — trust the commit blindly:**
```
# "I see commit abc123 on main that mentions TICKET-937. Closing."
# Reality: META_ACCESS_TOKEN is unset in Vercel prod. CAPI client is in silent
# no-op mode. Zero events have fired in 30 days. Users still can't track conversions.
# You just closed a ticket that's still actively broken.
```

### Rule 3: Umbrella breakdown auto-detection — skip single-bug triage on umbrella tickets

**WHY:** A ticket labeled `Needs Breakdown` or `Epic`, stuck In Progress for >60 days, with ≥5 distinct symptoms in its description, is not one bug — it's a collection of N root causes that can't fit in a single branch. Trying to triage it as one bug will waste investigation time and produce a fix plan that can't ship. The first job is to break it into per-root-cause sub-tickets.

**Auto-detect signal (ALL three must hold):**
```
isUmbrella = (
  labels.includes("Needs Breakdown") || labels.includes("Epic")
) && (
  daysInCurrentState > 60
) && (
  countDistinctSymptomsInDescription >= 5
)
```

**Action when umbrella detected:**
1. Do NOT dispatch research agents on the umbrella
2. Read the full description + every "Additional report" block
3. Propose N sub-tickets, each with: specific title, parent link, Bug/area labels, priority from symptom severity, files + root cause hypothesis + fix sketch + test plan + AC
4. Group proposed sub-tickets into clusters by shared code path (one investigation covers multiple fixes, one PR ships multiple bugs)
5. Post a breakdown comment on the umbrella with the full list + cluster recommendation
6. Ask user to pick: **A** (keep umbrella as tracking epic + create children), **B** (close umbrella + create fresh with back-links), **C** (don't break down — almost always wrong if already stalled)

## Implementation Pattern

### Phase 1 — Hygiene Pass (automated, <5 min for 20 tickets)

```bash
# 1. Batch git-log check for all candidate IDs
for id in $CANDIDATE_IDS; do
  git log --oneline --all --grep="$id" -i --since="60 days ago"
done > hygiene-results.txt

# 2. For each hit, run `git show <sha>` and read the fix commit body
# 3. For each commit that adds instrumentation, run Sentry module-tag count
# 4. Classify each ticket:
#    - ALREADY FIXED (commit + Sentry >0) → Strategy D close
#    - SHIPPED BUT SILENT (commit + Sentry 0) → investigation comment, keep open
#    - NO COMMIT → survives to Phase 2
#    - UMBRELLA → breakdown mode
```

### Phase 2 — Investigation (only on survivors)

Now you can dispatch research agents. Give each agent the specific ticket + its symptom + the hygiene-pass result ("no commit found, safe to investigate live code").

Research output gets filed as root-cause hypotheses into Phase 3.

### Phase 3 — Fix

Cluster fixes by shared code path. One branch, one PR, one investigation read, one regression test suite covering multiple tickets. The cluster reduction is 3–5x — 14 tickets usually collapse into 4–6 PRs when grouped by file.

## Anti-Patterns

| Anti-pattern | Why it fails | Fix |
|--------------|--------------|-----|
| "Dispatch N research agents in parallel on day 1" | Many agents run on already-fixed code and describe the fix as the bug | Phase gate: hygiene pass first, agents second |
| "Commit on main + PR merged = ticket done" | The commit may be silently dormant if config/env/feature flag is missing | Sentry module-tag count before closing |
| "The ticket description lists 9 bugs, I'll fix them all in one branch" | 2+ months later, branch is still open because scope is unbounded | Breakdown mode: split into 9 children, ship in 3 clusters of related fixes |
| "I'll investigate the first ticket in depth, then move to the next" | Context-switching cost. You'll re-read the same files for each ticket. | Batch by cluster: read the file once, fix 3 bugs that live in it |
| "Close the ticket, the author said they fixed it" | The commit message might say `fix(X): ...` but the fix could be partial, or for a different root cause than the user reported | Read the commit body AND verify the fix is firing AND match the symptom to the commit |

## Audit Checklist

Before marking any bug-cleanup session "done," verify:

- [ ] Every ticket ran through `git log --grep="<TICKET-ID>"` first (Phase 1 hygiene)
- [ ] Every "commit found" result had its commit body read via `git show <sha>` (not just title)
- [ ] Every fix that added instrumentation was verified via Sentry module-tag count (not just "commit on main")
- [ ] Tickets with 0 events but shipped code have an investigation comment flagging the likely config gap (env var, feature flag, upstream)
- [ ] No research agents were dispatched on tickets that were already fixed
- [ ] Umbrella tickets (`Needs Breakdown` + >60d + ≥5 symptoms) were routed to breakdown mode, not triaged as single bugs
- [ ] Remaining tickets were clustered by shared code path and fixed in grouped PRs, not 1-ticket-per-branch
- [ ] Each closed ticket has a Linear comment referencing the specific commit (or the Sentry verification link) — not just `state: "Done"`

## Evidence: The Session That Taught This

**2026-04-15 Aura session:** 14 open bug tickets, planned as a 6-wave cleanup over multiple days.

**What actually happened:**
- **9 of 14 were already fixed on `main`** across three commits — `ec418890a` (AUR-901 billing), `880bbfa0b` (7-bug batch), `1c794af14` (AUR-938 Nylas notify_participants).
- **5 parallel research agents were dispatched before the git log check.** They ran for 30 minutes on already-fixed code. Each agent confidently described the fix code as if it were the bug — the comment `// AUR-916 insurance PUT` reads identically whether you interpret it as the bug marker or the fix marker.
- **AUR-937 (Meta CAPI):** code shipped correctly, but Sentry query showed `count(module:meta-capi) = 0` over 7 days. `META_ACCESS_TOKEN` was unset in Vercel production → CAPI client silently no-op. Ticket had been sitting as "in progress" with the code already deployed. Without Sentry verification, it would have been closed prematurely.
- **AUR-351:** `Needs Breakdown` label since February, In Progress for 2+ months, description listed 9 distinct analytics bugs. Breakdown produced 9 children (AUR-951 through AUR-959) grouped into 3 clusters. First child shipped within a week.

**Cost comparison:**
- Without this framework: ~30 minutes of wasted research + ~8 hours of investigation on already-fixed bugs before anyone noticed = 1 day of burned work
- With this framework: 15 minutes of hygiene + Sentry checks, then straight to the 3 remaining real bugs = 2 hours total

**The compounding lesson:** Step 0 (git log + Sentry) costs seconds per ticket. Skipping it costs hours per ticket. The ROI is 100:1 in favor of checking first. Never skip.
