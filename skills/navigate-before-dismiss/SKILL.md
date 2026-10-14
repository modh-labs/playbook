---
name: navigate-before-dismiss
description: When a single click handler both calls `router.push(...)` and closes a Radix dismissable (Dialog, Sheet, Popover, CommandDialog, DropdownMenu), navigate FIRST and defer the dismiss to a microtask. Triggers on any Next.js App Router + Radix UI codebase, especially command palettes and "click result to navigate" flows. Activates on `setOpen(false)` + `router.push` in the same handler.
---

# Navigate Before Dismiss

## When This Skill Activates

- A click handler contains both `router.push(...)` and `setOpen(false)` / `onOpenChange(false)`
- A Radix `Dialog`, `Sheet`, `Popover`, `CommandDialog`, or `DropdownMenu` wraps a Next.js `<Link>`
- A `cmdk` `CommandItem` uses `asChild` with a `<Link>` child
- A user reports: "clicking the result closes the popup but doesn't go anywhere"
- A user reports: "I click X, the dialog closes, but the URL never changes — refresh does nothing"
- A Playwright test for in-palette navigation flakes

## The Diagnostic Question

> **"Does this handler both close a Radix container and call `router.push`? If yes,
> which runs first?"**

If `setOpen(false)` runs first, you have the bug.

## Decision Tree

```
Click handler fires
  ├─ Calls router.push(...) AND closes a dismissable?
  │   ├─ Push runs FIRST?
  │   │   └─ ✅ Safe. Defer the dismiss in a microtask.
  │   │
  │   └─ Close runs FIRST?
  │       └─ ❌ BUG. Radix unmounts children mid-event.
  │              Next.js Link's intercepted navigation is cancelled.
  │              User sees popup close, URL never changes.
  │
  ├─ Click target is INSIDE the dismissable?
  │   └─ Risk is HIGHEST (the target itself gets unmounted).
  │
  └─ Click target is a form Submit button?
      └─ Risk is LOWER (React 19 batching usually rescues you),
         but the reorder is still defensive best-practice.
```

## Core Rules

### Rule 1: Push first, dismiss in a microtask

```tsx
// ❌ WRONG — dismiss before push
function handleClick() {
  setOpen(false);
  router.push("/somewhere");
}

// ✅ RIGHT — push first, defer dismiss
function handleClick() {
  router.push("/somewhere");
  queueMicrotask(() => setOpen(false));
}
```

**Why a microtask?** `queueMicrotask` defers `setOpen(false)` to the
microtask queue that runs *after* the current synthetic-event handler
returns. By then, `router.push` has already written to the history API
and React has registered the navigation intent. The dismiss-driven unmount
can no longer cancel it.

### Rule 2: One navigation path per click

When a Radix item uses `asChild` with a `<Link>`, both `onSelect` (Radix)
and `<a>` click default behavior fire. Pick one:

```tsx
// ✅ Canonical: cmdk asChild + Link, with preventDefault on the anchor
<CommandItem asChild onSelect={() => onNavigate(href)}>
  <Link
    href={href}
    onClick={(e) => {
      e.preventDefault();          // ← cmdk.onSelect owns the React-driven nav
      onNavigate(href);
    }}
  >
    {children}
  </Link>
</CommandItem>
```

- `e.preventDefault()` blocks the anchor's React-driven default click,
  leaving cmdk's `onSelect` as the single, well-ordered navigation path.
- The anchor's `href` attribute is untouched, so **middle-click** opens a
  new tab and **right-click → "Copy link address"** still works.

### Rule 3: Dedupe duplicate-trigger handlers

If two paths (e.g. `CommandItem.onSelect` AND `Link.onClick`) can both fire
the same handler within ~400ms, add a `useRef` dedup so only the first wins:

```tsx
const lastRef = useRef<{ key: string; t: number } | null>(null);
const PALETTE_NAV_DEDUP_MS = 400;

function onNavigate(href: string) {
  const t = performance.now();
  if (lastRef.current?.key === href && t - lastRef.current.t < PALETTE_NAV_DEDUP_MS) {
    return;
  }
  lastRef.current = { key: href, t };

  router.push(href);
  queueMicrotask(() => setOpen(false));
}
```

## Implementation Pattern: `usePaletteNavigate` Hook

Extract the ordering rule into a hook so every dismissable+navigation
combo in the codebase follows it:

