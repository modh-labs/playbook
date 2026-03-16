---
title: "Caching Strategy"
subtitle: "How we think about cache invalidation"
chapter: 8
section: "Architecture"
seo_title: "Next.js 16 Caching Strategy — Server-First Cache Invalidation 2026"
seo_description: "One cache layer, one invalidation pattern, zero client-side cache libraries. How Next.js 16 eliminated the need for React Query and SWR."
keywords: ["cache invalidation", "Next.js 16", "server cache", "updateTag", "React Server Components", "no React Query"]
reading_time: "7 min"
difficulty: "intermediate"
tech_stack: ["Next.js", "Supabase", "TypeScript"]
business_case: "Eliminates an entire category of cache consistency bugs and removes 30KB+ of client-side caching libraries from the bundle."
---

# Caching Strategy

> "There are only two hard things in computer science: cache invalidation and naming things. We fixed one of them."

## The Problem

The typical React application has at least three caching layers, and none of them agree.

First, there's the server cache — Next.js route caching, CDN edge caching, ISR revalidation timers. Second, there's the client-side data cache — React Query's normalized cache or SWR's key-value store, each with their own staleness timers, refetch policies, and garbage collection. Third, there's component state — `useState` calls that hold copies of data fetched on mount, growing staler with every second the tab stays open.

Each layer has its own invalidation mechanism. The server cache uses `revalidatePath` or time-based expiry. The client cache uses query key invalidation or manual `setQueryData` calls. Component state doesn't invalidate at all unless you explicitly refetch.

The bugs that emerge from this are subtle and maddening. A user creates an order. The Server Action succeeds. The server cache invalidates. But the React Query cache in the user's browser still has the old list for another 30 seconds because `staleTime` hasn't expired. The user doesn't see their new order. They create it again. Now there are two.

Or the opposite: an optimistic update shows the new order in the client cache immediately, but the server cache hasn't revalidated yet. The user refreshes the page and the order disappears. They panic, create it a third time. Now there are three.

We spent years building increasingly sophisticated cache coordination systems — event emitters that broadcast invalidation signals, React Query mutation callbacks that manually update related query keys, custom hooks that merge optimistic state with server state. All to solve a problem we created by having multiple caches in the first place.

## The Principle

One cache layer. One invalidation pattern. Zero client-side cache libraries.

Next.js 16 shifted the default from "cached unless you opt out" to "dynamic unless you opt in." Routes render dynamically by default. You add caching explicitly where you need it, using `'use cache'` directives. And you invalidate that cache from Server Actions using `updateTag()`.

The entire model is: Server Components fetch data. Server Actions mutate data and invalidate tags. Client components call Server Actions via `useTransition`. There's one cache, managed by the framework, invalidated in one place.

## The Pattern

### Server Components fetch, Server Actions invalidate

This is the complete caching model. There's nothing else to learn.

```typescript
// app/(protected)/orders/page.tsx — Server Component
import { listOrders } from "@/repositories/orders.repository";

export default async function OrdersPage() {
  const supabase = await createClient();
  // Fetched fresh on every request (dynamic by default in Next.js 16)
  const orders = await listOrders(supabase);

  return <OrdersClient orders={orders} />;
}
```

```typescript
// app/(protected)/orders/actions.ts — Server Action
"use server";
import { updateTag, refresh } from "next/cache";

export async function createOrderAction(data: OrderInsert) {
  const supabase = await createClient();
  await createOrder(supabase, data);

  updateTag("orders");       // Expire any cached order data
  refresh();                 // Refresh the client router
  return { success: true };
}
```

```typescript
// app/(protected)/orders/components/OrdersClient.tsx — Client Component
"use client";
import { useTransition } from "react";
import { createOrderAction } from "../actions";

export function OrdersClient({ orders }: { orders: Order[] }) {
  const [isPending, startTransition] = useTransition();

  async function handleCreate(data: OrderInsert) {
    startTransition(async () => {
      await createOrderAction(data);
      // No router.refresh() needed — the action handles it
    });
  }

  return (/* render orders, form calls handleCreate */);
}
```

