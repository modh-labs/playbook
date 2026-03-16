---
title: "Testing Philosophy"
subtitle: "What we test and why — confidence over coverage"
chapter: 7
section: "Quality"
seo_title: "Testing Philosophy for TypeScript SaaS — Pyramid, Boundaries, Confidence — 2026"
seo_description: "A testing philosophy that prioritizes confidence over coverage: the pyramid, the boundaries, and risk-based coverage targets for modern TypeScript SaaS."
keywords: ["testing philosophy", "test pyramid", "vitest", "typescript testing", "SaaS testing strategy", "coverage targets"]
reading_time: "8 min"
difficulty: "intermediate"
tech_stack: ["Next.js", "Supabase", "TypeScript", "Vitest", "Playwright"]
business_case: "Tests that match your risk profile catch real bugs, prevent regressions, and let engineers ship with confidence — not ceremony."
---

# Testing Philosophy

> "We don't write tests to prove the code works. We write tests to prove we can change it safely."

## The Problem

Most teams fall into one of two traps. Either they test nothing and deploy on vibes, living in constant fear of regressions. Or they test everything obsessively, mocking every internal function, achieving 100% coverage of code that never breaks while leaving the real failure modes untouched.

Both traps share the same root cause: no philosophy about _what_ a test is for.

Without a testing philosophy, you get tests that are brittle, slow, and expensive to maintain. Engineers start skipping them. The suite becomes a formality nobody trusts. And when something actually breaks in production, the 4,000 green checkmarks in CI offer zero comfort.

The worst outcome is not zero tests. It is a test suite that gives you false confidence.

## The Principle

Tests exist to answer one question: **can we change this code safely?**

That question has different urgency depending on what the code does. A billing webhook that processes real money demands 100% coverage. A date formatting utility needs a few edge cases. A UI component showing a badge might not need a test at all.

We organize around three ideas:

### The Pyramid

```
        +-------------+
        |     E2E     |  10% — Critical user flows
        +-------------+
        | Integration |  20% — Real dependencies, real boundaries
        +-------------+
        |    Unit     |  70% — Fast, isolated, surgical
        +-------------+
```

Unit tests are the foundation. They are fast, cheap, and surgical. They test a single function or module in isolation. If a unit test fails, you know exactly where to look.

Integration tests verify that modules work together with real dependencies. They answer questions like: does the repository actually enforce tenant isolation? Does the payment flow create the right records?

E2E tests are expensive and slow. We reserve them for the paths where a failure costs real money or real users: checkout, authentication, the core workflow.

### Risk-Based Coverage

Not all code carries equal risk. We set coverage targets by risk level:

| Risk Level | Coverage Target | What Belongs Here |
|------------|----------------|-------------------|
| **P0 Critical** | 100% | Billing, security, data deletion, partner APIs |
| **P1 High** | 80%+ | Core business logic, repositories, server actions |
| **P2 Medium** | 60%+ | UI components, utilities, helpers |

A billing webhook with 75% coverage is a liability. A color formatting function with 75% coverage is fine.

### Boundary Testing

We test at boundaries, not at internals. A boundary is where your code meets something it does not control: a database, an external API, user input, the clock.

This means we mock the _module_, not the implementation. We never chain `.from().select().eq().single()` in a mock. We mock the repository function that wraps that query.

## The Pattern

### Unit Test: Server Action

Server actions are the boundary between the user and your business logic. Test the contract: valid input produces a result, invalid input produces an error, side effects are triggered.

