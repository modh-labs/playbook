---
title: "The Repository Pattern"
subtitle: "Why we never write raw database queries"
chapter: 1
section: "Data Layer"
seo_title: "Repository Pattern for TypeScript & Supabase — Data Access Best Practices 2026"
seo_description: "Stop scattering database queries across your codebase. The repository pattern gives you type safety, testability, and a single source of truth for every entity."
keywords: ["repository pattern", "TypeScript", "Supabase", "data access layer", "type safety", "generated types"]
reading_time: "8 min"
difficulty: "intermediate"
tech_stack: ["Next.js", "Supabase", "TypeScript"]
business_case: "Eliminates an entire class of data bugs by centralizing every query behind typed, testable functions."
---

# The Repository Pattern

> "If you can grep your codebase for `.from('orders')` and find it in more than one directory, you have a ticking time bomb."

## The Problem

It starts innocently. A developer needs to fetch a list of orders for a dashboard. They write a quick Supabase query inline, selecting the five columns they need. It works. Ship it.

Three weeks later, another developer needs orders for an export feature. They write their own query, selecting a slightly different set of columns. Both work. Both ship.

Then the schema changes. The `status` column gets renamed to `fulfillment_status`. One query gets updated. The other doesn't. The export feature silently returns `null` for every order's status. No TypeScript error, no runtime exception — just wrong data flowing into a CSV that a customer hands to their accountant.

This is the quiet catastrophe of scattered queries. You don't get a crash. You get bad data. And bad data is worse than no data, because people make decisions on it.

We've seen this pattern destroy velocity on teams of every size. The codebase becomes a minefield where changing a column name means grepping through dozens of files, hoping you catch every reference. Tests pass because each test mocks its own query shape. The type system can't help because every query returns a slightly different subset of the actual row.

The worst part is that every individual query looks reasonable in isolation. It's only when you zoom out and see fifteen different files all talking to the same table with fifteen different column selections that the problem becomes obvious.

## The Principle

Every table gets exactly one file. Every query against that table lives in that file. No exceptions.

This isn't about architecture astronautics. It's about having one place to look when something breaks, one place to update when the schema changes, and one set of types that every consumer shares. Stripe does this. Linear does this. Every team that has survived a schema migration at scale does this.

The repository pattern works because it converts a distributed problem (queries scattered everywhere) into a local one (one file per entity). When a column changes, you update one file. TypeScript propagates the change to every consumer. The compiler tells you exactly what broke.

## The Pattern

### The repository file

One file per entity. Functions accept a typed database client as their first argument — this is dependency injection that lets you swap between an authenticated client and a service-role client without changing the query logic.

```typescript
// repositories/orders.repository.ts
import type { SupabaseClient } from "@supabase/supabase-js";
import type { Database } from "@/lib/supabase/database.types";

// These types are GENERATED from your schema — never hand-written
type Order = Database["public"]["Tables"]["orders"]["Row"];
type OrderInsert = Database["public"]["Tables"]["orders"]["Insert"];
type OrderUpdate = Database["public"]["Tables"]["orders"]["Update"];

export async function listOrders(
  supabase: SupabaseClient<Database>,
  filters?: { status?: string }
): Promise<Order[]> {
  let query = supabase
    .from("orders")
    .select(
      `
      *,
      customer:customers(*),
      assignee:users(*)
    `
    )
    .order("created_at", { ascending: false });

  if (filters?.status) {
    query = query.eq("status", filters.status);
  }

  const { data, error } = await query;
  if (error) throw error;
  return data || [];
}

export async function createOrder(
  supabase: SupabaseClient<Database>,
  data: OrderInsert
): Promise<Order> {
  const { data: order, error } = await supabase
    .from("orders")
    .insert(data)
    .select("*")
    .single();

  if (error) throw error;
  return order;
}

export async function updateOrder(
  supabase: SupabaseClient<Database>,
  id: string,
  updates: OrderUpdate
): Promise<Order> {
  const { data: order, error } = await supabase
    .from("orders")
    .update(updates)
    .eq("id", id)
    .select("*")
    .single();

  if (error) throw error;
  return order;
}
```

### The golden rule: always `select *`

This is non-negotiable. When you cherry-pick columns, you create a coupling between the query and every consumer's assumptions about what fields exist. When the schema changes, cherry-picked queries silently return `null` for missing fields instead of failing at compile time.

```typescript
// WRONG — this will silently break when the schema changes
const { data } = await supabase
  .from("orders")
  .select("id, title, created_at");

// RIGHT — the generated types always match reality
const { data } = await supabase
  .from("orders")
  .select("*");
```

### Using repositories from Server Actions

Server Actions call repositories. They never touch the database directly.

```typescript
// app/(protected)/orders/actions.ts
"use server";
import { createOrder } from "@/repositories/orders.repository";
import { createClient } from "@/lib/supabase/server";

export async function createOrderAction(data: OrderInsert) {
  const supabase = await createClient();
  const order = await createOrder(supabase, data);
  revalidatePath("/orders");
  return { success: true, data: order };
}
```

### Types flow from the database, never the other way

Types are generated from your schema, not hand-written. When you run type generation after a migration, every repository, every action, and every component that consumes that data gets compile-time validation for free.

```typescript
// WRONG — a hand-written interface that will drift from reality
interface CreateOrderInput {
  title: string;
  description?: string | null;
  customer_id: string;
}

// RIGHT — generated from the schema, always accurate
type CreateOrderInput =
  Database["public"]["Tables"]["orders"]["Insert"];
```

### The repository directory

```
repositories/
├── orders.repository.ts      # Order CRUD + queries
├── customers.repository.ts   # Customer CRUD + queries
├── products.repository.ts    # Product catalog
├── payments.repository.ts    # Payment records
├── users.repository.ts       # User data
└── audit.repository.ts       # Audit logs
```

Each file exports individual functions (not a class or object) for better tree-shaking. Each function accepts the database client as its first parameter for testability and flexibility.

## The Business Case

- **Zero-cost schema migrations.** Change a column, regenerate types, follow the compiler errors. No grepping, no guessing, no silent failures in production.
- **Onboarding in hours, not weeks.** New developers learn one pattern and can contribute to any entity. The repository directory is a map of the entire data model.
- **Testability without mocks.** Pass a test client to any repository function. No HTTP layer, no mock server, no fragile test fixtures.

## Try It

Install the Modh Playbook skills to enforce this pattern automatically:
```bash
# Add to your project
git submodule add https://github.com/modh-labs/playbook .agents/modh-playbook
./.agents/modh-playbook/install.sh
```
