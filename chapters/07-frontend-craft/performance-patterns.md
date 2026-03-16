---
title: "Frontend Performance"
subtitle: "Suspense, streaming, and instant UI"
section: "07 — Frontend Craft"
---

# Frontend Performance

> Every interaction should feel instant. Users should never wonder "is this working?" Perceived performance through streaming, skeletons, optimistic updates, and smart prefetching.

---

## Problem

Users do not care about your server response time. They care about how fast the interface *feels*. A page that loads in 800ms but shows a blank white screen feels slower than a page that loads in 1200ms but shows a skeleton in 50ms.

The traditional approach — fetch all data, then render everything at once — fails in three ways:

1. **Blank screens.** The page waits for the slowest query before showing anything. A dashboard with four sections blocks on whichever database query takes longest.
2. **Laggy interactions.** Clicking "delete" sends a request, waits for the response, then updates the UI. The 200-400ms round trip makes every action feel sluggish.
3. **Stale navigations.** Users click a link and wait for the next page to load. There is no feedback that anything is happening.

These are not backend problems. The server might respond in 100ms. But without the right frontend patterns, users still perceive the application as slow.

---

## Principle

**Show something in 100ms. Show everything progressively. Never wait for confirmation to update the UI.**

Four techniques, layered together:

1. **Suspense streaming** — Independent sections render as their data arrives. The shell appears instantly; content fills in progressively.
2. **Skeleton-first design** — Every loading state shows a skeleton that matches the final layout. No spinners. No blank space. No layout shift.
3. **Optimistic updates** — The UI reflects the user's action immediately. The server confirms in the background. If it fails, roll back.
4. **Smart prefetching** — Anticipate where the user will go next and preload that page before they click.

---

## Pattern

### Suspense Boundaries for Progressive Loading

Wrap independent sections in their own `<Suspense>` boundaries. Each section streams to the browser as its data becomes ready.

```tsx
// BEFORE — single blocking fetch, page waits for ALL data
export default async function DashboardPage() {
  const [analytics, orders, users] = await Promise.all([
    getAnalytics(),
    getOrders(),
    getUsers(),
  ]);

  return (
    <div>
      <Analytics data={analytics} />
      <Orders data={orders} />
      <Users data={users} />
    </div>
  );
}

// AFTER — progressive streaming, each section loads independently
export default function DashboardPage() {
  return (
    <div>
      <Suspense fallback={<AnalyticsSkeleton />}>
        <AnalyticsSection />
      </Suspense>
      <Suspense fallback={<OrdersSkeleton />}>
        <OrdersSection />
      </Suspense>
      <Suspense fallback={<UsersSkeleton />}>
        <UsersSection />
      </Suspense>
    </div>
  );
}

// Each section is its own async Server Component
async function AnalyticsSection() {
  const analytics = await getAnalytics();
  return <Analytics data={analytics} />;
}
```

**Rules for Suspense boundaries:**

| Scenario | Use Nested Suspense? |
|----------|---------------------|
| Independent data sources | Yes — each streams separately |
| Parent-child data dependency | No — child depends on parent |
| Multiple tabs/views | Yes — only active tab loads |
| Primary + secondary content | Yes — show primary first |

Keep it to 3-5 boundaries per page. More than that and the progressive loading becomes distracting.

### Skeleton-First Design

Every loading state uses a skeleton that mirrors the actual content layout. Skeletons prevent Cumulative Layout Shift (CLS) and communicate what is loading.

```tsx
import { Skeleton } from '@/components/ui/skeleton';

// Skeleton matches actual OrderCard layout exactly
function OrderCardSkeleton() {
  return (
    <div className="flex items-center gap-4 p-4 border rounded-lg">
      <Skeleton className="h-10 w-10 rounded-full" />  {/* Avatar */}
      <div className="flex-1 space-y-2">
        <Skeleton className="h-4 w-1/3" />  {/* Name */}
        <Skeleton className="h-3 w-1/4" />  {/* Date */}
      </div>
      <Skeleton className="h-8 w-20" />  {/* Action button */}
    </div>
  );
}

// List skeleton repeats card skeleton with realistic count
function OrdersListSkeleton({ count = 10 }: { count?: number }) {
  return (
    <div className="space-y-4">
      {Array.from({ length: count }).map((_, i) => (
        <OrderCardSkeleton key={i} />
      ))}
    </div>
  );
}
```

