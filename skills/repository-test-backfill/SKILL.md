---
name: repository-test-backfill
description: Two-tier strategy for retroactively writing unit tests for a Drizzle-based repository module that has zero or sparse coverage. Tier 1 = empty-org early-return test for every public function (cheap, locks the signed-out contract). Tier 2 = deep happy-path tests for the most-used functions only. Use after a monster-file decomposition surfaces 0%-coverage submodules, or when adding tests to any uncovered repository file.
---

# Repository Test Backfill (Two-Tier Strategy)

## The problem this solves

You have a repository module (Drizzle-based, Aura-style — `createServerDb` + `db.rls(tx => ...)` pattern) with N public functions and zero or sparse unit test coverage. Writing exhaustive tests for every function is multi-hour work. Writing zero tests perpetuates the gap. The two-tier strategy lets you ship meaningful coverage in 30-60 minutes per submodule.

This is especially common after a [[monster-file-decomposition]] — the moment a 3,000-LOC monolith becomes 5 submodules, the aggregate coverage number splits and 0%-coverage submodules become visible. Backfilling those gaps is exactly what this skill is for.

## The two tiers

### Tier 1: empty-org early-return test for EVERY public function

Every public function in a `createServerDb`-style repository has the same early-return contract: when there's no `orgId` (signed-out caller, RLS-stripped JWT, edge case), it returns a fixed empty shape — usually `[]`, sometimes a zero-filled object, occasionally a project-default constant.

Pinning that shape is the cheapest, highest-coverage-per-line-of-test you can write:

- **Cost**: ~5 lines per test (mock no-org, call function, assert shape)
- **Value**: catches the common breakage where someone changes a returned field name and silently breaks the downstream prop-typing in a consuming route
- **Locks the contract** for new contributors / agents who add a new function — they'll see the pattern and write one

Target: 1 empty-org test per public function. No exceptions.

### Tier 2: deep happy-path tests for the most-used functions

For functions that drive primary product surfaces (a tab's main chart, the homepage's KPI, etc.), write 2-4 tests covering:

- Happy path with realistic mock rows + assertion on the shaped output
- A null/missing-field edge case (real data has nulls)
- A sort/ordering invariant if the function returns a sorted array
- Math sanity (count + percentage + ratio math)

Don't write deep tests for every function — pick the 2-3 highest-traffic ones per submodule. The remaining functions stay protected by their Tier 1 test.

## The mock template

Aura's `createServerDb` pattern means every function does roughly:

```ts
const { db, orgId } = await createServerDb();
if (!orgId) return /* empty shape */;
const rows = await db.rls((tx) => tx.select({...}).from(table).where(...));
// aggregate rows -> shaped output
return shapedOutput;
```

The minimal mock that supports both tiers:

```ts
import { beforeEach, describe, expect, it, vi } from "vitest";

const mockCreateServerDb = vi.fn();
const mockSelect = vi.fn();

vi.mock("@aura/database/server", () => ({
  createServerDb: () => mockCreateServerDb(),
}));

vi.mock("@/app/_shared/lib/sentry-logger", () => ({
  createModuleLogger: () => ({
    info: vi.fn(),
    error: vi.fn(),
    warn: vi.fn(),
    debug: vi.fn(),
  }),
}));

vi.mock("@/app/_shared/lib/query-timing", () => ({
  withRepositoryTiming: (_name: string, repo: Record<string, unknown>) => repo,
}));

vi.mock("@/app/_shared/lib/sentry/captures/analytics", () => ({
  captureAnalyticsException: vi.fn(),
}));

// IMPORTANT: import the functions UNDER TEST after vi.mock calls so the mocks
// resolve before module evaluation.
import { yourFunction } from "../path/to/repository";

function setNoOrg() {
  mockCreateServerDb.mockResolvedValue({
    db: { rls: vi.fn() },
    orgId: null,
  });
}

function setRows(rows: unknown[]) {
  mockSelect.mockReturnValue({
    from: () => ({ where: () => Promise.resolve(rows) }),
  });
  mockCreateServerDb.mockResolvedValue({
    db: {
      rls: (fn: (tx: unknown) => unknown) => fn({ select: mockSelect }),
    },
    orgId: "org_test",
  });
}
```

For functions with joins, extend the fluent chain in `setRows`:

```ts
const fluentChain = {
  from: () => ({
    where: () => Promise.resolve(rows),
    innerJoin: () => ({
      leftJoin: () => ({
        where: () => Promise.resolve(rows),
      }),
    }),
  }),
};
```

For functions that issue multiple parallel queries (current period + previous period), thread a sequence:

```ts
function setRows(rows: unknown[] | unknown[][]) {
  const sequence = Array.isArray(rows[0]) ? (rows as unknown[][]) : null;
  let calls = 0;
  // ... return sequence[calls++] from the chain when sequence is set ...
}
```

## Tier 1 test shape (boilerplate per function)

```ts
describe("yourRepository - empty-org early returns", () => {
  beforeEach(() => {
    mockSelect.mockReset();
    mockCreateServerDb.mockReset();
  });

  it("yourFunction returns [] when there's no orgId", async () => {
    setNoOrg();
    await expect(yourFunction()).resolves.toEqual([]);
  });

  // Repeat for every public function.
});
```

If the function returns a non-`[]` empty shape (zero-filled object, project default constant), assert against that exact shape — don't use `toBeDefined()` or `toBeTruthy()`. The point is to **lock the contract**.

