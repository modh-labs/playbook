---
name: stale-bot-pr-triage
description: 'Triage auto-generated fix PRs (Sentry Seer, Dependabot, Renovate, Cursor) by diffing their intent against CURRENT main BEFORE actioning them. Use when a bot opens a fix PR, when sweeping a backlog of bot PRs, or before cherry-picking/merging any machine-authored branch. Bot PRs are stale snapshots — often already fixed on main, fixed better, or actively regressive. Default to "survey first," not "apply."

'
---

# Stale Bot-PR Triage

A bot opened a fix PR. Your instinct is "review it, then merge it." That instinct is wrong often enough to cost you a regression.

Auto-fix bots (Sentry Seer, Dependabot, Renovate, Cursor background agents) cut a branch against a **snapshot** of main and then sit in the queue for days or weeks. By the time you look, main has moved — sometimes hundreds of commits. The fix may already be on main, may be on main in a *better* form, or — worst case — may *undo* a deliberate guard a human added in the meantime. "Apply the bot's fix" is the wrong default.

## When This Skill Activates

- A bot (Sentry Seer, Dependabot, Renovate, Cursor, etc.) opens a fix or upgrade PR
- You're sweeping a backlog of accumulated bot PRs
- You're about to cherry-pick or merge any machine-authored branch
- A bot PR is "old" (more than a few days) or the repo moves fast

## The One Question

> **"Is the code this PR targets already different on current main — and if so, is main already fixed, fixed better, or did someone add a guard this PR would remove?"**

Answer it with `git`, not by reading the PR description.

## Decision Tree

```
Bot opens fix PR
  │
  ├─ How far behind main is the branch?
  │     git rev-list --count <branch>..origin/main
  │     (if it's hundreds of commits, treat everything below as likely-stale)
  │
  ├─ Diff the PR's INTENT against CURRENT main (not the PR's base):
  │     grep / git log -S<distinctive-string> on the target files in main
  │
  ├─ Already fixed on main?
  │     YES → CLOSE. Comment the superseding commit SHA. Done.
  │
  ├─ Fixed BETTER on main? (main has a TTL/guard/observability the PR lacks)
  │     YES → CLOSE. Comment why main's version is superior. Done.
  │
  ├─ Would the PR REGRESS main? (it removes a guard, deletes observability,
  │   relaxes a constraint a human added on purpose)
  │     YES → CLOSE. Cite the guard and the commit that added it. Do NOT merge.
  │
  └─ Genuinely unshipped value?
        YES → RE-IMPLEMENT on current main, against current APIs.
              Do NOT cherry-pick the stale branch.
              Validate (typecheck + tests), commit, then close the PR
              with the new SHA.
```

## Core Rules

### Rule 1 — Survey main before you read the diff

The PR description describes the world at branch-cut time. Current main is the world you're shipping into. Check main first.

```bash
# How stale is it?
git rev-list --count <bot-branch>..origin/main      # commits main is ahead

# Is the fix already present? Search for the symptom, not the PR's code.
git log --oneline -S "inMemoryState" -- path/to/target.ts
grep -n "the-guard-or-fix-keyword" path/to/target.ts
```

### Rule 2 — A passing CI on the bot branch proves nothing about current main

The bot's branch was green against its stale base. Re-implementing against current main frequently surfaces API drift the bot couldn't know about (renamed functions, changed signatures, decomposed files). Let the type-checker tell you — it catches stale APIs instantly.

### Rule 3 — Watch for guard removal (the dangerous case)

The most damaging bot PRs *silence the symptom by removing the protection*. The guard's REASON usually lives in a comment or a doc the bot never read.

```
WRONG (what the bot does):
  // error keeps firing on calendar drift → just auto-correct closer_id
  await db.update(calls).set({ closerId: matchedId })...

RIGHT (what was already on main, on purpose):
  // We log + alert but DON'T auto-correct: the calendar organizer can
  // legitimately be a shared mailbox / admin delegate / external party.
  logger.warn({ ... }, "closer drift detected");
  captureException(...);  // no silent mutation
```

If a bot PR makes an error "go away" by deleting a log, a guard, an idempotency check, or an observability signal — stop. Find why that guard existed before you accept its removal.

### Rule 4 — Re-implement, don't cherry-pick

When a bot PR has real unshipped value, take the *idea*, not the diff. Build it on current main against current APIs and conventions, with the project's current patterns (repository layer, tracing wrapper, test shape). Cherry-picking a months-old branch drags stale APIs and stale assumptions with it.

### Rule 5 — Close superseded PRs with the SHA

"Code merged" and "PR closed" are two different states. If you fix the issue with a direct-to-main commit, the bot's PR is still open and stale. Close it with a comment naming the superseding commit — otherwise it pollutes the review queue, re-surfaces in triage, and makes "is this done?" ambiguous forever.

## Anti-Patterns

- **Cherry-pick-then-fix**: applying the stale branch and patching it. You inherit its API drift and its assumptions. Re-implement instead.
- **Merge-because-green**: trusting the bot branch's CI. It was green against a stale base.
- **Symptom silencing**: accepting a fix that removes a log/guard/check without finding why the guard existed.
- **Orphaned PRs**: shipping the fix to main but leaving the bot PR open. Close it with the SHA.
- **Trusting the queue over git**: assuming "open PR = not yet fixed." The ticket/PR queue lags git by days.

## Audit Checklist

For each bot PR before actioning:

- [ ] Computed how far the branch is behind main (`git rev-list --count`)
- [ ] Searched current main for the fix/symptom (`git log -S`, grep) — NOT just read the PR
- [ ] Classified: already-fixed / fixed-better / regressive / unshipped
- [ ] If already-fixed or better → closed with superseding SHA in a comment
- [ ] If regressive → closed, citing the guard it removes and the commit that added it
- [ ] If unshipped → re-implemented on current main against current APIs (not cherry-picked), typecheck + tests green
- [ ] Every superseded/closed PR has a comment explaining where the work went
- [ ] No bot PR left open-but-stale in the queue

## Why It Matters

A real sweep: 7 Sentry Seer PRs, every one ~500 commits behind main. Four were already fixed on main (two of them *better* than the bot's version — e.g., a circuit-breaker fallback that already had the TTL the bot's version lacked). Two would have re-introduced silent data-mutation bugs that a human had deliberately guarded with a log-and-alert stance. Only two carried genuinely unshipped value, plus one net-new feature. Blindly applying the queue would have undone good work and shipped two regressions. Surveying main first turned a "merge 7 PRs" afternoon into "close 6, re-implement 1 properly" — and zero regressions.
