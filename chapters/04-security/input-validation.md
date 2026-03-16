---
title: "Input Validation"
subtitle: "Zod schemas at every boundary"
chapter: 10
section: "Security"
seo_title: "Input Validation with Zod — Every Boundary, Every Time 2026"
seo_description: "Stop trusting user input. Zod schemas at every boundary — forms, server actions, webhooks, API routes. Runtime validation that generates TypeScript types."
keywords: ["input validation", "Zod", "TypeScript validation", "server actions", "form validation", "API security"]
reading_time: "9 min"
difficulty: "intermediate"
tech_stack: ["Next.js", "Supabase", "TypeScript"]
business_case: "Prevents injection attacks, data corruption, and cascading failures by rejecting bad data at the boundary — before it touches your database or business logic."
---

# Input Validation

> "TypeScript protects you from your own code. Zod protects you from everyone else's."

## The Problem

A server action receives a form submission. The TypeScript signature says the input is `CreateOrderInput`. The developer writes business logic assuming the data matches that type. It compiles. It passes tests. It ships.

Then someone opens the browser's network tab, copies the request, changes the `quantity` field from `5` to `-500`, and sends it. The application processes a negative quantity. The order total goes negative. The customer now has a credit they shouldn't have.

TypeScript types exist only at compile time. They vanish completely when the code runs. The `CreateOrderInput` type is a promise — "I intend to pass data shaped like this" — not a guarantee. In production, the data comes from the network: form submissions, API calls, webhook payloads, URL parameters. None of these are type-checked. They are raw bytes from an untrusted source, and treating them as typed data is a security vulnerability.

This isn't hypothetical. We've seen server actions that accept a `string` for a user ID and pass it directly to a database query. A crafted input containing SQL-like strings wouldn't bypass the ORM, but a UUID field containing a 10MB string would bloat the database. A `number` field containing `NaN` would poison aggregation queries. A `date` field containing `"constructor"` would cause bizarre prototype pollution in libraries that treat input as plain objects.

The surface area is enormous. Every form field, every URL parameter, every webhook payload, every API request body is an entry point. Miss one and you've created a gap between what the code expects and what the network delivers.

## The Principle

Every piece of data that crosses a trust boundary must be validated at runtime before it touches business logic. No exceptions.

Trust boundaries exist in four places: user form submissions, server action parameters, webhook payloads, and API route inputs. At each boundary, a Zod schema validates the data, rejects anything malformed, and returns a typed, narrowed result that downstream code can trust completely.

The schema is the source of truth. TypeScript types are derived from it, not the other way around. You define the shape once, validate at runtime, and get compile-time types for free.

## The Pattern

### Schema files: one per domain

Validation schemas live in a central directory, organized by domain. Each file exports schemas and the types derived from them.

```
_shared/validation/
├── orders.schema.ts       # Order creation, update, filtering
├── customers.schema.ts    # Customer creation, import
├── products.schema.ts     # Product catalog mutations
├── payments.schema.ts     # Payment processing
└── common.schema.ts       # Reusable primitives (date ranges, UUIDs, pagination)
```

### Writing schemas

A schema defines the exact shape of valid data, with human-readable error messages for every constraint:

```typescript
// _shared/validation/orders.schema.ts
import { z } from "zod";

export const createOrderSchema = z.object({
  title: z.string().min(1, "Title is required").max(200, "Title too long"),
  customer_id: z.string().uuid("Invalid customer ID"),
  priority: z.enum(["low", "medium", "high", "urgent"]),
  notes: z.string().max(5000, "Notes too long").optional(),
  items: z
    .array(
      z.object({
        product_id: z.string().uuid("Invalid product ID"),
        quantity: z.number().int().positive("Quantity must be positive"),
        unit_price_cents: z.number().int().nonnegative("Price cannot be negative"),
      })
    )
    .min(1, "At least one item required"),
});

// The type is DERIVED from the schema — never defined separately
export type CreateOrderInput = z.infer<typeof createOrderSchema>;

// Update schema reuses the creation schema with all fields optional
export const updateOrderSchema = createOrderSchema.partial().extend({
  id: z.string().uuid("Invalid order ID"),
});

export type UpdateOrderInput = z.infer<typeof updateOrderSchema>;
```

Notice: the type is derived from the schema using `z.infer`. You never write the type separately. If you change the schema, the type updates. If you forget a field in the schema, the type is missing it too — and the compiler catches every consumer.

### Server actions: validate first, always

Every server action validates input before doing anything else. The validated data is the only thing that touches the repository.

```typescript
// actions/create-order.ts
"use server";
import { revalidatePath } from "next/cache";
import { createOrderSchema } from "@/app/_shared/validation/orders.schema";
import { createOrder } from "@/app/_shared/repositories/orders.repository";
import { createClient } from "@/lib/supabase/server";

export async function createOrderAction(input: unknown) {
  // Step 1: Validate — rejects bad data before it goes anywhere
  const validation = createOrderSchema.safeParse(input);

  if (!validation.success) {
    return {
      success: false,
      error: validation.error.issues[0]?.message ?? "Invalid input",
    };
  }

  // Step 2: Use validated data — this is now provably correct
  const supabase = await createClient();
  const order = await createOrder(supabase, validation.data);

  revalidatePath("/orders");
  return { success: true, data: order };
}
```

