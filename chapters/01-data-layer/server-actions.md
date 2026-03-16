---
title: "Server Actions"
subtitle: "Type-safe mutations that just work"
chapter: 2
section: "Data Layer"
seo_title: "Next.js Server Actions — Type-Safe Mutations Best Practices 2026"
seo_description: "Replace API routes with Server Actions for internal mutations. Get end-to-end type safety, automatic cache invalidation, and zero HTTP boilerplate."
keywords: ["server actions", "Next.js", "mutations", "type safety", "cache invalidation", "Zod validation"]
reading_time: "7 min"
difficulty: "intermediate"
tech_stack: ["Next.js", "Supabase", "TypeScript"]
business_case: "Cuts mutation boilerplate by 60% while eliminating an entire category of serialization and validation bugs."
---

# Server Actions

> "Every API route you write for internal use is a tax on your future self."

## The Problem

Here's a pattern we've all written. A React component needs to create an order. So we build an API route: parse the body, validate it, call the database, serialize the response. Then we build a client-side fetch: serialize the data, handle the loading state, parse the response, handle errors, invalidate the cache, refresh the UI. Two files, fifty lines of boilerplate, and a type boundary where TypeScript can't help you.

Now multiply that by every mutation in your application. Create, update, delete, archive, restore, duplicate, assign, unassign. Each one needs an API route, a fetch call, error handling on both sides, and manual type alignment between what the server sends and what the client expects.

The real cost isn't the boilerplate — it's the bugs that live in the seams. The API route returns `{ data: order }` but the client expects `{ order }`. The server throws a validation error as a 400, but the client only checks for network errors. The mutation succeeds but the UI doesn't refresh because someone forgot to invalidate the cache.

We spent years building elaborate client-side data fetching layers — React Query, SWR, custom hooks — to manage the complexity that we created by putting an HTTP boundary between our UI and our server code. Server Actions remove the boundary entirely.

## The Principle

If the mutation originates from your own UI, it should be a function call, not an HTTP request.

Server Actions are functions that run on the server but can be called directly from client components. No API route, no fetch, no serialization. TypeScript types flow end-to-end. Errors propagate naturally. The function signature is the API contract, enforced by the compiler.

API routes still exist for one purpose: receiving webhooks from external services. Everything else is a Server Action.

## The Pattern

### The standard Server Action

Actions live in an `actions.ts` file colocated with the route that uses them. They call repositories for data access and handle cache invalidation before returning.

```typescript
// app/(protected)/orders/actions.ts
"use server";

import { createOrder, updateOrder } from "@/repositories/orders.repository";
import { createClient } from "@/lib/supabase/server";
import { revalidatePath } from "next/cache";

export async function createOrderAction(data: OrderInsert) {
  try {
    const supabase = await createClient();
    const order = await createOrder(supabase, data);
    revalidatePath("/orders");
    return { success: true as const, data: order };
  } catch (error) {
    return {
      success: false as const,
      error: error instanceof Error ? error.message : "Unknown error",
    };
  }
}

export async function updateOrderStatusAction(
  id: string,
  status: OrderStatus
) {
  try {
    const supabase = await createClient();
    const order = await updateOrder(supabase, id, { status });
    revalidatePath("/orders");
    return { success: true as const, data: order };
  } catch (error) {
    return {
      success: false as const,
      error: error instanceof Error ? error.message : "Unknown error",
    };
  }
}
```

### Calling from client components

No fetch. No loading state hook. Just `useTransition` and a direct function call.

```typescript
// app/(protected)/orders/components/OrderForm.tsx
"use client";
import { useTransition } from "react";
import { createOrderAction } from "../actions";

export function OrderForm() {
  const [isPending, startTransition] = useTransition();

  async function handleSubmit(formData: FormData) {
    startTransition(async () => {
      const result = await createOrderAction({
        title: formData.get("title") as string,
        customer_id: formData.get("customer_id") as string,
      });

      if (result.success) {
        // Navigate, show toast, etc.
      } else {
        // Show error — result.error is typed
      }
    });
  }

  return (
    <form action={handleSubmit}>
      {/* form fields */}
      <button type="submit" disabled={isPending}>
        {isPending ? "Creating..." : "Create Order"}
      </button>
    </form>
  );
}
```

### Cache invalidation is not optional

The single most common Server Action bug: the mutation succeeds but the UI shows stale data. Every action that writes to the database must invalidate the relevant cache.

```typescript
// WRONG — the UI won't update
"use server";
export async function archiveOrderAction(id: string) {
  const supabase = await createClient();
  await updateOrder(supabase, id, { archived: true });
  // Where's the cache invalidation?
}

// RIGHT — the UI reflects the change immediately
"use server";
export async function archiveOrderAction(id: string) {
  const supabase = await createClient();
  await updateOrder(supabase, id, { archived: true });
  revalidatePath("/orders");
}
```

### Trust the database for authorization

If your database has Row Level Security, don't duplicate permission checks in your Server Actions. RLS enforces tenant isolation at the query level. A redundant check in your action is code that can drift out of sync with the actual policy.

```typescript
// WRONG — duplicating what RLS already does
"use server";
export async function deleteOrderAction(id: string) {
  const { orgId } = await auth();
  const order = await getOrderById(supabase, id);

  if (order.organization_id !== orgId) {
    throw new Error("Unauthorized");
  }

  await deleteOrder(supabase, id);
}

// RIGHT — let RLS enforce it
"use server";
export async function deleteOrderAction(id: string) {
  const supabase = await createClient();
  // If RLS rejects, Supabase throws automatically
  await deleteOrder(supabase, id);
  revalidatePath("/orders");
}
```

### When to use API routes instead

API routes exist for one purpose: receiving events from external services.

```typescript
// app/api/webhooks/payments/route.ts
export async function POST(req: Request) {
  const signature = req.headers.get("x-webhook-signature")!;
  const body = await req.text();

  // Verify the webhook came from the payment provider
  const event = verifySignature(body, signature, process.env.WEBHOOK_SECRET!);

  // Use service role client (webhooks bypass RLS)
  const supabase = createServiceRoleClient();

  switch (event.type) {
    case "payment.completed":
      await handlePaymentCompleted(supabase, event);
      break;
  }

  return Response.json({ received: true });
}
```

The rule is simple: if the caller is your own UI, use a Server Action. If the caller is an external service, use an API route.

## The Business Case

- **60% less mutation code.** No API routes, no fetch calls, no manual serialization. A Server Action replaces two files with one function.
- **Zero type boundary bugs.** TypeScript types flow from the action signature to the client call site. If the return type changes, the compiler catches every consumer.
- **Faster time to interactive.** Server Actions execute on the server and stream the result. No client-side JavaScript bundle for the mutation logic. No waterfall of fetch-parse-render.

## Try It

Install the Modh Playbook skills to enforce this pattern automatically:
```bash
# Add to your project
git submodule add https://github.com/modh-labs/playbook .agents/modh-playbook
./.agents/modh-playbook/install.sh
```
