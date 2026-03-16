---
title: "Component Architecture"
subtitle: "Composition over configuration"
section: "07 — Frontend Craft"
---

# Component Architecture

> Composition over configuration. Server Components render data. Client Components handle interaction. Shared UI lives in a library. Everything else is colocated with its route.

---

## Problem

Frontend codebases rot in a predictable way. A component starts as a simple card. Someone adds a prop for "compact mode." Another developer adds an `isAdmin` flag. Six months later, it has 23 props, three render paths, and no one wants to touch it.

Configuration-driven components (the "god component" anti-pattern) create coupling. Every consumer depends on every feature. Every new use case adds another prop. Tests become combinatorial explosions.

The second failure mode is the wrong abstraction boundary. Teams either share too early (extracting a component after one use, then fighting it when use cases diverge) or too late (copy-pasting the same 80-line card across five routes until they drift apart).

---

## Principle

**Composition over configuration.** Small components that do one thing. Combine them like building blocks. Never add a boolean prop when you could compose two components.

Three rules govern where components live:

1. **Server Components by default.** They run on the server, fetch data directly, and send zero JavaScript to the browser. Every component starts as a Server Component.
2. **Client boundaries are explicit.** Only add `'use client'` when you need interactivity (event handlers, state, browser APIs). Push the boundary as deep as possible — wrap the interactive leaf, not the entire tree.
3. **Colocation with escape hatch.** Components live next to their route until three or more routes need them. Then — and only then — they move to the shared library.

---

## Pattern

### The Component Location Rule

```
app/(protected)/orders/
├── components/
│   ├── OrderTable.tsx          # Only used in this route
│   ├── OrderFilters.tsx        # Only used in this route
│   └── OrderStatusBadge.tsx    # Only used in this route
├── actions.ts
├── page.tsx
└── loading.tsx

app/_shared/components/
├── entity-list/                # Used by 3+ routes
├── timeline/                   # Used by 3+ routes
└── metrics/                    # Used by 3+ routes

components/ui/                  # shadcn/ui base components (never modify directly)
```

**Decision tree:**

| Question | Answer | Location |
|----------|--------|----------|
| Is it a base UI primitive (button, input, dialog)? | Yes | `components/ui/` (shadcn) |
| Is it used by only 1 route? | Yes | `app/(protected)/route/components/` |
| Is it used by 2 routes? | Yes | Keep colocated, tolerate duplication |
| Is it used by 3+ routes? | Yes | `app/_shared/components/` |
| Does it need state or event handlers? | Yes | Add `'use client'` |
| Does it only render data? | Yes | Keep as Server Component |

### Server Components Fetch Data

Server Components call repository functions directly. No API layer. No client-side state management. The component *is* the data-fetching layer.

```tsx
// page.tsx — Server Component (default, no directive needed)
import { getOrders } from '@/repositories/orders.repository';

export default async function OrdersPage() {
  const orders = await getOrders();

  return (
    <div>
      <PageHeader title="Orders" />
      <Suspense fallback={<OrdersTableSkeleton />}>
        <OrdersTable orders={orders} />
      </Suspense>
    </div>
  );
}
```

No `useEffect`. No loading state management. No `useState` for data. The server fetches, renders HTML, and streams it to the browser.

### Client Boundaries Are Leaves

Push `'use client'` as deep as possible. The parent stays on the server; only the interactive piece ships JavaScript.

```tsx
// WRONG — entire page is a Client Component
'use client';
export default function OrdersPage() {
  const [orders, setOrders] = useState([]);
  useEffect(() => { fetchOrders().then(setOrders); }, []);
  // ... 200 lines of rendering
}

// RIGHT — only the interactive part is a Client Component
// page.tsx (Server Component)
export default async function OrdersPage() {
  const orders = await getOrders();
  return <OrdersList initialOrders={orders} />;
}

// components/OrdersList.tsx (Client Component — handles selection, filtering)
'use client';
export function OrdersList({ initialOrders }: { initialOrders: Order[] }) {
  const [selected, setSelected] = useState<string | null>(null);
  // Only interactivity logic here
}
```

### The Three-Layer Detail View

Every detail view (sheet, panel, full page) follows the same three layers:

```tsx
// Layer 1: Container — manages open/close state
export function OrderDetailSheet({ open, onOpenChange, orderId }: Props) {
  return (
    <Sheet open={open} onOpenChange={onOpenChange}>
      <SheetContent>
        <Suspense fallback={<OrderDetailSkeleton />}>
          <OrderDetail orderId={orderId} />
        </Suspense>
      </SheetContent>
    </Sheet>
  );
}

// Layer 2: Detail — assembles sections (Server Component)
async function OrderDetail({ orderId }: { orderId: string }) {
  const order = await getOrderById(orderId);
  return (
    <div className="space-y-0 divide-y">
      <CustomerSection customer={order.customer} />
      <ItemsSection items={order.items} />
      <ActionsSection orderId={order.id} status={order.status} />
    </div>
  );
}

// Layer 3: Section — renders one concern
function CustomerSection({ customer }: { customer: Customer }) {
  return (
    <SectionLayout title="CUSTOMER">
      <InfoGrid cols={2}>
        <InfoItem label="Name">{customer.name}</InfoItem>
        <InfoItem label="Email">{customer.email}</InfoItem>
      </InfoGrid>
    </SectionLayout>
  );
}
```

Why three layers? Each can change independently. The container can switch from a Sheet to a Dialog. The detail can add new sections. Sections can be reused across detail views.

### The Shared UI Library

Base components come from shadcn/ui. Never use raw HTML elements for interactive controls.

```tsx
// ALWAYS — use the component library
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Dialog, DialogContent, DialogHeader, DialogTitle } from '@/components/ui/dialog';

<Button variant="destructive">Delete Order</Button>
<Input placeholder="Search orders..." />

// NEVER — raw HTML with custom classes
<button className="px-4 py-2 bg-red-500 text-white rounded">Delete Order</button>
<input className="border rounded px-3 py-2" placeholder="Search orders..." />
```

Use semantic design tokens, not hardcoded colors:

```tsx
// RIGHT — semantic tokens (auto light/dark mode)
<div className="bg-background text-foreground border-border" />
<Badge className="bg-destructive text-destructive-foreground" />

// WRONG — hardcoded colors
<div className="bg-white text-gray-900 border-gray-200" />
<Badge className="bg-red-500 text-white" />
```

### Master-Detail with Real-time Updates

For collaborative features, the architecture adds two more layers on top of Server Component rendering:

```
Layer 1: Server-Side Rendering (initial load)
  → Server Component fetches via repository, passes as props

Layer 2: Optimistic Updates (user's own actions)
  → useOptimistic for instant feedback, Server Action in background

Layer 3: Real-time Subscriptions (cross-user updates)
  → WebSocket subscription for INSERT/UPDATE/DELETE events
  → Other users' changes appear automatically
```

```tsx
'use client';

export function OrdersList({ initialOrders }: Props) {
  const [optimisticOrders, updateOrder] = useOptimistic(
    initialOrders,
    (state, updated: Order) =>
      state.map(o => o.id === updated.id ? updated : o)
  );

  // Real-time: other users' changes appear automatically
  useRealtimeOrders({
    onUpdate: (order) => updateOrder(order),
    onInsert: (order) => { /* add to list */ },
    onDelete: (id) => { /* remove from list */ },
  });

  return <DataGrid data={optimisticOrders} />;
}
```

### Never Cross-Route Import

```tsx
// WRONG — importing from another route
import { UserCard } from '../users/components/UserCard';

// RIGHT — if you need it in two places, move to shared
import { UserCard } from '@/app/_shared/components/UserCard';
```

This rule is non-negotiable. Cross-route imports create invisible coupling. When the users route refactors its `UserCard`, the orders route breaks.

---

## Business Case

**Smaller bundles.** Server Components send zero JavaScript for data display. A typical dashboard page that was 180KB of client JS becomes 12KB when only interactive controls are Client Components. Faster load times directly correlate with user engagement.

**Faster iteration.** Colocated components mean developers work in one directory. No hunting through a shared component library to understand what a page does. New team members are productive in hours, not days.

**Fewer regressions.** The three-use-rule prevents premature abstraction. When a component finally moves to shared, it has three real use cases to design against — not one imagined future that never arrives.

**Real-time collaboration.** The three-layer architecture (SSR + optimistic + real-time) means teams can work on the same data simultaneously without conflicts or stale views. No "refresh to see changes" — the UI stays synchronized automatically.

---

## Try It

Take a page in your application that uses a single large Client Component with `useEffect` for data fetching:

1. **Convert the page to a Server Component.** Move the data fetch into the component body with `await`. Remove `useState` and `useEffect` for data.
2. **Push client boundaries down.** Identify which parts need interactivity (a filter dropdown, a row selection). Extract only those into `'use client'` components.
3. **Measure the difference.** Check the JavaScript bundle size before and after. Typical reduction: 60-80% less client JS.
4. **Apply the colocation rule.** If any component is imported from another route's directory, either move it to `_shared/` (if 3+ routes use it) or duplicate it (if only 2 routes use it). Duplication is cheaper than wrong abstraction.
