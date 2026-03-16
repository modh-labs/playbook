---
title: "Route Colocation"
subtitle: "Files live next to the route that uses them"
chapter: 4
section: "Architecture"
seo_title: "Route Colocation — File Organization for Next.js App Router 2026"
seo_description: "Stop splitting features across shared folders. Colocate files with the route that uses them, share only when three or more routes need them."
keywords: ["route colocation", "Next.js App Router", "file organization", "component colocation", "feature folders"]
reading_time: "8 min"
difficulty: "intermediate"
tech_stack: ["Next.js", "Supabase", "TypeScript"]
business_case: "Reduces onboarding time from weeks to days by making every feature self-contained and discoverable in a single directory."
---

# Route Colocation

> "If you have to open four directories to understand one feature, your architecture is working against you."

## The Problem

Open a codebase that's been alive for two years. Find where the order creation form lives. Not the component — the whole feature. The form, the validation, the server action, the types, the loading state, the error boundary.

In a typical project, you'll find the form component in `components/orders/`, the action in `lib/actions/orders.ts`, the types in `types/orders.ts`, the validation schema in `lib/validation/orders.ts`, and the page in `app/orders/page.tsx`. Five directories. Five places to remember. Five places that will drift apart as the codebase grows.

This is the "shared-first" architecture, and it is a slow-motion disaster. It feels clean when you start — everything categorized by type, neatly separated. But type-based organization optimizes for the question nobody asks: "Show me all the validation schemas." Nobody has ever asked that. The question people actually ask is: "Show me everything about orders." And the answer is scattered across the entire tree.

The real cost shows up during maintenance. A developer needs to change how orders are created. They modify the form component, update the action, adjust the validation schema, and change the types. Four files in four directories. They forget to update the loading skeleton in a fifth directory. The PR looks clean because the reviewer can't see the missing change — it's in a directory nobody thought to check.

We've watched teams add a single field to a form and touch eight files across six directories. Not because the feature was complex, but because the architecture forced every concern into a different corner of the codebase. The cognitive overhead is enormous: you need a mental map of the entire project structure just to make a simple change.

Multiply this by every feature in the application and you get the real tragedy: new developers spend their first two weeks not learning the product or the business logic, but learning where things live.

## The Principle

Files live next to the route that uses them. A route directory is a self-contained unit — it has everything it needs to render, mutate, validate, and recover from errors. You share code only when three or more routes need it, and even then, you move it reluctantly.

This is colocation: the principle that things that change together should live together. It's not new — it's how React components work (JSX and logic in the same file), how CSS Modules work (styles next to the component), and how test files work (`.test.ts` next to the source). We're simply applying the same idea to the route level.

## The Pattern

### The anatomy of a route

Every route in the application follows the same structure. When you open a route directory, you see everything that route needs:

```
app/(protected)/orders/
├── page.tsx              # Server Component — fetches data, renders layout
├── actions.ts            # Server Actions — all mutations for this route
├── loading.tsx           # Loading skeleton — matches the real UI layout
├── error.tsx             # Error boundary — user-friendly recovery
├── components/           # Route-specific components
│   ├── OrderTable.tsx
│   ├── OrderFilters.tsx
│   ├── OrderItem.tsx
│   └── OrderItem.skeleton.tsx
└── CLAUDE.md             # Documentation for AI agents and new developers
```

The `page.tsx` is always a Server Component. It fetches data through repositories and passes it to client components. The `actions.ts` file contains every mutation this route can perform. The `loading.tsx` produces a skeleton that matches the actual layout — not a generic spinner. The `error.tsx` gives users a retry button instead of a white screen.

### When actions grow: the actions folder

When a route has more than three server actions, split them into individual files. Each file handles one mutation.

```
app/(protected)/orders/
├── actions/
│   ├── create-order.ts
│   ├── update-order.ts
│   ├── delete-order.ts
│   └── assign-order.ts
├── components/
│   ├── OrderTable.tsx
│   └── OrderForm.tsx
├── page.tsx
├── loading.tsx
└── error.tsx
```

