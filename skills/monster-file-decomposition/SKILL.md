---
name: monster-file-decomposition
description: When decomposing a monster file (>1000 LOC) into focused submodules in a closed-source monorepo, extract one submodule per commit AND migrate all consumer imports to the new source-of-truth path in the SAME commit. Never use re-export shims to bridge consumers. Activates on any file >1000 LOC with 2+ external consumers in a monorepo.
---

# Monster File Decomposition (No-Shim Rule)

## The One Question

> "How will a future grep tell me which file owns this function?"

If the consumer imports from path A but the logic lives in path B (via re-export shim in A), the answer is "two greps, one of which is misleading." That's the failure state this skill prevents.

## The Rule

**Each extraction commit MUST:**

1. Create the new submodule with the extracted code (and its tests/types/helpers)
2. Remove the extracted code from the parent file
3. **Update every consumer's import path** to point at the new submodule
4. Update every `vi.mock(...)` / `jest.mock(...)` reference in test files
5. Stage with `git commit --only <explicit paths>` and commit atomically (one phase = one commit)

After the final phase, the parent file is deleted entirely. No re-export block survives.

## Why no re-export shims (in a monorepo)

In **open-source libraries** with unknown external consumers, a re-export shim is the right tradeoff: you take a slightly dishonest import graph to spare consumers a one-time churn you can't coordinate.

In **closed-source monorepos** with bounded, visible consumers, the tradeoff inverts:

- The consumer-migration cost is bounded (you can see every importer) and one-time. Pay it once.
- The shim's cost is permanent. It hides which file owns the symbol. `grep "from .*/foo"` finds the import; `grep "function foo"` finds the definition; they are in different files. Onboarding agents (human or AI) trip on this for years.
- The "we'll delete the shim later" plan reliably becomes "we never deleted the shim." The deleter is a future agent who has no incentive (the code works, the shim is invisible) and the delete-only PR feels like pure churn. Front-load the work into the extraction commit so it's never deferred.
- During the intermediate phases, each commit is self-consistent: it typechecks clean, tests pass, no broken imports. A reviewer can `git checkout <mid-phase-sha>` and the branch is green.

## Order of operations within a phase

1. **Map sibling-call dependencies** between planned submodules
2. **Extract the destination before the caller** — so when a sibling submodule calls into another sibling, the call path is already submodule-to-submodule, never submodule-to-still-fat-orchestrator
3. **One submodule per commit, gates green between each** — typecheck + tests pass at every commit
4. **`git commit --only <my-paths>` in multi-agent repos** — sibling `git add .` from concurrent agents will otherwise sweep your unstaged files into their commits
5. **Update the parent file's `AGENTS.md`/`README.md` in the same commit** to describe the new layout

## After the last phase: coverage audit

Decomposition makes previously-invisible coverage gaps visible. When a 3,000-LOC file had "30% coverage" attributed to it, the per-query split was hidden in the aggregate; the moment that file becomes 5 submodules, each one's coverage stands alone — and queries that were never tested individually now show up at 0%.

Treat this as a feature, not a regression. **After the final extraction phase:**

1. Run coverage per-submodule (`vitest run --coverage <submodule-path>`).
2. For each submodule whose coverage falls below the project's threshold (look for the existing well-covered files in the same domain as the reference), open a follow-up to backfill unit tests using the well-covered submodule as the pattern reference.
3. Land at least the smallest submodule's tests in the same branch as the decomposition; the larger ones can be sequenced after.
4. Document the gap if you defer it. A submodule at 0% should not look the same as a submodule that was always at 0% — the decomposition is the moment that gap became *cheap to fix*, and the AGENTS.md should note which submodules are still pending coverage.

Aura's analytics decomposition (May 2026) is the cautionary example: the 5-phase extraction was clean, but 4 of 5 submodules landed with zero dedicated unit coverage. The coverage that existed before the split (concentrated in `getDashboardAnalytics` and lead-source partial) was preserved, but the post-split surface made the gap obvious — objection (1,122 LOC), call-quality (640 LOC), and funnel (153 LOC) all had to be backfilled in a separate session. Worth doing the coverage audit at phase-end so it's all one motion.

## What NOT to do

- ❌ **Don't add `export ... from "./{submodule}"` bridge lines to the parent.** Even "temporarily for one phase." They become permanent. Reference: AUR session 7 burned a full session correcting this exact anti-pattern after session 5 left shims behind.
- ❌ **Don't create an `index.ts` barrel** in the submodule directory either. Same problem — moves the dishonesty one level deeper.
- ❌ **Don't extract everything in one mega-commit.** Each phase should be reviewable; a 10-file extraction with 50 consumer updates is harder to revert than 5 commits of 2-file extractions with 10 consumer updates each.
- ❌ **Don't separate types from their primary consumer** into a grab-bag `types.ts`. Co-locate types with the submodule that owns the function whose return type they describe.
- ❌ **Don't `git commit` after a bare `git add`** — a sibling agent's concurrent `git add .` can sweep your unstaged files in the race window. Use `git commit --only` with explicit paths.
- ❌ **Don't defer consumer migration to a "cleanup commit at the end."** That commit is itself an admission you violated the rule for every commit before it.

## Decision rule

If you find yourself typing `export { ... } from "./submodule"` in the parent to "temporarily keep consumers working":

**STOP.** Migrate the consumers in this commit instead. If the consumer-migration count is too large to fit in one commit, the extraction is bundled wrong — split it into smaller per-domain pieces so each piece's consumer surface is manageable.

## Reference implementation

**Aura `analytics.repository.ts` decomposition (May 2026):**

- Original: 3535 LOC, ~10 external route consumers
- Decomposed into 5 submodules under `_shared/repositories/analytics/`:
  - `overview.repository.ts` (794 LOC) — dashboard KPIs, filters
  - `attribution.repository.ts` (973 LOC) — UTM / referrals / lead source
  - `objection.repository.ts` (1,122 LOC) — objection analytics
  - `call-quality.repository.ts` (640 LOC) — AI score trends
  - `funnel.repository.ts` (153 LOC) — booking funnel
- 5 phases, 5 commits, each with extraction + consumer migration:
  - Phase 1 (objection) → Phase 2 (`38b1cd714` call-quality) → Phase 3 (`1c8c3d08c` attribution) → Phase 4 (`3d66b7a44` funnel) → Phase 5 (`d0db7ea60` overview + delete parent)
- Final phase deleted the parent file outright. Zero re-export bridges across the entire refactor.
- Docs codified in `apps/web/app/_shared/repositories/AGENTS.md` with the explicit rule: "never add a 'temporary' `export ... from "./submodule"` block to the parent."

## Proof points (other Aura monsters that took this approach)

- `data-grid-table` (component): decomposed into `parts/` submodules, consumer migration in the same commits, parent deleted at the end
- `call-status.service`: extracted into focused submodules, consumers migrated atomically per phase

## When this skill does NOT apply

- **Open-source libraries** with external/unknown consumers — there, re-export shims are correct, because you cannot coordinate the consumer migration. This skill is for closed-source monorepos only.
- **Single-consumer extractions** (1 importer) — just rewrite the one consumer; the "phasing + atomic commits" discipline is overkill.
- **Small files (<500 LOC)** — pull the helper into a sibling, update the one or two callers, done. No formal phasing needed.
