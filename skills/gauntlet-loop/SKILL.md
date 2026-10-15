---
name: gauntlet-loop
description: >
  Author a Gauntlet Loop: a single prompt that runs an ambitious goal as a bounded
  build/inspect/judge/repeat cycle with a metric the agent cannot fudge. Use when a task
  is too large or too multi-round for one pass, when asked to "keep going until it's
  perfect", to fan out subagents, to harden/audit/production-ready a whole feature, to
  make something faster, to sweep a codebase, or before any long autonomous session.
  Also use when asked to split sprawling work into workstreams, or to write a /loop or
  ultracode prompt. Enforces objective + metric + boundary, forbids builder-self-grading,
  and picks the metric that attacks the failure class the target area actually has.
user-invocable: true
---

# Gauntlet Loop

A Gauntlet Loop turns one instruction into a persistent cycle: generate the work, inspect the real result, judge it against a stated bar, fix the largest gap, repeat until a success condition, budget, or escalation rule stops it. Pattern credited to Matt Shumer ("Claude of Duty"); this skill is the production-hardened version.

The failure mode a loop exists to prevent is not bad code. It is **plausible work believed because it was plausible**. A believable explanation, believed because it was believable, is the same defect as the bug it explains, one level up.

## Step 0: decide whether this should be a loop at all

Do NOT author a loop when:

- The work is one or two discrete verifiable actions. Run a backfill, send a reply, apply a known fix. A loop adds ceremony and delays the thing that closes the question.
- Success cannot be described yet. Do it manually once.
- The agent cannot observe the real result. A loop with no feedback is an expensive single prompt.
- Mistakes are irreversible and the boundary list would exceed the objective.
- One careful human pass is cheaper than writing and reviewing the loop.

If work has sprawled across several concerns, **split by metric, not by subject**. Two concerns share a loop only if one metric governs both. Correctness ("did this ship what the commit says"), speed ("did the number move"), and semantics ("does this label mean what it says") are three loops. Merged, the loop optimizes the easiest metric and abandons the hardest. Name the discrete non-loop actions separately and put them first.

## Step 1: write the objective

State the outcome, not the route. It must be gradable by someone who did not build it.

Weak: "Improve the API." Useful: "A partner engineer building against the published schema, with no source access and no conversation with us, builds a correct client first try and cannot construct a reasonable query that returns wrong data, unrepresentable data, or an N+1."

Order the items by **cost x irreversibility**, not importance. Item 0 is always the cheapest thing that de-risks everything after it, usually verifying the facts the plan depends on plus a tooling preflight. State what is OUT of scope explicitly.

## Step 2: pick the metric that fits the failure class

This is where loops are won or lost. Always include both kinds:

**Executable.** Tests, typecheck, a live query, a screenshot, an observed green CI run. The only thing that stops a loop congratulating itself.

**Critic-judged.** A separate agent, fresh context, given the objective, the rules, and the **real artifact**. Never the builder's summary. A builder remembers every compromise and can justify each one; that is exactly the context the judge must not have.

Then add the rule that attacks what this area actually gets wrong:

| If the risk is | Use |
|---|---|
| Wrong explanations of why something fails | **Mechanism Rule.** Every causal claim settled by a read-only query BEFORE it enters a plan. A plan asserting "this fails because X" where X was never queried is a failed round even if X is correct. |
| Believing a gap exists | **Absence Rule.** Any "X does not exist" claim settled by search plus one level of indirection. Name what you searched and what you followed. |
| Asserting infra state from source | **Live-Read Rule.** Query the database, hit the endpoint, read the deployment. Reading the code that would produce the state does not count. |
| Shipping code no user can see | **Demonstrated-Effect Rule.** A round passes only on an observable result in a real environment. "The handler is registered" is the state every dark surface is already in. |
| Breaking an external consumer | **Would-a-partner-have-seen-it-first**, plus audit-before-edit as a hard gate. |
| Optimizing on vibes | **Measurement is permission, not proof.** Nothing applied before its cost is measured; nothing kept unless the number moved. |
| A number that is right under a misleading name | **Stakeholder Rule.** Write the belief a non-technical reader forms, verify that belief with a query. False belief = failed label, however correct the query. |

Always include the **failure-triage ladder**, checked in order before editing anything:

1. Stale tree, stale base, or a cache replaying?
2. Ambient on main, predating this work? MEASURE IT before accepting blame.
3. Stale assertion from an earlier migration?
4. Real product defect?
5. Only then: infra.

Record which rung each failure landed on. Two consecutive rung-4s means the earlier change was under-tested, which is a bigger finding than either failure.

## Step 3: write the boundaries

Loops do not stop on their own. "Until perfect" is motivation, not a stop condition.

- **Approval gates**, per action and per session, never generalized from one yes: breaking contract changes, production migrations or writes, new OAuth scopes, deploys, dependency additions, anything that increases notification volume, and beginning the edit phase of an audit.
- **Stop-and-report**, for decisions that belong to a human: what a number should mean, whether a consumer depends on a field, whether a duplicate can be deleted, anything blocked on product semantics.
- **Nevers**, naming the defect classes just eliminated so the loop cannot reintroduce them.
- **The spinning rule:** stop when the same failure recurs twice without a changed strategy. Repeating an action with the same evidence is spinning, not looping.

## Step 4: decomposition and state

Fan out on genuinely independent work (routes, screens, files, per-measure changes). Keep **one owner** for anything coupled: a public schema, a two-sided event contract, several call sites converging on one definition. Parallel edits to a shared contract produce locally-correct, globally-inconsistent results, which is the original bug plus steps. Broad fan-out measurably underperformed sequential ownership on coupled systems in Shumer's own run.

Read-only fan-out is nearly free. When unsure: fan out to read, serialize to write.

Require a progress file outside the conversation: current target, parts passed, **failed approaches and why**, evidence, next action, remaining budget. Add one section recording the claim class this loop keeps getting wrong (every mechanism claim and the query that settled it; every absence claim and the indirection followed). Three wrong root causes in one session is a pattern, and the file is what makes the fourth visible before a human sees it.

## Step 5: emit the prompt

Use `references/template.md`. Read `references/field-guide.md` for the full rationale and the green-that-means-nothing catalogue; read `references/examples.md` for eight worked loops across correctness, client honesty, definition convergence, dark-surface activation, performance, deploy provenance, metric labelling, and route-level Storybook.

Always include an **integration pass**: one fresh agent that built nothing inspects the whole result for consistency and seams, not redesign, then hands over the diff and the receipts.

## Non-negotiables

- The builder never grades its own work. Cheapest rule here, catches the most.
- The critic gets the artifact, never the summary.
- A green subset is not evidence. Re-run the whole gate from a clean build in the same checkout each round.
- Each round deletes its own scratch (builds, dependency installs, database restores) before the next round starts, and keeps the evidence. The `agent-disk-budget` skill owns the evidence and scratch split.
- A cache hit is not a run. A piped gate reports the pipe's exit code.
- A safety test that has never gone red is a hypothesis. Show it failing first.
- Delete config you cannot prove is load-bearing. A line that looks necessary and isn't is how the next person concludes the wrong thing.
- Check what parses a file before editing it. Tables, snapshots, and journals get read as data.
- A manifest scope, env var, or workflow trigger is a request, not a grant. A workflow that has never run is indistinguishable from one that does not exist.
- If the clone is shared: explicit `git add` paths only, `git diff --cached --stat` before and `git show --stat HEAD` after, never touch another session's uncommitted files, re-read HEAD before assuming the branch has not moved, and after any rebase check authorship and count before pushing.