The input parameter is typed as `unknown`, not as the schema's inferred type. This is deliberate. The TypeScript type on the parameter is a lie — the actual data comes from the network. By typing it as `unknown`, you force validation before use. The compiler won't let you access `input.title` without narrowing through Zod first.

### The validateInput helper

When every action has the same validation boilerplate, extract a helper:

```typescript
// _shared/validation/helpers.ts
import type { z } from "zod";

export function validateInput<T extends z.ZodSchema>(
  schema: T,
  input: unknown
): { success: true; data: z.infer<T> } | { success: false; error: string } {
  const result = schema.safeParse(input);
  if (!result.success) {
    const firstIssue = result.error.issues[0];
    const path = firstIssue?.path.join(".") || "input";
    const message = firstIssue?.message || "Validation failed";
    return { success: false, error: `${path}: ${message}` };
  }
  return { success: true, data: result.data };
}
```

Now every action is clean:

```typescript
export async function updateOrderAction(input: unknown) {
  const validation = validateInput(updateOrderSchema, input);
  if (!validation.success) {
    return { success: false, error: validation.error };
  }

  const supabase = await createClient();
  const order = await updateOrder(supabase, validation.data.id, validation.data);
  revalidatePath("/orders");
  return { success: true, data: order };
}
```

### Webhook payloads: validate external data aggressively

Webhook payloads come from third-party services. They change their API without telling you. They send unexpected fields. They send missing fields. Validate everything.

```typescript
const webhookPaymentSchema = z.object({
  id: z.string(),
  type: z.enum(["payment.completed", "payment.refunded", "payment.failed"]),
  created: z.number().int(),
  data: z.object({
    payment_id: z.string(),
    amount_cents: z.number().int().nonnegative(),
    currency: z.string().length(3),
    customer_email: z.string().email(),
    metadata: z.record(z.unknown()).optional(),
  }),
});

export async function POST(req: Request) {
  const body = await req.text();
  const event = verifySignature(body, req.headers);

  // Validate the payload shape — don't trust the provider
  const validation = webhookPaymentSchema.safeParse(event);
  if (!validation.success) {
    console.error("Malformed webhook payload", validation.error.flatten());
    return Response.json({ error: "Invalid payload" }, { status: 400 });
  }

  await processPaymentEvent(validation.data);
  return Response.json({ received: true });
}
```

### Graceful degradation for read queries

Not every validation failure should be an error. For read-only operations like search and filtering, fall back to sensible defaults:

```typescript
export async function getOrders(filters: unknown) {
  const validated = orderFilterSchema.safeParse(filters);

  // Bad filters? Use defaults instead of failing
  const effectiveFilters = validated.success
    ? validated.data
    : { page: 1, pageSize: 25, sortBy: "created_at" };

  return ordersRepository.list(supabase, effectiveFilters);
}
```

### Common reusable schemas

Build a library of validated primitives that compose into larger schemas:

```typescript
// _shared/validation/common.schema.ts
import { z } from "zod";

export const uuidSchema = z.string().uuid("Invalid ID format");

export const dateRangeSchema = z.object({
  from: z.coerce.date(),
  to: z.coerce.date(),
}).refine(
  (data) => data.from <= data.to,
  { message: "Start date must be before end date" }
);

export const paginationSchema = z.object({
  page: z.number().int().positive().default(1),
  pageSize: z.number().int().min(1).max(100).default(25),
});

export const sortSchema = z.object({
  sortBy: z.string(),
  sortDirection: z.enum(["asc", "desc"]).default("desc"),
});
```

These compose naturally:

```typescript
export const orderListSchema = paginationSchema
  .merge(sortSchema)
  .extend({
    dateRange: dateRangeSchema.optional(),
    status: z.enum(["pending", "confirmed", "shipped"]).optional(),
    customer_id: uuidSchema.optional(),
  });
```

## The Business Case

- **Security without thinking about security.** Every boundary rejects malformed data automatically. Negative quantities, oversized strings, invalid UUIDs, missing required fields — all caught before they reach the database. You don't need to train developers to think about input attacks. The schema does it for them.
- **Error messages users can understand.** Zod produces structured, human-readable error messages. "Title is required" and "Quantity must be positive" are messages you can show directly to users. No more "Internal Server Error" because a null value hit a NOT NULL constraint three layers deep.
- **API stability.** When your schemas are the source of truth for types, changing a field name or adding a required parameter produces compile errors everywhere that field is used. You find every call site that needs updating before the code ships.

## Try It

Install the Modh Playbook skills to enforce this pattern automatically:
```bash
# Add to your project
git submodule add https://github.com/modh-labs/playbook .agents/modh-playbook
./.agents/modh-playbook/install.sh
```
