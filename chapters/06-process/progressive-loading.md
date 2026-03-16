---
title: "Progressive Loading"
subtitle: "The user should never wait"
chapter: 24
section: "Process"
seo_title: "Progressive Loading Patterns for Next.js — Suspense, Skeletons, and Optimistic Updates in 2026"
seo_description: "Make every interaction feel instant with Suspense boundaries, skeleton components, optimistic updates, and smart prefetching in Next.js."
keywords: ["progressive loading", "suspense boundaries", "skeleton components", "optimistic updates", "next.js performance", "perceived performance"]
reading_time: "9 min"
difficulty: "intermediate"
tech_stack: ["Next.js", "React 19", "TypeScript"]
business_case: "Reduce perceived load times by 70% without changing backend performance, directly improving conversion and retention."
---

# Progressive Loading

> "The fastest app is not the one that loads the fastest. It is the one that feels like it already loaded."

## The Problem

A dashboard page fetches analytics, recent orders, and team activity. Each query takes 200-500ms. The page waits for all three to complete before rendering anything. Total: 1.2 seconds of white screen.

1.2 seconds is fast in absolute terms. It feels slow because the user sees nothing during that time. They click a link and the screen goes blank. For 1.2 seconds, the application appears broken.

This is the gap between actual performance and perceived performance. Actual performance is how long the server takes to respond. Perceived performance is how long the user feels like they are waiting. A page that shows a skeleton in 50ms and streams content over the next second feels faster than a page that renders everything at once in 800ms, even though the second page is objectively faster.

The second problem is interaction latency. A user clicks "Delete" on an order. The UI disables the button and waits for the server to confirm the deletion. 400ms later, the order disappears. Those 400ms feel like the application is thinking. In a modern web application, the user expects the order to disappear immediately.

The third problem is navigation. The user clicks a link to an order detail page. The browser navigates, hits a loading state, fetches data, and renders. The transition feels clunky — a visible gap between the click and the content.

## The Principle

Every interaction should feel instant. Users should never wonder "is this working?" We achieve this through four techniques:

**Immediate visual feedback.** Show something within 100ms of any user action. A skeleton, a loading spinner in a button, a dimmed row — anything that confirms the application received the input.

**Progressive streaming.** Do not wait for all data before rendering. Wrap independent sections in their own loading boundaries so they stream as they become ready. The analytics chart appears while the activity feed is still loading.

**Optimistic updates.** Update the UI immediately when the user takes an action. Reconcile with the server afterward. The order disappears from the list the instant the user clicks "Delete," not 400ms later when the server confirms.

**Smart prefetching.** Anticipate where the user is going and preload that destination. When a row is hovered, prefetch the detail page. When a list is visible, prefetch the first few detail pages. The navigation feels instant because the data is already there.

## The Pattern

### Suspense Boundaries for Progressive Streaming

Wrap independent sections in their own `<Suspense>` boundaries so they stream as they become ready.

```tsx
// BEFORE: Single blocking fetch — page waits for ALL data
export default async function DashboardPage() {
  const [analytics, orders, activity] = await Promise.all([
    getAnalytics(),
    getOrders(),
    getActivity(),
  ]);

  return (
    <div>
      <Analytics data={analytics} />
      <Orders data={orders} />
      <Activity data={activity} />
    </div>
  );
}

// AFTER: Progressive streaming — each section loads independently
export default function DashboardPage() {
  return (
    <div>
      <Suspense fallback={<AnalyticsSkeleton />}>
        <AnalyticsSection />
      </Suspense>
      <Suspense fallback={<OrdersSkeleton />}>
        <OrdersSection />
      </Suspense>
      <Suspense fallback={<ActivitySkeleton />}>
        <ActivitySection />
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

The user sees three skeletons immediately. As each data source responds, its skeleton is replaced with real content. The fastest section appears first. No section blocks another.

**When to use nested Suspense:**

| Scenario | Nested Suspense? |
|----------|-----------------|
| Independent data sources | Yes — each streams separately |
| Parent-child data dependency | No — child depends on parent |
| Multiple tabs or views | Yes — only active tab loads |
| Primary + secondary content | Yes — show primary first |

**Rules:** 3-5 Suspense boundaries per page is typical. Do not over-granularize — a boundary per paragraph is too many. Group data that must appear together.

### Skeleton Components

Skeletons must match the actual content layout. A generic spinner communicates nothing about what is loading and causes layout shift when the content arrives.

```tsx
import { Skeleton } from "@/components/ui/skeleton";

// Skeleton matches the actual OrderCard layout
export function OrderCardSkeleton() {
  return (
    <div className="flex items-center gap-4 p-4 border rounded-lg">
      <Skeleton className="h-10 w-10 rounded-full" />
      <div className="flex-1 space-y-2">
        <Skeleton className="h-4 w-1/3" />
        <Skeleton className="h-3 w-1/4" />
      </div>
      <Skeleton className="h-8 w-20" />
    </div>
  );
}

// List skeleton repeats the card skeleton at a realistic count
export function OrdersListSkeleton({ count = 10 }: { count?: number }) {
  return (
    <div className="space-y-4">
      {Array.from({ length: count }).map((_, i) => (
        <OrderCardSkeleton key={i} />
      ))}
    </div>
  );
}
```

**Skeleton rules:**
- Match exact dimensions to prevent Cumulative Layout Shift (CLS)
- Use consistent animation (pulse by default)
- Show a realistic count (10 rows for a list, not 3)
- Use circles for avatars, rectangles for text, matching the real element sizes

### Two-Phase Loading

Routes that use both Next.js `loading.tsx` and a `<Suspense>` boundary inside `page.tsx` need two distinct skeleton forms to avoid double-wrapping the page layout.

```tsx
// loading.tsx