That's it. No `useQuery`. No `queryClient.invalidateQueries`. No `staleTime`. No `refetchOnWindowFocus`. No event emitters. No manual cache coordination.

### When to add explicit caching

Most pages don't need caching. They render in milliseconds from the database and serve dynamic content. But for expensive computations or data that changes rarely, opt in with `'use cache'`:

```typescript
// A dashboard that aggregates millions of rows
async function getDashboardMetrics(orgId: string) {
  "use cache";
  cacheTag("dashboard", `dashboard-${orgId}`);
  cacheLife("minutes"); // Serve stale for up to 5 minutes

  return await computeExpensiveMetrics(orgId);
}
```

The cache tag lets you invalidate surgically. When an order is created, you don't need to invalidate the entire dashboard — just the affected org's metrics.

```typescript
export async function createOrderAction(data: OrderInsert) {
  "use server";
  const { orgId } = await auth();
  await createOrder(supabase, data);

  updateTag("orders");
  updateTag(`dashboard-${orgId}`);  // Targeted invalidation
  refresh();
}
```

### What we replaced

Each of these patterns existed to solve cache consistency in a multi-cache world. In a single-cache world, they're unnecessary.

**React Query / SWR**: Client-side data fetching and caching. Replaced by Server Components that fetch directly.

```typescript
// BEFORE
const { data, isLoading } = useQuery({
  queryKey: ["orders"],
  queryFn: () => fetch("/api/orders").then((r) => r.json()),
  staleTime: 30_000,
});

// AFTER
// Server Component — no hook, no loading state, no stale time
const orders = await listOrders(supabase);
```

**Event emitters**: Custom pub/sub for coordinating cache invalidation across components. Replaced by `updateTag()` which the framework broadcasts automatically.

```typescript
// BEFORE
emitOrdersInvalidated(); // Hope every subscriber handles it

// AFTER
updateTag("orders"); // Framework handles it, everywhere, every time
```

**Manual polling**: `setInterval` to refetch data periodically. Replaced by cache tags with time-based expiry.

```typescript
// BEFORE
useEffect(() => {
  const interval = setInterval(fetchOrders, 60_000);
  return () => clearInterval(interval);
}, []);

// AFTER
cacheLife("minutes"); // Framework handles staleness
```

**`router.refresh()` from client**: Manually refreshing the router after a mutation. Replaced by `refresh()` called from within the Server Action.

```typescript
// BEFORE — client has to know to refresh
const router = useRouter();
await myAction();
router.refresh();

// AFTER — action handles its own invalidation
// Client just calls the action; refresh happens server-side
startTransition(() => createOrderAction(data));
```

### The decision tree

```
Is this a mutation?
+-- YES -> Server Action with updateTag() + refresh()
+-- NO -> Is this a data fetch?
    +-- YES -> Does it need caching?
    |   +-- YES -> 'use cache' + cacheTag() + cacheLife()
    |   +-- NO  -> Direct fetch in Server Component
    +-- NO -> Regular component logic
```

## The Business Case

- **30KB+ removed from client bundle.** React Query alone is 13KB gzipped. SWR is 4KB. Custom cache coordination code adds more. Removing all of it measurably improves page load times.
- **Zero cache consistency bugs.** One cache, one invalidation mechanism, one source of truth. No more stale-while-the-other-cache-catches-up race conditions.
- **Simpler mental model for the team.** New developers learn one pattern: Server Components fetch, Server Actions invalidate. There's no cache configuration to tune, no staleness policies to debate, no query key hierarchies to maintain.

## Try It

Install the Modh Playbook skills to enforce this pattern automatically:
```bash
# Add to your project
git submodule add https://github.com/modh-labs/playbook .agents/modh-playbook
./.agents/modh-playbook/install.sh
```