Each action file follows the same pattern: validate with Zod, call the repository, revalidate the path.

```typescript
// actions/create-order.ts
"use server";
import { revalidatePath } from "next/cache";
import { createOrderSchema } from "@/app/_shared/validation/orders.schema";
import { createOrder } from "@/app/_shared/repositories/orders.repository";
import { createClient } from "@/lib/supabase/server";

export async function createOrderAction(input: unknown) {
  const validated = createOrderSchema.parse(input);
  const supabase = await createClient();
  const order = await createOrder(supabase, validated);
  revalidatePath("/orders");
  return { success: true, data: order };
}
```

### The sharing threshold: three routes

A component used by one route stays in that route's `components/` folder. A component used by two routes stays where it is — the second consumer imports it directly, and you note the cross-route dependency.

A component used by three or more routes gets promoted to the shared layer:

```
app/_shared/components/
├── entity-list/         # Generic list patterns
├── timeline/            # Activity timeline
├── metrics/             # KPI cards, charts
└── detail-sections/     # Section layouts
```

The threshold is three, not two, because premature abstraction is worse than a little duplication. Two usages might diverge. Three usages have established a pattern.

When you do promote a component, leave a re-export at the original location for backward compatibility. Existing imports continue to work. New imports use the shared path.

```typescript
// Original location — now a re-export
// app/(protected)/orders/components/StatusBadge.tsx
export { StatusBadge } from "@/app/_shared/components/StatusBadge";
```

### Never import across routes

This is the hard rule. A component in `orders/components/` must never be imported by `customers/components/`. Cross-route imports create invisible coupling — you change a component for one route and break another route that you didn't know was using it.

```typescript
// WRONG — cross-route import creates invisible coupling
import { OrderBadge } from "../orders/components/OrderBadge";

// RIGHT — if customers need it too, it belongs in _shared
import { OrderBadge } from "@/app/_shared/components/OrderBadge";
```

### Repositories and validation live in _shared from the start

Unlike components, repositories and validation schemas start in the shared layer. A repository represents a database table — it's inherently shared across the entire application. Validation schemas define data contracts — they belong next to the type system, not next to a specific route.

```
app/_shared/
├── repositories/
│   ├── orders.repository.ts
│   ├── customers.repository.ts
│   └── products.repository.ts
├── validation/
│   ├── orders.schema.ts
│   ├── customers.schema.ts
│   └── products.schema.ts
└── types/
    ├── orders.types.ts
    └── customers.types.ts
```

### The route audit checklist

Every route should pass this structural check:

| File | Purpose | Required |
|------|---------|----------|
| `page.tsx` | Server Component, data fetching | Yes |
| `actions.ts` or `actions/` | Server Actions for mutations | Yes |
| `loading.tsx` | Skeleton that matches real layout | Yes |
| `error.tsx` | Error boundary with retry | Yes |
| `components/` | Route-specific components | Yes |
| `CLAUDE.md` | Documentation for developers and agents | Yes |

If any of these are missing, the route is incomplete.

## The Business Case

- **Onboarding in hours.** A new developer opens the `orders/` directory and sees everything about orders. No mental map required. No asking "where do the types live?" The feature is the folder.
- **Fearless refactoring.** When you change a route, you know the blast radius. Everything that could break lives in one directory. Cross-route coupling is explicitly forbidden, so changes to one feature cannot silently break another.
- **Deletability.** When a feature is removed, you delete one directory. No orphaned components in `shared/`, no dead validation schemas, no lingering types. The codebase gets smaller, not just different.

## Try It

Install the Modh Playbook skills to enforce this pattern automatically:
```bash
# Add to your project
git submodule add https://github.com/modh-labs/playbook .agents/modh-playbook
./.agents/modh-playbook/install.sh
```
