---
title: "Design Standards"
subtitle: "shadcn/ui, semantic tokens, premium by default"
chapter: 22
section: "Frontend Craft"
seo_title: "Design Standards — shadcn/ui, Semantic Tokens, Premium by Default 2026"
seo_description: "Stop writing raw HTML and hardcoding colors. Use shadcn/ui for every interactive element, semantic tokens for theming, and build interfaces that feel expensive from day one."
keywords: ["design standards", "shadcn/ui", "design tokens", "Tailwind CSS", "component library", "UI standards"]
reading_time: "9 min"
difficulty: "intermediate"
tech_stack: ["Next.js", "Supabase", "TypeScript"]
business_case: "Premium UI increases trial-to-paid conversion. Users judge software quality by its surface in the first 30 seconds. Consistent design is not polish — it is product-market signal."
---

# Design Standards

> "If your SaaS looks like a hackathon project, it doesn't matter how good the backend is. Users closed the tab."

## The Problem

Pull up the average SaaS application built by a backend-heavy team. Click through three pages. You'll see it immediately: the login page has round corners, the dashboard has square ones. The primary button is blue on one page and purple on another. The spacing between cards is 16px in one section and 24px in the one right next to it. The loading state is a centered spinner on one page and a skeleton on the next.

Nobody made these inconsistencies deliberately. They happened because five developers built five features over five months, and each one made reasonable local decisions that produced incoherent global results. Developer A used `bg-blue-600` because it looked right. Developer B used `bg-violet-600` because that's what they saw on another page. Developer C used `bg-primary` because they read the docs. Three different blues in one application.

The customer doesn't see "three different blues." They see "unfinished." They see "this team doesn't pay attention to details." And they unconsciously extrapolate: if the interface is sloppy, the data handling is probably sloppy too. If the loading states are inconsistent, the error handling is probably inconsistent too.

This is the compound interest of design debt. Each individual inconsistency is trivial. Together, they communicate a lack of care that erodes trust. Users can't articulate it — they just say "it doesn't feel professional" and they look at alternatives.

The tragic part is that fixing this doesn't require a designer. It requires discipline. A component library, semantic tokens, and the conviction to never write a raw `<button>` element.

## The Principle

Every interactive element uses shadcn/ui. Every color references a semantic token. Every spacing value uses the Tailwind scale. No exceptions, no shortcuts, no "I'll just use a raw div with some classes this one time."

Premium is the default. Not because we're optimizing for beauty — because consistency is the cheapest way to communicate competence, and competence is what converts trials to paid subscriptions.

## The Pattern

### shadcn/ui for every interactive element

This is the hard rule. If a user can click it, type in it, select it, toggle it, or dismiss it, it must be a shadcn/ui component. No raw HTML elements for interactive UI.

```typescript
// WRONG — raw HTML masquerading as a component
<button className="px-4 py-2 bg-blue-500 text-white rounded hover:bg-blue-600">
  Create Order
</button>
<input className="border rounded px-3 py-2 w-full" placeholder="Search..." />
<select className="border rounded px-3 py-2">
  <option>All</option>
  <option>Active</option>
</select>

// RIGHT — shadcn/ui components with consistent behavior
<Button>Create Order</Button>
<Input placeholder="Search..." />
<Select>
  <SelectTrigger>
    <SelectValue placeholder="Filter by status" />
  </SelectTrigger>
  <SelectContent>
    <SelectItem value="all">All</SelectItem>
    <SelectItem value="active">Active</SelectItem>
  </SelectContent>
</Select>
```

Why this matters beyond consistency: shadcn/ui components handle focus management, keyboard navigation, screen reader announcements, and disabled states correctly. A raw `<button>` doesn't. A raw `<select>` doesn't match your theme. Every time you skip the component library, you skip accessibility and theming for free.

### Semantic color tokens

Colors are referenced by their purpose, not their value. This is what makes dark mode, theme customization, and visual consistency possible:

```typescript
// WRONG — hardcoded colors that break in dark mode and drift between pages
<div className="bg-white text-gray-900 border-gray-200">
  <h1 className="text-gray-900">Orders</h1>
  <p className="text-gray-500">Manage your orders</p>
  <Button className="bg-violet-600 hover:bg-violet-700">Create</Button>
</div>

// RIGHT — semantic tokens that adapt to any theme
<div className="bg-background text-foreground border-border">
  <h1 className="text-foreground">Orders</h1>
  <p className="text-muted-foreground">Manage your orders</p>
  <Button>Create</Button>  {/* Uses primary color by default */}
</div>
```

The semantic tokens are defined in your CSS and adapt to light/dark mode automatically:

| Token | Purpose | Light Mode | Dark Mode |
|-------|---------|------------|-----------|
| `background` | Page background | white | slate-950 |
| `foreground` | Primary text | slate-900 | slate-50 |
| `muted` | De-emphasized backgrounds | slate-100 | slate-800 |
| `muted-foreground` | Secondary text | slate-500 | slate-400 |
| `primary` | Brand color, primary actions | violet-600 | violet-400 |
| `destructive` | Dangerous actions | red-600 | red-400 |
| `border` | Borders and dividers | slate-200 | slate-800 |
| `ring` | Focus indicators | violet-600 | violet-400 |

Never reference a Tailwind color directly in a component. Always use the semantic token. If `bg-violet-600` appears in your code, it should only be in `globals.css` where you define what `primary` means.

### Button variants: use the right one

