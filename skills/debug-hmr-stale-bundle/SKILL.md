---
name: debug-hmr-stale-bundle
description: Diagnose and fix "module factory is not available. It might have been deleted in an HMR update" errors in Next.js + Turbopack dev. Use when you see module-evaluation errors pointing at innocent import lines, empty-object error boundary logs, or inexplicable route behavior that differs between browsers or subdomains. Activates when the root cause is a stale bundle in **browser storage**, not a code bug.
---

# Debug HMR Stale Bundle

## When This Skill Activates

Trigger on any of these symptoms in a Next.js 16 + Turbopack (or webpack HMR) dev environment:

- `Module [...] was instantiated because it was required from module [...], but the module factory is not available. It might have been deleted in an HMR update`
- Error boundary logs with empty object payload: `"route error" {}` (error has no enumerable fields — it's a raw module-eval failure)
- Stack trace points at innocent `import { X } from "lucide-react"` (or any shared library) lines that have not been touched
- The same URL behaves differently between incognito and regular browser
- The same URL behaves differently between `app.localhost:3000` and `localhost:3000` (or any subdomain swap)
- A hard refresh appears to fix it — until the next HMR update

## The One Question

> **Does it work in incognito — or on a different subdomain?**

If yes, the bug is not in your code. It is a **stale JS bundle sitting in browser disk cache** referencing internal HMR module IDs the dev server has since recompiled away.

## Decision Tree

```
Error: "module factory is not available"
  ↓
Does the same URL work in incognito?
  YES → Stale browser bundle. Go to Fix.
  NO  → Does the same path work on a different origin (drop/add `app.` prefix)?
          YES → Stale browser bundle for ONE origin only. Go to Fix.
          NO  → Genuine code bug. Read the stack trace.
```

## Core Rule

**Browser HTTP caches are keyed by origin** (scheme + host + port). `http://app.localhost:3000` and `http://localhost:3000` are different origins. That is why one can be poisoned while the other works. That is why incognito always works — fresh origin cache.

The dev server **does** send `Cache-Control: no-store`, but disk cache hits can still race the HMR update on the first page load after recompile. Once a stale bundle is cached for an origin, every subsequent request for that origin hits the stale JS until the cache is cleared.

## Fix — In Priority Order

### 1. Clear site data for the affected origin (most reliable)

```
DevTools → Application → Storage → Clear site data (tick everything)
```

Or right-click the reload button in Chrome → **Empty Cache and Hard Reload**.

Do this **per origin**. If you are seeing the bug on `app.localhost:3000`, clearing `localhost:3000` does nothing.

### 2. Work with "Disable cache" on — durable workflow

```
DevTools → Network → ☑ Disable cache
```

Only applies while DevTools is open. Keep it on for active dev. Zero effect on the real app. This is the standard Next.js dev workflow.

### 3. What does NOT fix it

```bash
# These look reasonable but do NOT help:
rm -rf .next .turbo             # stale bundle is in BROWSER storage
killall node                    # same reason
npm install                     # same reason
restart dev server              # only relevant if server itself is corrupt
```

The server-side cache wipe is orthogonal. Do it only if you suspect server-side corruption (rare). Browser cache is the 95% case.

## Anti-Patterns

### Reading the stack trace as if the error is real

```
at module evaluation (../../packages/ui/components/dropdown-menu.tsx:4:59)
   import { Check, ChevronRight, Circle } from "lucide-react";
   //                                    ^^^ "error is here"
```

This line of code is fine. It worked yesterday. The compiled module factory for `Circle` was invalidated by HMR and the browser is running old JS that expects it. Do not "fix" the import.

### Patching the library

Downgrading `lucide-react`, switching icon libraries, or ejecting the shadcn component is chasing the symptom. The library is not broken.

### Blaming a browser extension

Extensions can cause hydration warnings (rewriting `<output>` to `<div>`, etc.) but they do not cause module-factory errors. If the stack says "module factory", it is the bundle, not the DOM.

### Assuming the redirect is real

If the error cascade pushes you to a generic error page (a `/500`, `/outage`, etc.), **check the classifier**. A module-eval error usually will not match a real outage classifier (statusCode ≥ 500, specific error codes, etc.). The redirect may be leftover browser-history state from an earlier crash, not a fresh match.

## Audit Checklist

When another engineer reports "it's broken on my machine":

- [ ] Have them open the exact URL in incognito. If it works → stale cache.
- [ ] Have them try the same path on a different subdomain. If it works → stale cache for one origin.
- [ ] Check the error message for `module factory is not available` — the specific string.
- [ ] Check the stack — does it point at an `import X from "Y"` line in a shared UI module?
- [ ] Are the error boundary logs emitting empty objects (`{}`)? That is raw module-eval, not an error object.
- [ ] Fix: Clear site data for the affected origin. Confirm with hard reload.
- [ ] Durable: Recommend DevTools "Disable cache" on during active dev.

## Why This Keeps Happening

Turbopack (and webpack HMR before it) assigns compiled modules integer or hash-based IDs. When files change during dev, modules get recompiled and IDs shift. The dev server tells connected clients to invalidate via HMR messages. But the *disk cache* of the browser can deliver a cached JS response that references the **old** ID namespace. The client tries to resolve an old ID, the factory is no longer registered, boom.

This is why the error message is phrased apologetically ("It might have been deleted in an HMR update") — the Turbopack runtime literally does not know why the factory is missing, only that it is.

## Related

- Next.js 16 Turbopack docs: https://nextjs.org/docs/app/api-reference/config/next-config-js/turbo
- The `Cache-Control: no-store` header is sent for dev assets, but browser disk cache policy can still serve stale on race.