**Skeleton mapping:**

| UI Element | Skeleton Shape |
|-----------|---------------|
| Avatar | Circle matching size |
| Text line | Rectangle at typical width |
| Button | Rectangle matching button size |
| Image | Rectangle matching aspect ratio |
| Input field | Rectangle matching input height |

### Two-Phase Loading: Named Export Pattern

Routes that use both `loading.tsx` and a `<Suspense>` boundary inside `page.tsx` need two distinct skeleton forms — one with a page layout wrapper and one without. This prevents double padding.

```tsx
// loading.tsx

// Named export: no layout wrapper — used as Suspense fallback inside page.tsx
export function OrdersLoadingSkeleton() {
  return (
    <div className="flex h-full min-h-0 flex-1 flex-col overflow-hidden">
      <Skeleton className="h-10 w-64 mb-4" />
      <div className="space-y-2">
        {Array.from({ length: 10 }).map((_, i) => (
          <Skeleton key={i} className="h-16 w-full" />
        ))}
      </div>
    </div>
  );
}

// Default export: with layout wrapper — used by Next.js as route-level loading
export default function OrdersLoading() {
  return (
    <PageLayout>
      <OrdersLoadingSkeleton />
    </PageLayout>
  );
}
```

```tsx
// page.tsx — uses the named export to avoid double-wrapping
import { OrdersLoadingSkeleton } from './loading';

export default async function OrdersPage() {
  return (
    <PageLayout>
      <Suspense fallback={<OrdersLoadingSkeleton />}>
        <OrdersListContent />
      </Suspense>
    </PageLayout>
  );
}
```

### Optimistic Updates with `useOptimistic`

Update the UI immediately. Sync with the server in the background. Roll back automatically if the server rejects the change.

```tsx
'use client';
import { useOptimistic, useTransition } from 'react';
import { deleteOrderAction } from './actions';

export function OrdersList({ orders }: { orders: Order[] }) {
  const [isPending, startTransition] = useTransition();

  const [optimisticOrders, removeOrder] = useOptimistic(
    orders,
    (state, deletedId: string) => state.filter(o => o.id !== deletedId)
  );

  const handleDelete = (orderId: string) => {
    // 1. Update UI immediately — user sees the item vanish
    removeOrder(orderId);

    // 2. Sync with server in background
    startTransition(async () => {
      const result = await deleteOrderAction(orderId);
      if (!result.success) {
        // UI auto-rolls back when `orders` prop refreshes from server
        toast.error('Failed to delete order');
      }
    });
  };

  return (
    <ul>
      {optimisticOrders.map(order => (
        <li key={order.id}>
          {order.title}
          <Button onClick={() => handleDelete(order.id)} disabled={isPending}>
            Delete
          </Button>
        </li>
      ))}
    </ul>
  );
}
```

**Common optimistic update patterns:**

```tsx
// Delete from list
const [items, removeItem] = useOptimistic(
  items,
  (state, id: string) => state.filter(item => item.id !== id)
);

// Add to list
const [items, addItem] = useOptimistic(
  items,
  (state, newItem: Item) => [...state, { ...newItem, id: 'temp-' + Date.now() }]
);

// Update item status
const [items, updateItem] = useOptimistic(
  items,
  (state, { id, status }: { id: string; status: string }) =>
    state.map(item => item.id === id ? { ...item, status } : item)
);

// Toggle boolean
const [item, toggleItem] = useOptimistic(
  item,
  (state, _) => ({ ...state, isActive: !state.isActive })
);
```

**Rules:** Always pair `useOptimistic` with `useTransition`. Show a toast on server error. Use temporary IDs for optimistic creates. Do not use optimistic updates for critical operations (payments, irreversible deletions).

### Smart Prefetching

Anticipate navigation and preload pages before the user clicks.

```tsx
// Automatic: prefetch when link enters viewport
import Link from 'next/link';

<Link href={`/orders/${order.id}`} prefetch={true}>
  View Order
</Link>

// On hover: prefetch likely destination
'use client';
export function OrderRow({ order }: { order: Order }) {
  const router = useRouter();

  return (
    <div
      onMouseEnter={() => router.prefetch(`/orders/${order.id}`)}
      onClick={() => router.push(`/orders/${order.id}`)}
    >
      {order.title}
    </div>
  );
}

// Predictive: prefetch next item in a sequence
export function OrderDetail({ order, nextOrderId }: Props) {
  const router = useRouter();

  useEffect(() => {
    if (nextOrderId) {
      router.prefetch(`/orders/${nextOrderId}`);
    }
  }, [nextOrderId, router]);

  return <div>...</div>;
}
```

