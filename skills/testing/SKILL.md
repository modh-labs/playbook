---
name: testing
description: >
  Create tests following Vitest and Playwright patterns. Use when writing
  unit tests, integration tests, mocking Supabase, testing server actions,
  or running test suites. Enforces __tests__ directories, repository mocking,
  and test data cleanup.
---

# Testing Patterns Skill

## When This Skill Activates

- Writing or modifying test files (`*.test.ts`, `*.test.tsx`)
- Creating mocks for database clients, repositories, or services
- Discussing testing strategy or coverage
- Running test suites

---

## Commands

```bash
bun test          # Watch mode (re-run on changes)
bun test:ci       # Single run (CI mode)
bun test:ui       # Interactive UI
bun test:e2e      # Playwright headed mode
bun ci            # Full pipeline (lint + typecheck + tests)
```

---

## Test Organization

Tests use `__tests__/` directories colocated next to source code:

```
app/orders/actions/
  process-order.ts
  __tests__/
    process-order.test.ts
    cancel-order.test.ts
```

### Naming Convention

| Type | Pattern | Example |
|------|---------|---------|
| Unit test | `*.test.ts` | `orders.test.ts` |
| Integration test | `*-integration.test.ts` | `orders-integration.test.ts` |
| E2E test | `*.e2e.test.ts` | `checkout.e2e.test.ts` |

---

## 4 Testing Patterns

### Pattern 1: Unit Test Repository (Mock Database Client)

Test repository logic in isolation with a mocked database client:

```typescript
import { describe, it, expect, beforeEach } from "vitest";
import { createMockSupabaseClient } from "@/test/mocks/supabase.mock";
import { createOrder } from "../orders.repository";

describe("orders.repository", () => {
  let mockDb: ReturnType<typeof createMockSupabaseClient>;

  beforeEach(() => {
    mockDb = createMockSupabaseClient();
  });

  it("should create an order", async () => {
    mockDb._chain.insert.mockReturnValue(mockDb._chain);
    mockDb._chain.select.mockReturnValue(mockDb._chain);
    mockDb._chain.single.mockResolvedValue({
      data: { id: "order_123", amount: 1000 },
      error: null,
    });

    const result = await createOrder(mockDb as any, {
      item_id: "item_456",
      amount: 1000,
    });

    expect(result.amount).toBe(1000);
    expect(mockDb.from).toHaveBeenCalledWith("orders");
  });
});
```

### Pattern 2: Integration Test Repository (Real Database)

Test against a real database for RLS, constraints, and indexes:

```typescript
describe("orders.repository (integration)", () => {
  let supabase: Awaited<ReturnType<typeof createServiceRoleClient>>;
  let testOrgId: string;

  beforeEach(async () => {
    supabase = await createServiceRoleClient();
    testOrgId = `test_org_${Date.now()}`;
  });

  afterEach(async () => {
    // Always clean up test data
    await supabase.from("orders").delete().eq("organization_id", testOrgId);
  });

  it("should create and retrieve orders", async () => {
    const order = await createOrder(supabase, {
      organization_id: testOrgId,
      amount: 1000,
    });
    expect(order.id).toBeDefined();
  });
});
```

### Pattern 3: Unit Test Server Action (Mock Repositories)

Mock at the repository boundary -- never mock internal functions:

```typescript
import { vi } from "vitest";
import * as ordersRepository from "@/lib/repositories/orders.repository";

vi.mock("@/lib/repositories/orders.repository", () => ({
  updateOrderStatus: vi.fn(),
}));

describe("updateOrderStatusAction", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it("should update order status", async () => {
    vi.spyOn(ordersRepository, "updateOrderStatus").mockResolvedValue(undefined);

    const result = await updateOrderStatusAction({
      orderId: "order_123",
      status: "shipped",
    });
    expect(result.success).toBe(true);
  });
});
```

### Pattern 4: Integration Test Server Action (Real Repositories)

Full flow with actual database:

```typescript
describe("updateOrderStatusAction (integration)", () => {
  // Setup real test data in beforeEach
  // Clean up in afterEach
  // Test the full action -> repository -> database flow
});
```

---

## Core Rules

### DO

| Rule | Why |
|------|-----|
| Use `__tests__/` directory next to source code | Easy to find tests for any file |
| Mock at repository boundary for action tests | Tests business logic, not DB details |
| Use `createMockSupabaseClient` from test helpers | Consistent mock behavior across tests |
| Clean up test data in `afterEach` | Prevents flaky tests from leftover data |
| Use unique test IDs (`test_org_${Date.now()}`) | Parallel test isolation |
| `beforeEach` with `vi.clearAllMocks()` | Fresh mocks for each test |
| Mock env vars before dynamic imports | Environment-dependent code loads correctly |

### DON'T

| Rule | Why |
|------|-----|
| Use database client directly in tests | Use repositories instead |
| Mock internal functions | Mock at boundaries (repositories, external APIs) |
| Mix unit and integration tests in same describe | Different setup/teardown needs |
| Skip cleanup | Causes flaky tests in CI |
| Hardcode test data | Use unique IDs or faker for isolation |

---

## Mocking Patterns

### Universal Server Action Test Template

Follow this exact structure for every server action test file. The key insight: **hoist mocks before `vi.mock` calls**, and **import the action AFTER all mocks are registered**.

