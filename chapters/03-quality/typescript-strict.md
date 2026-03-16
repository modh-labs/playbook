---
title: "TypeScript Strict"
subtitle: "Zero any, generated types, strict mode always on"
chapter: 7
section: "Quality"
seo_title: "TypeScript Strict Mode — Zero any, Generated Types, Full Safety 2026"
seo_description: "Stop using any. Generate your types from the database. Strict mode is not optional. Here's why, and the exact configuration that makes it work."
keywords: ["TypeScript strict", "no any", "generated types", "Supabase types", "type safety", "strict mode"]
reading_time: "9 min"
difficulty: "intermediate"
tech_stack: ["Next.js", "Supabase", "TypeScript"]
business_case: "Catches entire categories of bugs at compile time — before they reach code review, before they reach staging, before they reach users."
---

# TypeScript Strict

> "Every `any` in your codebase is a bet that you'll catch the bug manually. You won't."

## The Problem

Here's a function that shipped to production at a company we worked with:

```typescript
function processOrder(data: any) {
  const total = data.items.reduce((sum, item) => sum + item.price, 0);
  return { orderId: data.id, total };
}
```

It worked perfectly for six months. Then the API changed `items` to `line_items`. No TypeScript error. No test failure — the tests mocked the old shape. The function returned `NaN` for every order's total because `undefined.reduce` doesn't throw, it just produces garbage.

The financial reports were wrong for eleven days before anyone noticed. Not because the team was negligent — because they relied on a type system that had been systematically undermined by `any`.

This is the quiet erosion of `any`. It doesn't cause crashes. It causes wrong answers. It turns TypeScript into a linter with syntax highlighting — all the ceremony of types with none of the safety. You write type annotations, you import type modules, you feel like you're doing the right thing. But the moment `any` enters the chain, the compiler stops checking everything downstream. One `any` at a function boundary infects every consumer.

And it spreads. Once a team permits `any` in one place — "just this once, the API types are complicated" — it becomes the path of least resistance everywhere. We've seen codebases where 30% of functions have `any` in their signatures. At that point, you don't have a typed language. You have JavaScript with extra steps.

The second failure mode is hand-written types. A developer looks at the database schema and writes an interface:

```typescript
interface Order {
  id: string;
  title: string;
  status: string;
  created_at: string;
}
```

This matches the schema today. Next month, `status` becomes an enum. The month after, `total_cents` gets added. The interface doesn't update. The application continues to compile, but it's operating on a fiction — a type that describes a table that no longer exists.

## The Principle

Types must come from the source of truth, and the compiler must be merciless.

This means three things: strict mode in every `tsconfig.json`, zero `any` types anywhere in the codebase, and all database types generated from the schema — never hand-written. These aren't aspirational goals. They're configuration settings. There's no reason not to enable them on day one, and there's no justification for disabling them later.

## The Pattern

### The tsconfig: strict means strict

```json
{
  "compilerOptions": {
    "strict": true,
    "noUncheckedIndexedAccess": true,
    "noImplicitAny": true,
    "strictNullChecks": true,
    "noImplicitReturns": true
  }
}
```

`strict: true` enables a family of checks: no implicit `any`, strict null checks, strict function types, strict property initialization. Each one catches a different class of bug. Together, they make the compiler an exhaustive code reviewer that never gets tired and never misses an edge case.

`noUncheckedIndexedAccess` is the one most teams miss. It forces you to handle the case where an array access or object lookup returns `undefined`:

```typescript
const items = ["apple", "banana", "cherry"];

// Without noUncheckedIndexedAccess — compiles, crashes at runtime
const first: string = items[0]; // Actually might be undefined

// With noUncheckedIndexedAccess — forces the check
const first = items[0]; // Type is string | undefined
if (first) {
  console.log(first.toUpperCase()); // Now safe
}
```

### Generated types: the database is the source of truth

When your database schema changes, your types must change with it. The only way to guarantee this is to generate types directly from the schema.

```bash
# Generate types from your Supabase schema
npx supabase gen types typescript --local > lib/supabase/database.types.ts
```

This produces a single file with the complete type for every table, view, and function in your database. Every row type, every insert type, every update type — generated, accurate, and impossible to forget.

```typescript
// Generated — always matches the actual schema
import type { Database } from "@/lib/supabase/database.types";

type Order = Database["public"]["Tables"]["orders"]["Row"];
type OrderInsert = Database["public"]["Tables"]["orders"]["Insert"];
type OrderUpdate = Database["public"]["Tables"]["orders"]["Update"];
```

When you add a column, you regenerate. When you change a type, you regenerate. The compiler immediately tells you everywhere the change matters.

