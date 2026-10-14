---
name: fix-e2e
description: 'Intelligent fix-loop for Playwright e2e suites with failing or skipped tests. Triages every failure through a 4-rung evidence ladder (locator drift → test bug → product bug → infra), fixes at the right layer, and exits only after two consecutive clean runs. Refuses the "obvious" flake-hiders — bumping retries, adding waitForTimeout, or silencing tests behind test.skip — because those create long-term flake debt. Use when an e2e run is red, after UI changes that break many specs, or before a release gate.

'
---

# The E2E Fix-Loop

## When This Skill Activates

- A Playwright run has failing or skipped tests
- Before a release gate and the suite isn't green
- After a product change (UI copy rename, route move, auth flow edit) that likely broke semantic locators
- You catch yourself about to add `waitForTimeout`, bump `retries`, or add `test.skip(true, ...)` to "fix" flakes
- The suite has a growing pile of `.skip` and `.fixme` that nobody tracks

**Not for:** writing new tests. That's a separate authoring skill.

## The One Question

> "Would I put this fix in production code, or am I only doing it to make the test green?"

If the answer is "only to make the test green," you're patching a symptom, not a cause. Stop and go back up the triage ladder.

---

## The Core Contract

1. **"Green" means zero fails AND zero unexplained skips** across two consecutive runs. One clean run is not enough — that's how flakes hide.
2. **Never silence a failure.** No `test.skip(true, ...)`, no `waitForTimeout`, no retry-count bumps, no timeout inflation to mask real slowness.
3. **Fix the root cause at the right layer.** If the product is broken, fix the product. Don't patch the test to tolerate it.
4. **Evidence before edits.** Read the error context, screenshot, and live DOM before changing a single line.
5. **One spec green, then the next.** Re-run each fixed spec in isolation before moving on — don't batch-commit blind.

---

## The Triage Ladder

Every failure gets classified by walking this ladder top to bottom. Stop at the first rung that matches.

### Rung 1 — Locator drift (test-side fix)

**Signal:** `element(s) not found` or `strict mode violation` on a heading/role the app clearly still renders. Screenshot shows the correct page state. Accessible name in the DOM differs from what the test asserts.

**Typical cause:** Someone renamed a button, heading, or step label. The component is healthy; the test is looking for the old name.

**Fix:** Update the locator to match the current accessible name/role. Prefer `getByRole` with an accessible name. If the component exposes a documented testability hook (`aria-label`, `data-state`, `data-testid`), use that — every mature codebase has canonical handles; find and use them.

**Never:** fall back to `getByText` on a brittle body string, or add `data-testid` just to dodge the accessibility work.

### Rung 2 — Test bug (test-side fix)

**Signal:** Test assumes ordering/state that was never guaranteed. Race between a mutation and a read. Relies on `networkidle` or `waitForTimeout`. Uses a shared fixture that another spec mutates.

**Typical cause:** The test is coupled to timing or to global state. It worked by luck.

**Fix:** Add the missing readiness signal — `aria-busy`, `data-state="ready"`, `window.__*Ready`, or a visible confirmation — to the **component**, not the test. Then update the test to wait on that signal. Isolate shared state with unique test-run IDs.

**Never:** add a `waitForTimeout`. The moment you do, you've encoded "slow enough on my machine, usually" as a hard assertion, and CI will punish you for it.

### Rung 3 — Product bug (product-side fix)

**Signal:** You drove the same flow manually (or via Playwright MCP) and confirmed the app is actually broken. Dead-end UI, hanging fetch, missing button, silent error. The test is right; the code is wrong.

**Typical cause:** A real product regression — often a graceful-degradation path that was never exercised. The happy path is fine; the error path dead-ends.

**Fix:** Fix the product. Graceful degradation — render the fallback editor seeded with defaults instead of a dead Alert, add a fetch timeout so stuck connections surface errors instead of hanging — is usually the right move. It improves production UX *and* unblocks the test.

**Bonus:** a Rung 3 fix is almost always a product improvement. You didn't just unblock a test; you fixed a real UX dead-end that had been masked by the happy path.

### Rung 4 — Infra / flake (escalate, don't patch)

**Signal:** Failure can't be reproduced locally or via MCP. Fails only under load or on specific shards. Traces back to connection exhaustion, third-party outage, rate limits, or circuit breakers stuck open.

**Typical cause:** Staging infrastructure is degraded. The test is right; the environment is wrong.

**Action:** **Stop patching.** Pull staging logs and metrics for the window of the failure. Report findings. Open a ticket. Move on to the next failure.

**Never:** raise `retries: N` to mask it. Never add `test.skip` to "temporarily" hide it. Retries and skips become permanent the moment you merge them.

---

## The Skip Policy

`.skip` and `.fixme` are treated as failures unless they match an allowed shape.

### Allowed

```typescript
// Capability gate — genuinely cannot run without this
test.skip(!process.env.STRIPE_TEST_KEY, "requires STRIPE_TEST_KEY");

// Linked ticket — owner, deadline, loud failure when it starts passing
test.fixme(true, "AUR-1234 — blocked on Nylas sandbox fix");
```

### Banned

```typescript
// No gate, no ticket, no comment — dead spec
test.skip("flaky on CI", async ({ page }) => { /* ... */ });

// "Temporarily" disabled — it's been two years
test.skip(true, "TODO fix this");

// Used as graceful degradation for infra outages
test.skip(!process.env.CI, "only works locally"); // ← actually an infra bug
```