```typescript
import { beforeEach, describe, expect, it, vi } from "vitest";

// 1. Hoist mocks (these run BEFORE vi.mock factory functions)
const mockAuth = vi.hoisted(() =>
  vi.fn(() => Promise.resolve({
    userId: "user_test_123",
    orgId: "org_test_456",
    orgRole: "org:admin",
  } as Record<string, unknown>)),
);
const mockRepository = vi.hoisted(() => vi.fn());

// 2. Mock dependencies (order matters)
vi.mock("@/lib/auth", () => ({ auth: mockAuth }));
vi.mock("@/lib/traced-action", () => ({
  tracedAction: (_name: string, fn: unknown) => fn,
}));
vi.mock("@/lib/captures/domain", () => ({
  captureDomainException: vi.fn(),
}));
vi.mock("@/lib/logger", () => ({
  createModuleLogger: () => ({
    info: vi.fn(), warn: vi.fn(), error: vi.fn(), debug: vi.fn(),
  }),
}));
vi.mock("next/cache", () => ({
  revalidatePath: vi.fn(),
  revalidateTag: vi.fn(),
}));

// 3. Import AFTER mocks (dynamic resolution picks up mocked modules)
import { actionUnderTest } from "../action-file";

// 4. Structured test body
describe("actionUnderTest", () => {
  beforeEach(() => { vi.clearAllMocks(); });

  describe("auth", () => {
    it("returns error when unauthorized", async () => {
      mockAuth.mockResolvedValueOnce({ userId: null, orgId: null });
      const result = await actionUnderTest({ id: "123" });
      expect(result.error).toBeDefined();
    });
  });

  describe("validation", () => {
    it("returns error for invalid input", async () => {
      const result = await actionUnderTest({ id: "" });
      expect(result.error).toBeDefined();
    });
  });

  describe("happy path", () => {
    it("succeeds with valid input", async () => {
      mockRepository.mockResolvedValueOnce({ id: "123", status: "active" });
      const result = await actionUnderTest({ id: "123" });
      expect(result.success).toBe(true);
    });
  });

  describe("error handling", () => {
    it("captures domain exception on DB error", async () => {
      mockRepository.mockRejectedValueOnce(new Error("DB timeout"));
      const result = await actionUnderTest({ id: "123" });
      expect(result.success).toBe(false);
    });
  });
});
```

**Key rules:**
- Use `as Record<string, unknown>` on auth mock returns to avoid type conflicts with auth provider types
- Always mock `tracedAction` to pass through the function (no tracing in tests)
- Always mock domain capture functions (prevent Sentry calls in tests)
- Every test file has 4 describe blocks: auth, validation, happy path, error handling

### Mock Database Client (Supabase)

See `references/mock-patterns.md` for the full mock implementation.

```typescript
import { createMockSupabaseClient } from "@/test/mocks/supabase.mock";

const mockDb = createMockSupabaseClient();

// Mock a query chain: from() -> select() -> eq() -> single()
mockDb._chain.select.mockReturnValue(mockDb._chain);
mockDb._chain.eq.mockReturnValue(mockDb._chain);
mockDb._chain.single.mockResolvedValue({
  data: { id: "123", name: "Test" },
  error: null,
});
```

### Mock External APIs

```typescript
vi.mock("@/lib/external/payment-api", () => ({
  chargeCustomer: vi.fn(),
  refundPayment: vi.fn(),
}));
```

### Mock Environment Variables

```typescript
beforeEach(() => {
  vi.stubEnv("API_KEY", "test_key_123");
  vi.stubEnv("WEBHOOK_SECRET", "test_secret");
});

afterEach(() => {
  vi.unstubAllEnvs();
});
```

### Common Mock Mistakes

| Mistake | Fix |
|---------|-----|
| Importing action before `vi.mock` | Use `vi.hoisted()` + import after mocks |
| Missing `tracedAction` mock | Tracing wrapper calls error tracker on errors |
| Missing `captureException` mock | Domain capture tries to call error tracker |
| Auth mock returns typed object | Use `as Record<string, unknown>` to avoid type conflicts |
| Not clearing mocks between tests | Always `vi.clearAllMocks()` in `beforeEach` |

---

## Playwright E2E Patterns

> For the full guide on semantic locators, accessible UI patterns, flaky test elimination, and Page Object fixtures, see the [`e2e-testability`](../e2e-testability/) skill.

### Key Rules (Summary)

1. **Use `getByRole` first** — not CSS selectors or `data-testid`
2. **Wait for data presence**, not loading-state absence
3. **No `page.waitForTimeout()`** — use web-first assertions
4. **Extract repeated setup** into Page Object fixtures

### Page Object Pattern

```typescript
// tests/pages/checkout.page.ts
export class CheckoutPage {
  constructor(private page: Page) {}

  async fillShippingAddress(address: Address) {
    await this.page.getByLabel('Street').fill(address.street);
    await this.page.getByLabel('City').fill(address.city);
  }

  async submitOrder() {
    await this.page.getByRole('button', { name: 'Submit Order' }).click();
    await this.page.waitForURL(/\/confirmation/);
  }
}
```

### E2E Test Structure

```typescript
import { test, expect } from "@playwright/test";
import { CheckoutPage } from "./pages/checkout.page";

test("user can complete checkout", async ({ page }) => {
  const checkout = new CheckoutPage(page);

  await page.goto("/checkout");
  await checkout.fillShippingAddress({ street: "123 Main", city: "Portland" });
  await checkout.submitOrder();

  await expect(page).toHaveURL(/\/confirmation/);
  await expect(page.getByRole('heading', { name: /Order Confirmed/ })).toBeVisible();
});
```

---

## Quick Reference

| Pattern | Mock What | Test What |
|---------|-----------|-----------|
| Unit repo | Database client | Query building, error handling |
| Integration repo | Nothing (real DB) | RLS, constraints, data flow |
| Unit action | Repository functions | Business logic, validation |
| Integration action | Nothing (real DB) | Full flow end-to-end |

---

## Detailed References

- Database client mock implementation: `references/mock-patterns.md`