shadcn/ui provides five button variants. Each communicates a different level of emphasis:

```typescript
// Primary actions — the thing the user most likely wants to do
<Button variant="default">Create Order</Button>

// Secondary actions — alternatives to the primary
<Button variant="secondary">Save Draft</Button>

// Destructive actions — irreversible operations
<Button variant="destructive">Delete Order</Button>

// Outline — for less prominent but still visible actions
<Button variant="outline">Export</Button>

// Ghost — for tertiary actions that shouldn't compete for attention
<Button variant="ghost">Cancel</Button>
```

A page should have at most one `default` button visible at a time. If everything is primary, nothing is primary.

### Spacing: use the scale

Tailwind's spacing scale is a deliberate system. Use it. Don't invent custom values.

```typescript
// WRONG — arbitrary values that create visual noise
<div className="p-[13px] mt-[7px] gap-[11px]">

// RIGHT — consistent spacing from the scale
<div className="p-4 mt-2 gap-3">
```

Standard spacing patterns:

| Context | Token | Pixels |
|---------|-------|--------|
| Between list items | `space-y-2` | 8px |
| Between sections | `space-y-6` | 24px |
| Card padding | `p-4` or `p-6` | 16px or 24px |
| Page padding | `p-6` or `p-8` | 24px or 32px |
| Between form fields | `space-y-4` | 16px |

### Conditional classes with cn()

Use the `cn()` utility for conditional styling. No ternary expressions in className strings. No string concatenation.

```typescript
import { cn } from "@/lib/utils";

<div
  className={cn(
    "rounded-lg border p-4",              // Base styles — always applied
    isActive && "border-primary bg-accent", // Conditional — active state
    isDisabled && "opacity-50 cursor-not-allowed", // Conditional — disabled
    className                               // Override — from parent
  )}
/>
```

### Loading skeletons that match the layout

Every route has a `loading.tsx` that produces a skeleton matching the real UI. Not a spinner. Not a generic placeholder. A skeleton that occupies the same visual space as the content it replaces.

```typescript
// loading.tsx
import { Skeleton } from "@/components/ui/skeleton";

export default function OrdersLoading() {
  return (
    <div className="space-y-6 p-6">
      {/* Toolbar area */}
      <div className="flex items-center justify-between">
        <Skeleton className="h-10 w-64" />  {/* Search bar */}
        <Skeleton className="h-10 w-32" />  {/* Create button */}
      </div>

      {/* Table area */}
      <div className="space-y-2">
        <Skeleton className="h-12 w-full" /> {/* Header row */}
        <Skeleton className="h-16 w-full" /> {/* Data row */}
        <Skeleton className="h-16 w-full" />
        <Skeleton className="h-16 w-full" />
        <Skeleton className="h-16 w-full" />
      </div>
    </div>
  );
}
```

The skeleton's dimensions should approximate the real content. When the data loads, the transition from skeleton to content should feel like a reveal, not a layout shift.

### Empty states with purpose

Never show a blank area when there's no data. Every empty state has an icon, a message, and — when appropriate — an action:

```typescript
{orders.length === 0 && (
  <div className="flex flex-col items-center justify-center p-12 text-center">
    <Package className="h-12 w-12 text-muted-foreground" />
    <h3 className="mt-4 text-lg font-semibold">No orders yet</h3>
    <p className="mt-2 text-muted-foreground">
      Create your first order to get started
    </p>
    <Button className="mt-6">
      <Plus className="mr-2 h-4 w-4" />
      Create Order
    </Button>
  </div>
)}
```

Contextual empty states matter too. If the user has orders but their search returned nothing, say "No orders match your search" — not "Create your first order."

### Error boundaries with recovery

Every route has an `error.tsx` that gives users a way back:

```typescript
"use client";
import { Button } from "@/components/ui/button";
import { AlertTriangle, RefreshCcw } from "lucide-react";

export default function OrdersError({
  error,
  reset,
}: {
  error: Error & { digest?: string };
  reset: () => void;
}) {
  return (
    <div className="flex h-[calc(100vh-4rem)] flex-col items-center justify-center gap-6">
      <AlertTriangle className="h-12 w-12 text-destructive" />
      <h2 className="text-xl font-semibold">Something went wrong</h2>
      <p className="text-muted-foreground">
        We couldn't load your orders. Please try again.
      </p>
      <Button onClick={reset}>
        <RefreshCcw className="mr-2 h-4 w-4" />
        Try Again
      </Button>
    </div>
  );
}
```

A white screen is a dead end. An error boundary with a retry button is a speed bump.

## The Business Case

- **Trial conversion.** Users form their impression of software quality within 30 seconds. Consistent spacing, proper loading states, and a coherent color system communicate "this team knows what they're doing." Inconsistent UI communicates the opposite. This directly impacts trial-to-paid conversion.
- **Development velocity.** When every developer uses the same component library with the same tokens, there are no "which shade of blue?" discussions. No "how should this button look?" decisions. The system answers those questions. Developers build features, not design systems.
- **Automatic dark mode.** Semantic tokens mean dark mode is a CSS toggle, not a feature. Every component that uses tokens gets dark mode for free. Every component that hardcodes colors needs a separate dark mode implementation.

## Try It

Install the Modh Playbook skills to enforce this pattern automatically:
```bash
# Add to your project
git submodule add https://github.com/modh-labs/playbook .agents/modh-playbook
./.agents/modh-playbook/install.sh
```
