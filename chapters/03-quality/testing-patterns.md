---
title: "Testing Patterns"
subtitle: "Factories, mocking, and integration tests that prove it works"
chapter: 8
section: "Quality"
seo_title: "Testing Patterns — Factories, Mocking, Integration Tests for TypeScript SaaS — 2026"
seo_description: "Production-grade testing patterns: type-safe factories, boundary mocking, and integration tests that verify real behavior in multi-tenant TypeScript apps."
keywords: ["test factories", "mocking patterns", "integration tests", "vitest", "TypeScript testing", "faker.js", "MSW"]
reading_time: "10 min"
difficulty: "intermediate"
tech_stack: ["Next.js", "Supabase", "TypeScript", "Vitest", "Faker.js", "MSW"]
business_case: "Consistent test patterns eliminate flaky tests, reduce onboarding time for new engineers, and let teams ship tested code without reinventing scaffolding for every feature."
---

# Testing Patterns

> "A test is only as good as the data it tests against and the boundaries it respects."

## The Problem

You have a testing philosophy. You know what to test and why. Now you sit down to write the test and immediately hit three walls.

**Wall one: test data.** You need an order object with 14 required fields. You hand-craft one, miss the `updated_at` timestamp, and spend 20 minutes debugging a type error that has nothing to do with what you are testing.

**Wall two: mocking.** You mock the database client by chaining `.from().select().eq().single()`. Next month, someone refactors the query to use `.maybeSingle()` and your test breaks even though the behavior did not change.

**Wall three: integration confidence.** Your unit tests pass. Your mocks are clean. You deploy. And the feature is broken because the database policy rejects the query. No test ever ran against a real database.

These are not test failures. They are pattern failures. The right patterns make tests easy to write, easy to read, and hard to break.

## The Principle

Three patterns solve these three walls:

**Factories** generate realistic, type-safe test data. You override only what matters. The factory handles the rest.

**Boundary mocking** replaces entire modules at import boundaries, never internal implementation chains. When the internals change, the mocks stay stable.

**Integration tests** run against real dependencies to verify what mocks cannot: that your database policies, API contracts, and cascading behaviors actually work.

These patterns are complementary. Factories feed both unit and integration tests. Boundary mocks keep unit tests fast. Integration tests verify the assumptions that mocks encode.

## The Pattern

### Factories: Type-Safe Test Data

A factory is a function that returns a complete, valid entity with sensible defaults. You override only the fields your test cares about.

```typescript
// test/factories/orders.factory.ts
import { faker } from "@faker-js/faker";
import type { Database } from "@your-org/database-types";

type OrderRow = Database["public"]["Tables"]["orders"]["Row"];
type OrderInsert = Database["public"]["Tables"]["orders"]["Insert"];

const TEST_ORG_ID = "org_test_123";

export function createTestOrder(overrides: Partial<OrderInsert> = {}): OrderRow {
  const now = new Date().toISOString();
  return {
    id: faker.string.uuid(),
    organization_id: TEST_ORG_ID,
    customer_email: faker.internet.email(),
    total_cents: faker.number.int({ min: 100, max: 100000 }),
    currency: "usd",
    status: "pending",
    created_at: now,
    updated_at: now,
    ...overrides,
  };
}
```

The key discipline: **override only what is relevant to the test.**

```typescript
// Testing order status transitions — only status matters
const pendingOrder = createTestOrder({ status: "pending" });
const fulfilledOrder = createTestOrder({ status: "fulfilled" });

// Testing price calculations — only amount matters
const cheapOrder = createTestOrder({ total_cents: 500 });
const expensiveOrder = createTestOrder({ total_cents: 999900 });
```

Contrast this with the anti-pattern:

```typescript
// Every field specified — impossible to tell what this test is about
const order = {
  id: "order_123",
  organization_id: "org_123",
  customer_email: "test@example.com",
  total_cents: 5000,
  currency: "usd",
  status: "pending",
  created_at: "2026-01-15T10:00:00Z",
  updated_at: "2026-01-15T10:00:00Z",
};
```

When every field is specified, nothing stands out. The reader cannot tell which field the test actually cares about.

### Builder Pattern for Complex Scenarios

When entities have relationships, a builder pattern lets you compose test data with fluent syntax:

```typescript
// test/factories/orders.factory.ts
import { createTestCustomer } from "./customers.factory";
import { createTestProduct } from "./products.factory";

export class OrderBuilder {
  private data: Partial<OrderRow> = {};
  private customer?: CustomerRow;

  withCustomer(customer?: CustomerRow) {
    this.customer = customer ?? createTestCustomer();
    this.data.customer_id = this.customer.id;
    return this;
  }

  withStatus(status: "pending" | "fulfilled" | "cancelled") {
    this.data.status = status;
    return this;
  }

  withAmount(cents: number) {
    this.data.total_cents = cents;
    return this;
  }

  build(): OrderRow {
    return createTestOrder(this.data);
  }

  buildWithCustomer(): { order: OrderRow; customer: CustomerRow } {
    const customer = this.customer ?? createTestCustomer();
    this.data.customer_id = customer.id;
    return { order: this.build(), customer };
  }
}

// Usage
const { order, customer } = new OrderBuilder()
  .withCustomer()
  .withStatus("fulfilled")
  .withAmount(15000)
  .buildWithCustomer();

expect(order.customer_id).toBe(customer.id);
```

### Centralized Test Constants

Shared values prevent magic strings from scattering across tests:

```typescript
// test/factories/common.ts
export const TEST_ORG_ID = "org_test_123";
export const TEST_USER_ID = "user_test_123";
export const TEST_ADMIN_EMAIL = "admin@test.example.com";
```

### Boundary Mocking

The core principle: **mock at module boundaries, not internal implementation.**

This means you mock the repository function, not the database query chain. You mock the auth module, not the JWT verification internals.

```typescript
// The pattern that works with Bun's Vitest runner
import { describe, it, expect, vi, beforeEach, type Mock } from "vitest";

// 1. Declare mock variables
let mockGetOrderFn: Mock;
let mockUpdateOrderFn: Mock;

// 2. Set up vi.mock with inline factory
vi.mock("@/repositories/orders", () => ({
  getOrderById: (...args: unknown[]) => mockGetOrderFn(...args),
  updateOrder: (...args: unknown[]) => mockUpdateOrderFn(...args),
}));

// 3. Import AFTER mocks are declared
import { fulfillOrder } from "../fulfill-order";

describe("fulfillOrder", () => {
  // 4. Initialize mocks in beforeEach
  beforeEach(() => {
    vi.clearAllMocks();
    mockGetOrderFn = vi.fn(() =>
      Promise.resolve({
        id: "order_123",
        status: "pending",
        total_cents: 5000,
      })
    );
    mockUpdateOrderFn = vi.fn(() =>
      Promise.resolve({ id: "order_123", status: "fulfilled" })
    );
  });

  it("transitions order to fulfilled", async () => {
    const result = await fulfillOrder("order_123");

    expect(result.status).toBe("fulfilled");
    expect(mockUpdateOrderFn).toHaveBeenCalledWith(
      expect.any(Object),
      "order_123",
      expect.objectContaining({ status: "fulfilled" })
    );
  });

  // 5. Override for specific test scenarios
  it("rejects already-fulfilled orders", async () => {
    mockGetOrderFn = vi.fn(() =>
      Promise.resolve({ id: "order_123", status: "fulfilled" })
    );

    const result = await fulfillOrder("order_123");

    expect(result.success).toBe(false);
    expect(result.error).toContain("already fulfilled");
  });
});
```

Compare this with the anti-pattern -- mocking the database client internals:

```typescript
// NEVER DO THIS: brittle, breaks when query implementation changes
vi.mock("@/lib/supabase/server", () => ({
  createClient: vi.fn().mockResolvedValue({
    from: vi.fn().mockReturnValue({
      select: vi.fn().mockReturnValue({
        eq: vi.fn().mockReturnValue({
          single: vi.fn().mockResolvedValue({ data: { id: "123" } }),
        }),
      }),
    }),
  }),
}));
```

If someone changes `.single()` to `.maybeSingle()`, or adds a `.order()` clause, this mock shatters. Boundary mocking does not care about those changes because it operates at a higher abstraction.

### Common Mock Recipes

**Authentication:**

```typescript
let mockAuthFn: Mock;

vi.mock("@clerk/nextjs/server", () => ({
  auth: () => mockAuthFn(),
}));

beforeEach(() => {
  mockAuthFn = vi.fn(() =>
    Promise.resolve({ userId: "user_123", orgId: "org_123" })
  );
});

// Test unauthenticated scenario
it("rejects unauthenticated users", async () => {
  mockAuthFn = vi.fn(() =>
    Promise.resolve({ userId: null, orgId: null })
  );

  const result = await protectedAction();
  expect(result.error).toBe("Unauthorized");
});
```

**External APIs (Stripe, payment processors):**

```typescript
let mockCheckoutFn: Mock;

vi.mock("stripe", () => ({
  default: vi.fn().mockImplementation(() => ({
    checkout: {
      sessions: {
        create: (...args: unknown[]) => mockCheckoutFn(...args),
      },
    },
  })),
}));

beforeEach(() => {
  mockCheckoutFn = vi.fn(() =>
    Promise.resolve({ id: "cs_test_123", url: "https://checkout.example.com" })
  );
});
```

