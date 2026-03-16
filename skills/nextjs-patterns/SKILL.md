---
name: nextjs-patterns
description: Implement data fetching, server actions, and performance patterns for Next.js App Router. Use when fetching data in pages, writing mutations, adding loading states, Suspense boundaries, prefetching, or discussing data flow. Enforces Server Components, repository usage, structured returns, and progressive loading.
allowed-tools: Read, Grep, Glob, Edit, Write
tier: react
icon: layers
title: "Next.js Data & Mutation Patterns"
seo_title: "Next.js Data & Mutation Patterns — Modh Engineering Skill"
seo_description: "Implement data fetching, server actions, and performance patterns for Next.js App Router. Enforces Server Components, repository usage, and progressive loading."
keywords: ["nextjs", "server actions", "data fetching", "app router", "suspense"]
difficulty: intermediate
related_chapters: []
related_tools: []
---

# Next.js Patterns Skill

## When This Skill Activates

This skill automatically activates when you:
- Fetch data in Server Components or pages
- Create or modify server actions (mutations)
- Add loading states, skeletons, or Suspense boundaries
- Implement prefetching or navigation performance
- Discuss data flow, caching, or cache invalidation

---

## Section 1: Data Fetching

### Core Principle

All data fetching happens in Server Components via repository functions. Client Components receive data as props -- they never fetch.

```
Page (Server Component)
    | calls
Repository (Data Access)
    | queries
Database (via RLS)
    | returns
Typed Data
    | passes to
Client Components (display only)
```

### Basic Page Fetch

```typescript
// app/(protected)/orders/page.tsx
import { createClient } from "@/lib/supabase/server";
import { ordersRepository } from "@/lib/repositories/orders";
import { OrdersTable } from "./components/OrdersTable";

export default async function OrdersPage() {
  const supabase = await createClient();
  const orders = await ordersRepository.list(supabase);
  return <OrdersTable orders={orders} />;
}
```

### Parallel Fetching

Always use `Promise.all()` when fetching independent data:

```typescript
// Parallel (fast)
const [orders, users, stats] = await Promise.all([
  ordersRepository.list(supabase),
  usersRepository.list(supabase),
  statsRepository.getDashboard(supabase),
]);

// Sequential (slow) -- avoid
const orders = await ordersRepository.list(supabase);
const users = await usersRepository.list(supabase);
```

### Streaming with Suspense

Break pages into independently-loading sections:

```typescript
export default function DashboardPage() {
  return (
    <div>
      <h1>Dashboard</h1>
      <Suspense fallback={<OrdersSkeleton />}>
        <OrdersSection />
      </Suspense>
      <Suspense fallback={<StatsSkeleton />}>
        <StatsSection />
      </Suspense>
    </div>
  );
}

async function OrdersSection() {
  const supabase = await createClient();
  const orders = await ordersRepository.list(supabase);
  return <OrdersTable orders={orders} />;
}
```

### Graceful Degradation

Use `Promise.allSettled()` when partial data is acceptable:

```typescript
const results = await Promise.allSettled([
  ordersRepository.list(supabase),
  usersRepository.list(supabase),
]);
const orders = results[0].status === "fulfilled" ? results[0].value : [];
const users = results[1].status === "fulfilled" ? results[1].value : [];
```

### Data Fetching Decision Table

| Scenario | Pattern |
|----------|---------|
| Simple page load | Basic fetch in page component |
| Multiple independent queries | `Promise.all()` |
| Heavy page with sections | Suspense streaming |
| Form submission / mutation | Server Action + `revalidatePath()` |
| Real-time data | Database Realtime subscriptions (rare) |
| External third-party API | React Query / SWR (only for external APIs) |

---

## Section 2: Server Actions

### Core Rules

Server actions handle ALL mutations. They live in the route's `actions.ts` file.

#### 1. Always use repository functions

```typescript
// actions.ts
"use server";

import { ordersRepository } from "@/lib/repositories/orders";

// Never use supabase.from() directly in actions
export async function createOrderAction(input: OrderInput) {
  const supabase = await createClient();
  const order = await ordersRepository.create(supabase, input);
  // ...
}
```

#### 2. Always call revalidatePath() after mutations

```typescript
import { revalidatePath } from "next/cache";

export async function updateOrderAction(id: string, data: OrderUpdate) {
  const supabase = await createClient();
  await ordersRepository.update(supabase, id, data);

  revalidatePath("/orders");        // List page
  revalidatePath(`/orders/${id}`);  // Detail page
  revalidatePath("/dashboard");     // Related pages

  return { success: true };
}
```

#### 3. Return structured responses

All actions return `{ success, data?, error? }`:

```typescript
type ActionResponse<T> =
  | { success: true; data: T }
  | { success: false; error: string };

export async function getOrderAction(
  id: string
): Promise<ActionResponse<Order>> {
  try {
    const order = await ordersRepository.getById(supabase, id);
    if (!order) return { success: false, error: "Order not found" };
    return { success: true, data: order };
  } catch (error) {
    return { success: false, error: "Failed to fetch order" };
  }
}
```

#### 4. Validate at the boundary with Zod

```typescript
import { z } from "zod";

const CreateOrderSchema = z.object({
  title: z.string().min(1).max(200),
  amount: z.number().positive(),
  customer_id: z.string().uuid(),
});

export async function createOrderAction(input: unknown) {
  const parsed = CreateOrderSchema.safeParse(input);
  if (!parsed.success) {
    return { success: false, error: parsed.error.message };
  }
  // proceed with parsed.data
}
```

#### 5. Colocate with route

```
app/(protected)/orders/
  page.tsx
  actions.ts          <-- server actions here
  components/
    OrderForm.tsx     <-- imports from ../actions
```

Never put actions in a shared directory.

#### 6. Add "use server" directive