Focus prefetching on likely destinations. Do not prefetch everything — that wastes bandwidth and server resources.

### Dialog and Sheet Loading States

Show clear loading indication inside modals. Use `<fieldset disabled>` to disable all form fields at once.

```tsx
'use client';
import { useTransition } from 'react';
import { Loader2 } from 'lucide-react';

export function OrderOutcomeDialog({ order, onSubmit }: Props) {
  const [isPending, startTransition] = useTransition();

  const handleSubmit = (data: FormData) => {
    startTransition(async () => {
      await onSubmit(data);
    });
  };

  return (
    <DialogContent className="relative">
      {isPending && (
        <div className="absolute inset-0 bg-background/80 flex items-center justify-center z-50 rounded-lg">
          <Loader2 className="h-8 w-8 animate-spin text-muted-foreground" />
        </div>
      )}

      <form onSubmit={handleSubmit}>
        <fieldset disabled={isPending} className="space-y-4">
          <Input name="outcome" placeholder="Outcome" />
          <Textarea name="notes" placeholder="Notes" />
        </fieldset>

        <DialogFooter className="mt-4">
          <Button type="submit" disabled={isPending}>
            {isPending ? (
              <>
                <Loader2 className="mr-2 h-4 w-4 animate-spin" />
                Saving...
              </>
            ) : (
              'Save Outcome'
            )}
          </Button>
        </DialogFooter>
      </form>
    </DialogContent>
  );
}
```

### Transition-Wrapped Navigation

Wrap programmatic navigation in `startTransition` to show loading feedback during route transitions.

```tsx
'use client';

export function OrderRow({ order }: { order: Order }) {
  const router = useRouter();
  const [isPending, startTransition] = useTransition();

  const handleClick = () => {
    startTransition(() => {
      router.push(`/orders/${order.id}`);
    });
  };

  return (
    <div
      onClick={handleClick}
      className={cn(
        'cursor-pointer hover:bg-muted/50',
        isPending && 'opacity-50 pointer-events-none'
      )}
    >
      {isPending && <Loader2 className="h-4 w-4 animate-spin mr-2" />}
      {order.title}
    </div>
  );
}
```

---

## Business Case

**Perceived performance drives retention.** Users abandon pages that feel slow. A skeleton appearing in 50ms tells the user "this is working" even if the data takes another second. Studies consistently show that perceived speed matters more than actual speed for user satisfaction.

**Optimistic updates reduce support tickets.** When users click "delete" and the item vanishes instantly, they trust the system. When they click and wait 400ms, they click again. Double submissions, confusion about whether the action worked, and "it's not responding" complaints all stem from the same root cause: the UI did not react fast enough.

**Streaming reduces Time to First Byte impact.** With Suspense boundaries, the shell streams immediately. A slow database query for analytics does not block the entire page — users see the navigation, header, and primary content while the analytics section loads independently.

**Target metrics per route:**

| Metric | Target | What It Measures |
|--------|--------|-----------------|
| First Contentful Paint (FCP) | <1s | Skeleton/structure visible |
| Largest Contentful Paint (LCP) | <2.5s | Main content loaded |
| Time to Interactive (TTI) | <3s | Page responsive to input |
| Cumulative Layout Shift (CLS) | <0.1 | No unexpected layout movement |

---

## Try It

Take the slowest page in your application (check your analytics for the highest LCP):

1. **Add Suspense boundaries.** Identify the independent data sources on the page. Wrap each in its own `<Suspense>` with a matching skeleton. Measure LCP before and after.
2. **Add optimistic updates to one mutation.** Pick the most common user action (status change, delete, toggle). Add `useOptimistic` so the UI responds immediately. Watch for the moment the interaction goes from "click and wait" to "click and done."
3. **Add prefetching to a list.** On a datagrid or card list, add `onMouseEnter` prefetching for detail pages. Navigate to a detail page before and after — the difference is dramatic.
4. **Check your skeletons.** Do they match the actual content layout? Or are they generic rectangles? Mismatched skeletons cause layout shift that makes the page feel *worse* than a blank screen. Align them to the real layout dimensions.