```typescript
// app/(protected)/orders/_actions/__tests__/create-order.test.ts
import { describe, it, expect, vi, beforeEach, type Mock } from "vitest";

let mockCreateOrderFn: Mock;
let mockAuthFn: Mock;

vi.mock("@/repositories/orders", () => ({
  createOrder: (...args: unknown[]) => mockCreateOrderFn(...args),
}));

vi.mock("@clerk/nextjs/server", () => ({
  auth: () => mockAuthFn(),
}));

vi.mock("next/cache", () => ({
  revalidatePath: vi.fn(),
}));

import { createOrderAction } from "../create-order";

describe("createOrderAction", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mockAuthFn = vi.fn(() =>
      Promise.resolve({ userId: "user_123", orgId: "org_123" })
    );
    mockCreateOrderFn = vi.fn(() =>
      Promise.resolve({ id: "order_123", total_cents: 5000 })
    );
  });

  it("creates an order with valid input", async () => {
    const result = await createOrderAction({
      product_id: "prod_123",
      quantity: 2,
    });

    expect(result.success).toBe(true);
    expect(result.data.id).toBe("order_123");
  });

  it("rejects unauthenticated requests", async () => {
    mockAuthFn = vi.fn(() =>
      Promise.resolve({ userId: null, orgId: null })
    );

    const result = await createOrderAction({
      product_id: "prod_123",
      quantity: 1,
    });

    expect(result.success).toBe(false);
    expect(result.error).toBe("Unauthorized");
  });

  it("validates input with Zod schema", async () => {
    const result = await createOrderAction({
      product_id: "",
      quantity: -1,
    });

    expect(result.success).toBe(false);
  });
});
```

Notice what we mock: the repository module and the auth module. These are boundaries. We never mock the Supabase client internals or the Zod parser.

### Integration Test: Tenant Isolation

Integration tests verify that your security boundaries actually hold. This test uses a real database to prove that one tenant cannot see another tenant's data.

```typescript
// test/integration/orders-rls.test.ts
import { describe, it, expect, beforeEach, afterEach } from "vitest";
import { createServiceRoleClient } from "@/lib/supabase/server";

describe("orders.repository — RLS Integration", () => {
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

  it("prevents cross-tenant data access", async () => {
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

### Conditional Execution

Not every environment has every credential. Tests that need external APIs should degrade gracefully:

```typescript
const STRIPE_KEY = process.env.STRIPE_TEST_SECRET_KEY;

describe.skipIf(!STRIPE_KEY)("Stripe Integration", () => {
  it("creates a checkout session", async () => {
    const stripe = new Stripe(STRIPE_KEY!, { apiVersion: "2025-10-29.clover" });
    const session = await stripe.checkout.sessions.create({
      mode: "payment",
      line_items: [{ price: "price_test_123", quantity: 1 }],
      success_url: "https://example.com/success",
      cancel_url: "https://example.com/cancel",
    });

    expect(session.id).toMatch(/^cs_test_/);
  });
});
```

### Coverage Configuration

Configure coverage thresholds to enforce your risk profile:

```typescript
// vitest.config.ts
export default defineConfig({
  test: {
    coverage: {
      provider: "v8",
      reporter: ["text", "html"],
      thresholds: {
        statements: 70,
        branches: 60,
        functions: 70,
        lines: 70,
      },
      exclude: ["**/*.d.ts", "**/__tests__/**", "**/types/**"],
    },
  },
});
```

## The Business Case

A well-calibrated test suite pays for itself in three ways.

**Speed.** Engineers who trust the suite ship faster. They do not manually test every permutation before merging. They do not ask a teammate to "just check this looks right." The suite either passes or it does not.

**Safety.** When tests target real risk -- billing, security, data integrity -- they catch the bugs that actually cost money. A single prevented billing bug can save more than the entire engineering team's monthly salary.

**Onboarding.** New engineers read tests to understand what the code is supposed to do. A test named `"rejects unauthenticated requests"` is better documentation than a comment that says `// check auth`. Tests are living documentation that the compiler enforces.

The anti-pattern -- testing everything at the same depth -- costs roughly 3x more engineering time to maintain and catches fewer real bugs. Risk-based testing invests effort where it matters.

## Try It

```bash
npx modh-playbook init testing-philosophy
```