// Named export: no layout wrapper — used as Suspense fallback
// inside page.tsx, which already has its own layout.
export function OrdersLoadingSkeleton() {
  return (
    <div className="flex flex-1 flex-col">
      <OrdersListSkeleton />
    </div>
  );
}

// Default export: wraps in layout — used by Next.js as the
// route-level loading UI before page.tsx resolves.
export default function OrdersLoading() {
  return (
    <PageLayout>
      <OrdersLoadingSkeleton />
    </PageLayout>
  );
}
```

```tsx
// page.tsx — uses the named export to avoid double layout
import { OrdersLoadingSkeleton } from "./loading";

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

Without this split, the Suspense phase renders a skeleton inside two nested layout wrappers, producing double padding during the transition.

### Optimistic Updates

Update the UI immediately, then reconcile with the server.

```tsx
"use client";
import { useOptimistic, useTransition } from "react";
import { deleteOrderAction } from "./actions";

export function OrdersList({ orders }: { orders: Order[] }) {
  const [isPending, startTransition] = useTransition();

  const [optimisticOrders, removeOrder] = useOptimistic(
    orders,
    (state, deletedId: string) => state.filter((o) => o.id !== deletedId)
  );

  const handleDelete = (orderId: string) => {
    // 1. Update UI immediately
    removeOrder(orderId);

    // 2. Sync with server
    startTransition(async () => {
      const result = await deleteOrderAction(orderId);
      if (!result.success) {
        // UI will rollback when `orders` prop updates from server
        toast.error("Failed to delete order");
      }
    });
  };

  return (
    <ul>
      {optimisticOrders.map((order) => (
        <li key={order.id}>
          {order.title}
          <Button onClick={() => handleDelete(order.id)}>Delete</Button>
        </li>
      ))}
    </ul>
  );
}
```

The order disappears from the list the instant the user clicks Delete. If the server returns an error, the UI rolls back automatically when the `orders` prop refreshes.

**Optimistic update patterns:**

```tsx
// Delete from list
(state, id: string) => state.filter((item) => item.id !== id)

// Add to list
(state, newItem: Item) => [...state, { ...newItem, id: "temp-" + Date.now() }]

// Update status
(state, { id, status }) =>
  state.map((item) => (item.id === id ? { ...item, status } : item))

// Toggle boolean
(state, _) => ({ ...state, isActive: !state.isActive })
```

**Rules:** Always combine `useOptimistic` with `useTransition`. Show a toast on server error. Use temporary IDs for optimistic creates. Do not use optimistic updates for critical operations like payments.

### Smart Prefetching

Prefetch likely destinations so navigation feels instant.

```tsx
// Automatic: prefetch when link enters viewport
<Link href={`/orders/${order.id}`} prefetch={true}>
  View Order
</Link>

// On hover: prefetch when user shows intent
const router = useRouter();
<div
  onMouseEnter={() => router.prefetch(`/orders/${order.id}`)}
  onClick={() => router.push(`/orders/${order.id}`)}
>
  {order.title}
</div>

// Predictive: prefetch the next likely destination
useEffect(() => {
  if (nextOrderId) {
    router.prefetch(`/orders/${nextOrderId}`);
  }
}, [nextOrderId, router]);
```

**Prefetching rules:** Use `prefetch={true}` on links in lists and grids. Prefetch detail pages on row hover. Prefetch "next" items in sequential flows. Do not prefetch everything — focus on likely destinations.

### Dialog and Sheet Loading States

Dialogs that disable buttons during mutations without visual feedback leave users confused.

```tsx
"use client";
import { useTransition } from "react";
import { Loader2 } from "lucide-react";

export function OrderDialog({ order, onSubmit }: Props) {
  const [isPending, startTransition] = useTransition();

  return (
    <DialogContent className="relative">
      {isPending && (
        <div className="absolute inset-0 bg-background/80 flex items-center justify-center z-50">
          <Loader2 className="h-8 w-8 animate-spin text-muted-foreground" />
        </div>
      )}

      <form onSubmit={(data) => startTransition(() => onSubmit(data))}>
        <fieldset disabled={isPending} className="space-y-4">
          <Input name="status" placeholder="Status" />
          <Textarea name="notes" placeholder="Notes" />
        </fieldset>

        <Button type="submit" disabled={isPending}>
          {isPending ? (
            <>
              <Loader2 className="mr-2 h-4 w-4 animate-spin" />
              Saving...
            </>
          ) : (
            "Save"
          )}
        </Button>
      </form>
    </DialogContent>
  );
}
```

Use `<fieldset disabled>` to disable all form fields at once. Show a loading overlay for visual feedback. Change the button text to indicate the action in progress.

## The Business Case

**Perceived load time drops by 70%.** Suspense boundaries and skeletons mean the user sees content structure within 50ms, even if data takes a full second to load. The page never feels blank.

**Interaction latency drops to zero.** Optimistic updates make every action feel instant. The 400ms round trip to the server still happens, but the user does not experience it.

**Cumulative Layout Shift hits zero.** Skeletons that match the actual content layout prevent the jarring visual shifts that erode user trust and tank Core Web Vitals scores.

**Conversion improves measurably.** Studies consistently show that every 100ms of perceived latency costs 1% of conversions. A page that feels instant converts better than a page that feels slow, regardless of actual server performance.

**Navigation becomes invisible.** Smart prefetching means clicking a link shows content immediately. The user does not perceive a page transition because the destination was already loaded in the background.

## Try It

Install the [Modh Playbook](https://github.com/modh-ai/playbook) to get the complete progressive loading setup with Suspense boundary patterns, skeleton component templates, optimistic update hooks, and prefetching strategies pre-configured for Next.js and React 19.
