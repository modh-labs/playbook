---
title: "Data Fetching"
subtitle: "Server Components changed everything"
chapter: 3
section: "Data Layer"
seo_title: "Next.js Server Components Data Fetching — No More React Query 2026"
seo_description: "Server Components eliminated the need for client-side data fetching libraries. Learn the server-first pattern with Suspense streaming and cache invalidation."
keywords: ["server components", "data fetching", "React 19", "Next.js", "Suspense", "cache invalidation", "SSR"]
reading_time: "7 min"
difficulty: "intermediate"
tech_stack: ["Next.js", "Supabase", "TypeScript"]
business_case: "Ships less JavaScript to the client, eliminates cache consistency bugs, and removes an entire dependency category from your bundle."
---

# Data Fetching

> "The best client-side cache is the one you never write."

## The Problem

For half a decade, the React ecosystem convinced itself that data fetching was a client-side problem. We installed React Query or SWR, configured stale times and refetch intervals, built cache key hierarchies, wired up mutation callbacks to invalidate related queries, and wrote `useEffect` hooks that fired on mount to populate initial state.

And it mostly worked — until it didn't.

The cache goes stale and two users see different versions of the same order. A mutation succeeds but the optimistic update conflicts with the server state. Someone adds a new query that depends on the same data but with a different cache key, so now you have two sources of truth that drift apart. The bundle grows by 30KB of cache management code that the user's browser has to download, parse, and execute before they can see their data.

We had layers of complexity solving a problem that only existed because we were fetching data in the wrong place. The server already had the data. The server was already authenticated. The server was already connected to the database. We were just choosing to ignore all of that and re-fetching everything from the browser.

Server Components changed the fundamental equation. Your React component can be an `async` function that runs on the server, queries the database directly, and streams the rendered HTML to the client. No fetch. No cache. No loading spinner. The data is there when the page arrives.

## The Principle

Fetch data where it already is — on the server. Push interactions, not data, to the client.

The server has the database connection, the auth context, and the secrets. Let it do the work. Client components handle clicks, animations, and form state — things that genuinely require the browser. Data flows down as props. Mutations flow up as Server Action calls.

This isn't a new idea. It's how the web worked before single-page applications. Server Components just made it possible without giving up component composition and interactivity.

## The Pattern

### Server Component fetches, client component renders

The page component is a Server Component. It queries the database through a repository, then passes the data to a client component that handles user interactions.

```typescript
// app/(protected)/orders/page.tsx — Server Component
import { createClient } from "@/lib/supabase/server";
import { listOrders } from "@/repositories/orders.repository";
import { OrdersPageClient } from "./components/OrdersPageClient";

export default async function OrdersPage() {
  const supabase = await createClient();
  const orders = await listOrders(supabase, { status: "active" });

  return <OrdersPageClient orders={orders} />;
}
```

```typescript
// app/(protected)/orders/components/OrdersPageClient.tsx — Client Component
"use client";
import { useTransition } from "react";
import { archiveOrderAction } from "../actions";

export function OrdersPageClient({
  orders,
}: {
  orders: Order[];
}) {
  const [isPending, startTransition] = useTransition();

  async function handleArchive(id: string) {
    startTransition(async () => {
      await archiveOrderAction(id);
      // Cache invalidation happens inside the action
    });
  }

  return (
    <div>
      {orders.map((order) => (
        <OrderCard
          key={order.id}
          order={order}
          onArchive={() => handleArchive(order.id)}
          isPending={isPending}
        />
      ))}
    </div>
  );
}
```

### Cache invalidation replaces cache management

There's no `staleTime`, no `refetchOnWindowFocus`, no `queryKey` hierarchy. When a mutation happens, the Server Action invalidates the relevant tag, and the framework re-renders the affected Server Components with fresh data.

```typescript
// app/(protected)/orders/actions.ts
"use server";
import { updateTag, refresh } from "next/cache";

export async function archiveOrderAction(id: string) {
  const supabase = await createClient();
  await updateOrder(supabase, id, { archived: true });

  updateTag("orders");         // Expire cached order data
  updateTag(`order-${id}`);    // Expire this specific order
  refresh();                   // Refresh the client router
}
```

The mental model is simple: mutations invalidate tags, Server Components re-run, the UI updates. One direction, no ambiguity, no race conditions.

### Client-side filtering for small datasets

For datasets under ~100 items, filter in the browser. The data is already there from the initial server render.

```typescript
"use client";
import { useMemo, useState } from "react";

export function OrdersList({ orders }: { orders: Order[] }) {
  const [query, setQuery] = useState("");

  const filtered = useMemo(
    () => orders.filter((o) =>
      o.title.toLowerCase().includes(query.toLowerCase())
    ),
    [orders, query]
  );

  return (
    <>
      <input
        placeholder="Search orders..."
        onChange={(e) => setQuery(e.target.value)}
      />
      {filtered.map((order) => (
        <OrderCard key={order.id} order={order} />
      ))}
    </>
  );
}
```

### Server-side search for large datasets

For larger datasets, debounce a Server Action call to search on the server.

```typescript
"use client";
import { useDebouncedCallback } from "use-debounce";
import { searchOrdersAction } from "../actions";

export function OrderSearch() {
  const [results, setResults] = useState<Order[]>([]);

  const debouncedSearch = useDebouncedCallback(
    async (query: string) => {
      const data = await searchOrdersAction(query);
      setResults(data);
    },
    500
  );

  return (
    <>
      <input
        placeholder="Search..."
        onChange={(e) => debouncedSearch(e.target.value)}
      />
      {results.map((order) => (
        <OrderCard key={order.id} order={order} />
      ))}
    </>
  );
}
```

### What we don't use anymore

These tools solved real problems in a client-fetching world. In a server-first world, they're unnecessary complexity.

```typescript
// BEFORE — client-side data fetching
"use client";
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";

export function OrdersList() {
  const { data, isLoading } = useQuery({
    queryKey: ["orders"],
    queryFn: () => fetch("/api/orders").then((r) => r.json()),
  });
  const queryClient = useQueryClient();
  const mutation = useMutation({
    mutationFn: archiveOrder,
    onSuccess: () =>
      queryClient.invalidateQueries({ queryKey: ["orders"] }),
  });
  // ...30 more lines of cache management
}

// AFTER — server-first
// Page: async function, direct DB query, pass data as props
// Client: useTransition + Server Action call
// That's it. No cache library. No loading state hook. No query keys.
```

## The Business Case

- **30KB less JavaScript.** Removing React Query or SWR from your client bundle means faster page loads, especially on mobile networks.
- **Zero cache consistency bugs.** There's one source of truth (the database) and one path to it (Server Components). No stale caches, no optimistic update conflicts, no refetch storms.
- **Faster perceived performance.** Server Components stream HTML as it's ready. The user sees content before the client JavaScript even loads.

## Try It

Install the Modh Playbook skills to enforce this pattern automatically:
```bash
# Add to your project
git submodule add https://github.com/modh-labs/playbook .agents/modh-playbook
./.agents/modh-playbook/install.sh
```
