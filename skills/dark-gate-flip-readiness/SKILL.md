---
name: dark-gate-flip-readiness
description: Safely replace a hot computed/derived read with a cheaper persisted-or-SQL projection by shipping it DARK behind a flag, pinned by an automated source-of-truth parity check + a drift invariant + a bounded backfill, then flipping on a canary. Activates when optimizing a slow read path by moving derivation (status, scoring, rollups) into SQL or a persisted column, or any "make the hot read cheaper without changing results" rewrite.
---

# Dark-Gate Flip-Readiness

When you make an expensive read cheaper by changing *how a value is computed* —
moving a TypeScript-derived status into SQL, persisting a projection, caching a
rollup — you're trading correctness guarantees for speed. The risk isn't the
speedup; it's that the new path silently disagrees with the old one for some
rows. This skill is the apparatus that makes such a swap **flip-a-flag safe**.

## When This Skill Activates

- Replacing an O(all-rows) in-memory derivation with a bounded SQL/persisted read.
- Persisting a projection of a rule that used to be computed at read time.
- Any "same results, much faster read" rewrite of a hot path.

## The One Question

> **"If the new path silently disagrees with the old one for one row, what turns red?"**

If the answer is "nothing", you're not flip-ready. Build the gates first.

## Decision Tree

```
Rewriting how a hot read computes its result?
├─ Keep the OLD path as the runtime fallback, new path behind a flag (default OFF)
├─ Is the new result provably == the old single source of truth?
│   ├─ NO  → build a PARITY check (new ≡ SSOT across N scenarios) — must be green
│   └─ YES → still add a DRIFT INVARIANT (persisted projection vs SSOT, ongoing)
├─ Does the new path read a persisted/backfilled value?
│   └─ YES → bounded (keyset-streamed) BACKFILL reconciler, dry-run first
├─ Flip on ONE canary → verify parity + latency → roll out → retire fallback
```

## Core Rules

1. **One source of truth, two readers.** The old computation stays the SSOT; the
   fast path must be *pinned* to it, never a re-implementation that can drift.
2. **Parity is automated, not eyeballed.** A script asserts new-path ≡ SSOT
   across every branch/scenario (incl. the gnarly edge cases). It runs in CI and
   must be green before flip.
3. **Drift is monitored, not assumed.** A read-only consistency invariant
   recomputes the SSOT on a bounded sample and flags any row whose persisted
   projection disagrees — so post-flip drift pages you instead of corrupting reads.
4. **Backfill is bounded + idempotent + dry-run-first.** Reconcile existing rows
   with keyset-paginated streaming (never load the whole table), guard each write
   by the current stored value (concurrent-writer safe), dry-run on staging to
   report the flip count before `--execute`.
5. **Ship dark, flip on a canary.** Default-off flag; the unchanged old path is
   the fallback. Flip one tenant, verify parity + the latency win, then widen.
6. **Governance if you bend a rule.** If the rewrite violates a standing rule
   (e.g. "no business logic in SQL"), document the *scoped* exception and name
   the gates that keep it honest (the parity script + the invariant) — the rule's
   intent (one testable source) is preserved, not abandoned.

## Anti-Patterns

- Re-implementing the derivation in the new path (two sources → guaranteed drift).
- "We tested it once" instead of an enforced parity check.
- Unbounded backfill (`findMany` the whole table) — OOM + lock risk; stream by keyset.
- Flipping globally on day one instead of a canary.
- Deleting the fallback before the canary proves out.

## Audit Checklist

- [ ] New path behind a default-off flag; old path intact as fallback.
- [ ] Parity script: new ≡ SSOT across all branches; green in CI.
- [ ] Drift invariant registered (read-only, bounded sample, recomputes via SSOT).
- [ ] Backfill: keyset-streamed, idempotent, guarded writes, dry-run reported.
- [ ] Canary flip plan + latency/parity verification before rollout.
- [ ] Scoped-exception governance written if a standing rule was bent.