```tsx
import { useCallback, useRef } from "react";
import type { useRouter } from "next/navigation";

const DEDUP_MS = 400;

export function useNavigateBeforeDismiss(
  router: ReturnType<typeof useRouter>,
  dismiss: () => void,
) {
  const lastRef = useRef<{ key: string; t: number } | null>(null);

  return useCallback(
    (href: string) => {
      const t = performance.now();
      if (lastRef.current?.key === href && t - lastRef.current.t < DEDUP_MS) {
        return;
      }
      lastRef.current = { key: href, t };

      router.push(href, { scroll: false });
      queueMicrotask(dismiss);
    },
    [router, dismiss],
  );
}
```

## Anti-Patterns

### Anti-pattern 1: Synchronous close, then push

```tsx
// ❌ Causes silent navigation failures inside Radix dismissables
onSelect={() => {
  setOpen(false);
  router.push(href);
}}
```

### Anti-pattern 2: Trying to fix it with `setTimeout(..., 0)`

```tsx
// ❌ Works but is sloppy; microtasks (queueMicrotask) are the correct primitive
setTimeout(() => setOpen(false), 0);
```

`setTimeout(fn, 0)` schedules a macrotask, which runs after rendering.
`queueMicrotask` runs *between* the event handler and the next render —
it's the minimal correct deferral.

### Anti-pattern 3: Removing the anchor entirely

```tsx
// ❌ Breaks middle-click and "Copy link address"
<CommandItem onSelect={() => router.push(href)}>
  {children}
</CommandItem>
```

The anchor's `href` attribute is what makes middle-click work. Keep the
`<Link>`, just `preventDefault()` its click handler so it doesn't double-fire.

### Anti-pattern 4: Using `<a href>` instead of Next.js `<Link>`

```tsx
// ❌ Triggers a full-page reload, defeating client-side routing
<a href={href} onClick={(e) => { e.preventDefault(); router.push(href); }}>
```

Always use Next.js `<Link>` so prefetch + soft navigation still work.

## Audit Checklist

Run this grep across the codebase:

```bash
rg -n -g '*.tsx' -g '*.ts' -l 'onOpenChange\|setOpen\(false\)' src \
  | xargs -I{} rg -l 'router\.push' {}
```

For every matching file, verify:

- [ ] Does any single handler call `router.push` AND a dismiss in the same scope?
- [ ] If yes, does the dismiss come AFTER `router.push`?
- [ ] If yes, is the dismiss wrapped in `queueMicrotask` (or another deferral)?
- [ ] If the click target is a `<Link>` inside a dismissable, does its
      `onClick` use `e.preventDefault()` so navigation only fires once?
- [ ] Is there a dedup ref guarding against double-fire from `onSelect` +
      `onClick`?

## Canonical Incident (origin story)

Aura (B2B SaaS, Next.js App Router + Radix + cmdk). A user reported:

> "I search Hussain in the ⌘K palette. There's a long wait. I click Hussain.
> The popup disappears. I'm still on the upcoming calls tab. Refresh doesn't
> help."

Investigation found two stacked bugs (see Aura ticket AUR-1241, commit `c7b6471d2`):

1. **The navigation bug:** `usePaletteNavigate` called `setOpen(false)` before
   `router.push`. The Radix `CommandDialog` unmounted the inner Next.js
   `<Link>` mid-click. Next.js's intercepted navigation was silently cancelled.
   No URL change. No history entry. Refresh did nothing because the route
   never transitioned.

2. **The slowness:** unrelated — an N+1-style query for matched leads' calls
   with no `LIMIT`.

Fix: reorder push-before-dismiss with `queueMicrotask`, collapse the dual
`onSelect` + `onClick` handlers via `preventDefault`, keep anchor `href`
intact for middle-click.

The same defensive reorder was applied to a sibling `CreateLeadDialog`
flow in the same workstream — same shape, lower risk.

## Why This Bites Repeatedly

Three forces conspire:

1. **Radix is synchronous about close.** `onOpenChange(false)` doesn't
   queue an animation-aware unmount — it starts unmounting children on the
   next render commit. There's no built-in "wait for the click to settle."
2. **Next.js Link's click handler is React-driven.** It intercepts the
   anchor's default action and calls `router.push` internally. If the
   `<Link>` is unmounted before that interception completes, the push is
   never dispatched.
3. **The dev experience is opaque.** No error, no warning, no Sentry event.
   The user sees "click → popup closes → nothing." Refresh confirms the URL
   never changed. The bug looks like a routing problem, not a component
   ordering problem.

The fix is two lines and applies everywhere. The audit grep is mechanical.
This is exactly the kind of cross-cutting concern that benefits from being
codified as a skill rather than rediscovered every six months.