```typescript
// WRONG — will drift from reality within weeks
interface Order {
  id: string;
  title: string;
  status: string;
  created_at: string;
}

// RIGHT — generated from the schema, always accurate
type Order = Database["public"]["Tables"]["orders"]["Row"];
```

### Re-export with better names

Generated types have verbose paths. Create a types file per entity that re-exports with cleaner names:

```typescript
// _shared/types/orders.types.ts
import type { Database } from "@/lib/supabase/database.types";

export type Order = Database["public"]["Tables"]["orders"]["Row"];
export type OrderInsert = Database["public"]["Tables"]["orders"]["Insert"];
export type OrderUpdate = Database["public"]["Tables"]["orders"]["Update"];

// Derived types built from the generated base
export type OrderWithCustomer = Order & {
  customer: Database["public"]["Tables"]["customers"]["Row"];
};

export type OrderStatus = "pending" | "confirmed" | "shipped" | "delivered";
```

Every component, every action, every repository imports from this file. One place to look. One place to update.

### The zero-any enforcement

When you encounter truly unknown data — a webhook payload, an API response, user input — use `unknown`, not `any`. The difference is absolute: `any` disables type checking, `unknown` forces narrowing.

```typescript
// WRONG — any disables all checking downstream
function processWebhookPayload(data: any) {
  return data.order.id; // No error, even if order doesn't exist
}

// RIGHT — unknown forces you to prove the shape
function processWebhookPayload(data: unknown) {
  const parsed = webhookSchema.parse(data); // Zod validates at runtime
  return parsed.order.id; // Now type-safe
}
```

For third-party libraries that return `any`, wrap them immediately:

```typescript
// The library returns any — contain it at the boundary
import { externalApiCall } from "some-sdk";

async function fetchOrderFromPartner(id: string): Promise<Order> {
  const raw: unknown = await externalApiCall(id);
  return partnerOrderSchema.parse(raw);
}
```

The `any` never escapes the boundary. Everything downstream is typed.

### Zod schemas: runtime validation that generates types

Zod bridges the gap between compile-time types and runtime reality. Define the schema once, infer the type from it:

```typescript
// _shared/validation/orders.schema.ts
import { z } from "zod";

export const createOrderSchema = z.object({
  title: z.string().min(1, "Title is required").max(200),
  customer_id: z.string().uuid("Invalid customer ID"),
  items: z.array(
    z.object({
      product_id: z.string().uuid(),
      quantity: z.number().int().positive(),
    })
  ).min(1, "At least one item required"),
});

// The type is DERIVED from the schema — never defined separately
export type CreateOrderInput = z.infer<typeof createOrderSchema>;
```

Now validation and types cannot drift. Change the schema, the type updates. Add a field to the schema, every consumer gets a compile error until they provide it.

### Import conventions

Use `import type` for type-only imports. This makes the boundary between values and types explicit, and it helps bundlers eliminate type-only code:

```typescript
// Type-only — stripped at compile time
import type { Order, OrderWithCustomer } from "@/app/_shared/types/orders.types";
import type { Database } from "@/lib/supabase/database.types";

// Value imports — included in the bundle
import { createOrderSchema } from "@/app/_shared/validation/orders.schema";
import { createClient } from "@/lib/supabase/server";
```

### Function signatures: be explicit

Every exported function gets an explicit return type. This prevents accidental API changes — if the implementation changes the return shape, the compiler catches it before the consumer does.

```typescript
// Explicit return type — the contract is visible and enforced
export async function listOrders(
  supabase: SupabaseClient<Database>,
  filters?: { status?: OrderStatus }
): Promise<Order[]> {
  const { data, error } = await supabase
    .from("orders")
    .select("*")
    .order("created_at", { ascending: false });

  if (error) throw error;
  return data ?? [];
}
```

## The Business Case

- **Bugs caught before code review.** Strict mode catches null reference errors, missing fields, type mismatches, and unchecked array accesses at compile time. These are the bugs that waste the most time in QA because they're intermittent and hard to reproduce.
- **Schema migrations without fear.** When a column changes, regenerate types and follow the red lines. The compiler shows you every file that needs updating. No grepping, no guessing, no silent failures that surface weeks later in a financial report.
- **Onboarding velocity.** New developers trust the types. They can navigate the codebase by following type definitions instead of reading implementation details. The type system becomes documentation that is always up to date.

## Try It

Install the Modh Playbook skills to enforce this pattern automatically:
```bash
# Add to your project
git submodule add https://github.com/modh-labs/playbook .agents/modh-playbook
./.agents/modh-playbook/install.sh
```