**Rule:** every skip must have either an environment-variable gate OR an open ticket reference. Enforce with a `scripts/check-e2e-skips.ts` step in CI, same shape as the `check-no-wait-timeout.ts` pattern.

When the fix-loop encounters a banned skip, it either repairs the test or deletes the dead spec. It does not leave the skip dormant.

---

## The Loop Protocol

```
1. INGEST
   - Parse the last run's failure list (terminal output or
     test-results/*/error-context.md)
   - Grep the suite for test.skip / test.fixme
   - Build a list: { spec, test, rung-hypothesis, evidence-path }

2. EVIDENCE (per failure)
   - Read the error-context.md + screenshot
   - If the rung is unclear, drive the browser to the same state:
       • MCP reproduction OR local headful run
       • Inspect the accessibility tree at the point of failure
       • Decide: does the element exist under a different name?
         is the app in a broken state? is it a race?
   - Classify the rung. Record it.

3. FIX (one failure at a time)
   - Apply the rung-appropriate fix.
   - Re-run ONLY that spec (via --grep).
   - Green → next.
   - Red → re-evidence; you picked the wrong rung.

4. SWEEP SKIPS
   - For every unexplained skip: repair or delete.
   - Commit skip-policy compliance before the next full run.

5. FULL RE-RUN, TWICE
   - Run the full suite.
   - If new failures appeared, go to step 2.
   - Green? Run it again — two consecutive clean runs required.

6. REPORT
   - Fixes by rung. Infra escalations. Skips removed.
   - "Done" only if exit criteria met.
```

---

## "Look Before You Patch"

The most common mistake is guessing from the screenshot and editing the locator blindly. The loop between "rename locator → re-run → fail → rename again" burns hours.

Instead: **drive the browser to the same state the test reached and read the accessibility tree directly.** You find the real locator in ten seconds instead of ten minutes.

In practice this means:

- Playwright has a **trace viewer** — `npx playwright show-trace test-results/…/trace.zip` replays the test step by step with DOM snapshots
- Playwright has a **codegen** — `npx playwright codegen staging.example.com` gives you the canonical locator for anything you click
- Browser automation MCP servers (if you have them configured) let Claude Code itself drive the session

Whichever tool you use, the rule is: **look at the live DOM before renaming a locator.** You'll be right the first time instead of the third.

---

## Anti-Patterns

### 1. Retry inflation as a flake-hider

```typescript
// playwright.config.ts
export default defineConfig({
  retries: 3,  // ← every new flake gets hidden for free
});
```

Retries are for genuinely flaky *infrastructure* (network jitter, DNS), not flaky *tests*. Three retries turns a 30% flake into a 99.7% "pass" — hiding the bug while consuming 3× CI time. **Cap at 1 retry** and fix flakes at the source.

### 2. `waitForTimeout` as a fix

```typescript
await page.click('button.save');
await page.waitForTimeout(2000);  // ← encoded "slow enough on my laptop"
await expect(page.getByText('Saved')).toBeVisible();
```

The moment the component gets slower (or CI gets noisier), this breaks. Wait for the signal, not the clock:

```typescript
await page.click('button.save');
await expect(page.getByText('Saved')).toBeVisible();  // web-first, auto-retries
```

### 3. `test.skip` as graceful degradation

```typescript
test.skip(true, "email flaky, re-enable later");
```

It's been two years. "Later" is never. Either repair it or delete it — a dormant skip is worse than no test because it looks like coverage.

### 4. Inflating a single timeout

```typescript
await expect(locator).toBeVisible({ timeout: 600_000 });  // 10 minutes!
```

If the thing takes 10 minutes, the product is broken. A timeout this large hides a Rung 3 product bug behind a green checkmark.

### 5. Adding `data-testid` instead of an accessible name

```tsx
// Before
<button onClick={submit}>Submit</button>

// "Fixed"
<button onClick={submit} data-testid="submit-btn">Submit</button>
```

The button already had an accessible name. `data-testid` here is a confession that you didn't want to write `getByRole('button', { name: 'Submit' })`. Every `data-testid` is a decision to ignore accessibility — use them only for page-level landmarks where no natural role fits.

---

## Audit Checklist

Before declaring the suite green:

- [ ] Zero failures across two consecutive full runs
- [ ] Zero `test.skip` / `test.fixme` without env-gate or ticket reference
- [ ] `retries` ≤ 1 in `playwright.config.ts`
- [ ] No `waitForTimeout` in the codebase (CI-enforced)
- [ ] No `networkidle` in the codebase
- [ ] Every Rung 3 product fix has a ticket reference or commit-body explanation
- [ ] Every Rung 4 escalation has a linked ticket
- [ ] Every new readiness signal (`data-state`, `aria-busy`) is documented in the feature's testability notes

---

## Why This Pattern Matters

Flake debt compounds. A team that ships one hidden flake per sprint accumulates 13 per quarter. After a year, 50+ tests have "probably fine" attached to them, and nobody remembers which ones. The next real regression gets quietly hidden in the noise, and by the time someone notices, it's in production.

The fix-loop exists to make the cost of hiding a flake higher than the cost of fixing it. A ten-minute triage is cheaper than an hour of pager-duty six months from now. The discipline is what keeps the suite trustworthy.

Trust in the suite is the whole point. If you don't trust it, you don't gate on it, and the suite's protective value collapses to zero.