## Tier 2 test shape (per high-traffic function)

```ts
describe("yourRepository getYourBigFunction aggregation", () => {
  beforeEach(() => {
    mockSelect.mockReset();
    mockCreateServerDb.mockReset();
  });

  it("buckets rows by X, computes Y, sorts by Z desc", async () => {
    setRows([/* realistic mock rows */]);
    const result = await getYourBigFunction();
    expect(result).toEqual([/* exact expected shape */]);
  });

  it("treats null fieldX as Y so rows aren't silently dropped", async () => { /* ... */ });

  it("returns an empty array (not divide-by-zero) when there are zero rows", async () => {
    setRows([]);
    await expect(getYourBigFunction()).resolves.toEqual([]);
  });

  it("captures and rethrows when the underlying query fails", async () => {
    const boom = new Error("db on fire");
    mockSelect.mockImplementation(() => { throw boom; });
    mockCreateServerDb.mockResolvedValue({
      db: { rls: (fn: (tx: unknown) => unknown) => fn({ select: mockSelect }) },
      orgId: "org_test",
    });
    const { captureAnalyticsException } = await import("@/app/_shared/lib/sentry/captures/analytics");
    await expect(getYourBigFunction()).rejects.toBe(boom);
    expect(captureAnalyticsException).toHaveBeenCalledWith(
      boom,
      expect.objectContaining({ organizationId: "org_test", stage: expect.any(String) }),
    );
  });
});
```

## What NOT to do

- ❌ **Don't write Tier 1 tests that only assert "doesn't throw"** — `expect(fn()).resolves.toBeDefined()` is worse than no test. Assert the exact empty shape.
- ❌ **Don't skip Tier 1 for "obvious" functions.** The whole point is that they're uniform — and that uniformity is the invariant being tested.
- ❌ **Don't try to test every aggregation branch in Tier 2.** Pick 2-3 happy-path scenarios + null-handling + error capture. Edge cases beyond that should be added when a real bug surfaces them.
- ❌ **Don't mock individual Drizzle imports** (`eq`, `and`, `gte`, etc.). They're pure helpers. Mock `createServerDb` only.
- ❌ **Don't mock `@aura/database-schema`** (the table definitions). They're pure exports.
- ❌ **Don't write tests against the wrapped `repository.fnName(...)` form** — test the destructured `fnName(...)` export instead. The wrapping (`withRepositoryTiming`) is mocked away.

## Decision rule for "where does this submodule fall?"

| Symptom | Action |
|---|---|
| 0% coverage, ≤200 LOC, 1-2 public functions | Tier 1 only. ~15 min. |
| 0% coverage, >500 LOC, ≥3 public functions | Tier 1 for all + Tier 2 for top 1-2 functions. ~45 min. |
| <30% coverage, large surface | Tier 1 for any function without a dedicated test + Tier 2 only for functions you're touching this session. |
| Function is a re-exported pure helper (e.g., a color/hash util) | Test it directly (3 tests: deterministic output + collision-resistance + edge sentinel). Counts toward the submodule's coverage even though it lives in another file. |

## Reference implementations (Aura, May 2026)

- `apps/web/app/_shared/repositories/__tests__/analytics-overview.repository.test.ts` — pre-existing, more elaborate; uses RPC-row mocking. Reference for parallel-query setup.
- `apps/web/app/_shared/repositories/__tests__/analytics-funnel.repository.test.ts` (7 tests) — small submodule, deep coverage including stage-hierarchy math.
- `apps/web/app/_shared/repositories/__tests__/analytics-call-quality.repository.test.ts` (10 tests) — 5 Tier-1 empty-org tests + 2 Tier-2 happy-path functions.
- `apps/web/app/_shared/repositories/__tests__/analytics-objection.repository.test.ts` (15 tests) — 8 Tier-1 empty-org tests + 1 Tier-2 aggregation function + 3 tests for a re-exported pure helper.

Total backfill from these 3 test files: 32 tests, ~750 LOC, covered ~2,900 LOC of previously-untested repository code in under one session.

## Why this is the right shape

- **Catches the bugs that actually happen.** The signed-out / no-org early return is the single most-common edge case to break — it's the path that's least exercised in dev (you're always signed in locally) and most exercised in prod (every cron job, every webhook with no JWT, every public surface). Locking that shape catches contract drift cheaply.
- **Future-proof against refactors.** If someone renames a returned field, Tier 1 catches it immediately. Without Tier 1, the same change might silently break a route's prop typing and not surface until a user hits the page.
- **Stays maintainable.** Each Tier 1 test is 3-5 lines. Adding a new function = add one test. No ceremony, no fixture sprawl.
- **Honest about scope.** Tier 2 doesn't pretend to be exhaustive. It covers the highest-traffic paths and explicitly leaves edge cases for "next session" — and the AGENTS.md note next to the file should document which submodules are still pending deep coverage.

## When this skill does NOT apply

- **Pure utility modules** (no `createServerDb`, no DB calls) — use direct unit tests, no mock infrastructure needed.
- **React components** — use [[component-creation]] + Testing Library patterns instead.
- **Server Actions** — they have their own pattern (Zod validation + repository delegation); test those layers separately.
- **Cron jobs / Inngest functions** — those have their own integration-test pattern; Tier 1 mocking doesn't fit.