**Network-level mocking with MSW** for components that make HTTP requests:

```typescript
// test/mocks/handlers/payments.ts
import { http, HttpResponse } from "msw";

export const paymentHandlers = [
  http.get("https://api.payment-provider.com/v1/charges/:id", () => {
    return HttpResponse.json({
      id: "ch_123",
      amount: 5000,
      status: "succeeded",
    });
  }),
];

// test/mocks/server.ts
import { setupServer } from "msw/node";
import { paymentHandlers } from "./handlers/payments";

export const server = setupServer(...paymentHandlers);

// vitest.setup.ts
beforeAll(() => server.listen());
afterEach(() => server.resetHandlers());
afterAll(() => server.close());
```

### Integration Tests That Prove It Works

Integration tests use real dependencies. They are slower, require credentials, and must clean up after themselves. They are also the only way to verify behaviors that mocks cannot simulate: database policies, cascading deletes, API contract compatibility.

**Testing tenant isolation with a real database:**

```typescript
// test/integration/orders-rls.test.ts
import { describe, it, expect, beforeEach, afterEach } from "vitest";

describe("Orders — RLS Integration", () => {
  let supabase: SupabaseClient;
  let tenantA: string;
  let tenantB: string;

  beforeEach(async () => {
    supabase = await createServiceRoleClient();
    tenantA = `org_test_a_${Date.now()}`;
    tenantB = `org_test_b_${Date.now()}`;
  });

  afterEach(async () => {
    await supabase
      .from("orders")
      .delete()
      .in("organization_id", [tenantA, tenantB]);
  });

  it("enforces tenant isolation — cross-org queries return empty", async () => {
    await supabase.from("orders").insert({
      organization_id: tenantA,
      total_cents: 5000,
      status: "pending",
    });

    const { data } = await supabase
      .from("orders")
      .select("*")
      .eq("organization_id", tenantB);

    expect(data).toHaveLength(0);
  });
});
```

**Testing cascading deletes (data deletion compliance):**

```typescript
describe("Customer deletion — Integration", () => {
  it("deletes all associated data", async () => {
    const supabase = await createServiceRoleClient();
    const testOrgId = `org_deletion_${Date.now()}`;

    // Create customer with related records
    const { data: customer } = await supabase
      .from("customers")
      .insert({
        organization_id: testOrgId,
        email: "delete-me@test.com",
        name: "Delete Me",
      })
      .select()
      .single();

    await supabase.from("orders").insert({
      organization_id: testOrgId,
      customer_id: customer.id,
      total_cents: 3000,
    });

    // Perform deletion
    await deleteCustomerData(customer.id, "Customer request");

    // Verify complete removal
    const { data: customerCheck } = await supabase
      .from("customers")
      .select()
      .eq("id", customer.id)
      .maybeSingle();
    expect(customerCheck).toBeNull();

    const { data: ordersCheck } = await supabase
      .from("orders")
      .select()
      .eq("customer_id", customer.id);
    expect(ordersCheck).toHaveLength(0);
  });
});
```

**Graceful degradation when credentials are missing:**

```typescript
const STRIPE_KEY = process.env.STRIPE_TEST_SECRET_KEY;

describe.skipIf(!STRIPE_KEY)("Stripe Integration", () => {
  let stripe: Stripe;

  beforeAll(() => {
    stripe = new Stripe(STRIPE_KEY!, { apiVersion: "2025-10-29.clover" });
  });

  it("creates and cleans up a test customer", async () => {
    const customer = await stripe.customers.create({
      email: `integration_test_${Date.now()}@test.com`,
      metadata: { test: "true" },
    });

    expect(customer.id).toMatch(/^cus_/);

    await stripe.customers.del(customer.id);
  });
});
```

Tests that need missing credentials skip gracefully instead of failing the entire suite.

## The Business Case

**Onboarding speed.** When every test file follows the same patterns -- factories for data, boundary mocks for dependencies, integration tests for real verification -- a new engineer can write their first test in 30 minutes instead of 3 hours. They copy the pattern, change the names, and it works.

**Maintenance cost.** Boundary mocking means that refactoring a repository query does not break 40 action tests. Only the repository's own tests need updating. Teams that mock at implementation boundaries spend roughly 60% less time fixing broken tests after internal refactors.

**Deployment confidence.** Integration tests that verify tenant isolation, cascading deletes, and API contracts catch the class of bugs that unit tests structurally cannot. These are the bugs that cause data leaks, billing errors, and compliance violations -- the bugs with six-figure consequences.

**Flake rate.** Consistent patterns produce consistent results. Teams that standardize on factories and boundary mocking report near-zero flaky tests, because the mocks are deterministic and the test data is generated fresh for each run.

## Try It

```bash
npx modh-playbook init testing-patterns
```