File-level (preferred) or function-level:

```typescript
// File-level
"use server";
export async function myAction() { /* ... */ }

// Function-level (when mixing)
export async function myAction() {
  "use server";
  // ...
}
```

### Client-Side Usage with useTransition

```typescript
"use client";
import { useTransition } from "react";
import { createOrderAction } from "../actions";

export function OrderForm() {
  const [isPending, startTransition] = useTransition();

  function handleSubmit(formData: FormData) {
    startTransition(async () => {
      const result = await createOrderAction({
        title: formData.get("title") as string,
      });
      if (!result.success) { /* show error toast */ }
    });
  }

  return (
    <form action={handleSubmit}>
      <Button type="submit" disabled={isPending}>
        {isPending ? "Creating..." : "Create"}
      </Button>
    </form>
  );
}
```

### Full template: `references/server-action-template.ts`

---

## Section 3: Loading States

### Suspense Boundaries

- Use 3-5 Suspense boundaries per page (typical)
- Skeletons MUST match the final content layout to prevent CLS
- Group related data that must appear together in one boundary

### Skeleton Rules

1. Match exact dimensions of final content
2. Show content structure (cards, rows, columns)
3. Use `animate-pulse` (built into Skeleton component)
4. Never use generic spinners for content areas

```typescript
function OrderGridSkeleton() {
  return (
    <div className="grid grid-cols-3 gap-4">
      {Array.from({ length: 6 }).map((_, i) => (
        <Card key={i}>
          <Skeleton className="h-4 w-3/4" />
          <Skeleton className="h-3 w-1/2 mt-2" />
          <Skeleton className="h-8 w-full mt-4" />
        </Card>
      ))}
    </div>
  );
}
```

### Optimistic Updates

Update UI immediately, reconcile when server responds:

```typescript
function OrderCard({ order }: { order: Order }) {
  const [optimistic, setOptimistic] = useOptimistic(order);

  async function handleStatusChange(newStatus: string) {
    setOptimistic({ ...order, status: newStatus });
    await updateOrderStatus(order.id, newStatus);
  }

  return <Badge>{optimistic.status}</Badge>;
}
```

| Action | Use Optimistic? |
|--------|-----------------|
| Toggle, status change | Yes |
| Form submission | Yes (with validation) |
| Delete | Show confirmation first |
| Complex multi-step | No -- use loading state |

### Button Loading States

```typescript
function SubmitButton({ onSubmit }: { onSubmit: () => Promise<void> }) {
  const [isPending, startTransition] = useTransition();
  return (
    <Button
      onClick={() => startTransition(onSubmit)}
      disabled={isPending}
    >
      {isPending ? (
        <><Loader2 className="mr-2 h-4 w-4 animate-spin" />Saving...</>
      ) : "Save"}
    </Button>
  );
}
```

---

## Section 4: Prefetching

### Link Prefetch (default)

Next.js `<Link>` prefetches by default when visible in viewport:

```typescript
<Link href="/orders" prefetch={true}>
  View Orders
</Link>
```

### Hover Prefetch (for expensive pages)

```typescript
function NavLink({ href, children }: { href: string; children: React.ReactNode }) {
  const router = useRouter();
  return (
    <Link
      href={href}
      onMouseEnter={() => router.prefetch(href)}
      prefetch={false}
    >
      {children}
    </Link>
  );
}
```

### When to Prefetch

| Scenario | Strategy |
|----------|----------|
| Main navigation links | `prefetch={true}` (default) |
| Table row links | Prefetch on hover |
| Modals / sheets | No prefetch needed |
| External links | Never prefetch |

---

## Section 5: Performance Thresholds

| Metric | Target | Warning |
|--------|--------|---------|
| Time to First Paint | < 100ms | > 200ms |
| Time to Interactive | < 1s | > 2s |
| LCP (Largest Contentful Paint) | < 2.5s | > 4s |
| CLS (Cumulative Layout Shift) | < 0.1 | > 0.25 |
| INP (Interaction to Next Paint) | < 200ms | > 500ms |

---

## Section 6: Anti-Patterns

| Anti-Pattern | Why It Is Wrong | Correct Alternative |
|-------------|-----------------|---------------------|
| Fetching in Client Components with useEffect | Waterfalls, no streaming, no SSR | Fetch in Server Component |
| Direct `supabase.from()` in pages/actions | Bypasses repository layer | Use repository functions |
| React Query / SWR for database data | Unnecessary client-side state | Server Components + revalidatePath |
| API routes for internal data | Extra hop, no streaming | Server Components fetch directly |
| Missing `revalidatePath()` after mutation | Users see stale data | Always revalidate affected paths |
| Throwing errors from server actions | Crashes client, no graceful handling | Return `{ success: false, error }` |
| Actions in shared directory | Breaks route colocation principle | Keep in route's `actions.ts` |
| Generic spinner for content areas | No layout information, causes CLS | Layout-matched skeleton |
| Blocking entire page for all data | Slow perceived performance | Suspense boundaries per section |
| Disabled button without visual indicator | User unsure if click registered | Show spinner + "Saving..." text |
| Waiting for server before updating UI | Feels slow on every interaction | Optimistic updates for toggles |
| Sequential fetches for independent data | Unnecessary waterfall | `Promise.all()` |

### Quick Reference

| Pattern | Correct | Wrong |
|---------|---------|-------|
| Data access | Repository functions | `supabase.from()` |
| After mutation | `revalidatePath()` | Nothing |
| Action response | `{ success, data/error }` | throw / raw data |
| Action location | `route/actions.ts` | `shared/actions/` |
| Directive | `"use server"` at top | Missing |
| Multiple fetches | `Promise.all()` | Sequential awaits |
| Loading UI | Layout-matched skeleton | Generic spinner |
