---
name: control-flow-exceptions
description: Some "errors" are control flow, not failures. `redirect()` and `notFound()` in Next.js work by THROWING — a naive `try/catch` swallows the signal, cancels the navigation, and renders the internal digest string ("NEXT_REDIRECT;...") to the user. Any `catch` block wrapping code that might redirect MUST call `unstable_rethrow(error)` as its first line. Triggers on `try/catch` around a server action, Server Component, or route handler in Next.js App Router.
---

# Control-Flow Exceptions

## When This Skill Activates

- A client component `await`s a server action inside a `try/catch`
- A server action, Server Component, or route handler calls `redirect()`,
  `permanentRedirect()`, or `notFound()` anywhere reachable from a `try`
- A user reports: "I see NEXT_REDIRECT in the toast" / "the error popup says
  NEXT_HTTP_ERROR_FALLBACK"
- A redirect "sometimes doesn't happen" — the action succeeds, the DB row is
  gone, but the user stays on the dead page
- A `catch (error)` does `toast.error(error.message)` and the wrapped code can
  navigate

## The Diagnostic Question

> **"Does anything inside this `try` perform navigation or control flow that
> works by *throwing*? If yes, does the `catch` re-throw that signal before
> handling real errors?"**

If the `catch` treats every thrown value as a failure, you have the bug.

## Why This Happens

Next.js implements `redirect()` and `notFound()` by **throwing a special
error**. The framework catches it at the render/action boundary and performs
the navigation. The thrown value is identified by a `digest` field:

- `NEXT_REDIRECT;<mode>;<url>;<status>;` — from `redirect()` / `permanentRedirect()`
- `NEXT_NOT_FOUND` — from `notFound()`
- `NEXT_HTTP_ERROR_FALLBACK;<status>` — from `forbidden()` / `unauthorized()`

These are **not failures**. They are how the framework unwinds the stack to
signal "navigate now." When a server action redirects, that thrown signal
propagates all the way back to the **client-side `await`** of the action. A
`try/catch` there will catch it like any other error — and if the `catch`
does `toast.error(error.message)`, the user sees the raw digest string AND the
navigation never completes.

## Decision Tree

```
catch (error) block
  │
  ├─ Can anything in the `try` redirect / notFound / call a redirecting action?
  │   │
  │   ├─ NO  → ✅ Handle errors normally. No rethrow needed.
  │   │
  │   └─ YES → Is `unstable_rethrow(error)` the FIRST line of the catch?
  │             │
  │             ├─ YES → ✅ Correct. Real errors fall through; signals re-throw.
  │             │
  │             └─ NO  → ❌ BUG. The catch swallows NEXT_REDIRECT.
  │                          Navigation is cancelled. User sees the digest
  │                          string in a toast / error UI.
```

## Core Rules

### Rule 1: `unstable_rethrow` is the first line of any catch that wraps redirectable code

```tsx
// ❌ WRONG — catch swallows the redirect signal
try {
  await deleteThingAction(id, { redirectAfter: "/things" });
} catch (error) {
  toast.error(error instanceof Error ? error.message : "Failed");
  // ↑ When the action redirected, error.message is "NEXT_REDIRECT;replace;
  //   /things;307;" — shown to the user, and the navigation never happens.
}

// ✅ RIGHT — re-throw control-flow signals, handle only real errors
import { unstable_rethrow } from "next/navigation";

try {
  await deleteThingAction(id, { redirectAfter: "/things" });
} catch (error) {
  unstable_rethrow(error); // re-throws NEXT_REDIRECT / NEXT_NOT_FOUND etc.
  toast.error(error instanceof Error ? error.message : "Failed");
}
```

`unstable_rethrow` inspects the value: if it's a Next.js control-flow signal it
re-throws it (letting the framework navigate); otherwise it returns and your
real error handling runs. Despite the `unstable_` prefix it is the
**officially documented** tool for exactly this seam.

### Rule 2: Server-side `redirect()` is the right pattern — don't "fix" it by removing the redirect

The redirect throwing is not the bug. Having the mutation own the post-mutation
navigation is *correct* — it avoids a client/server round-trip race and a flash
of just-deleted content. The bug is only that the client `catch` couldn't tell
a signal from a failure. Fix the `catch`, keep the `redirect()`.

### Rule 3: Server-side wrappers must let the signal propagate too

If you wrap server actions in a tracing/logging helper, that helper's own
`try/catch` must detect control-flow signals and re-throw them **without**
logging or capturing them to Sentry — otherwise every successful redirect
alerts ops.

```ts
function isNextControlFlowError(error: unknown): boolean {
  if (!error || typeof error !== "object" || !("digest" in error)) return false;
  const digest = (error as { digest?: unknown }).digest;
  if (typeof digest !== "string") return false;
  return digest.startsWith("NEXT_REDIRECT") || digest === "NEXT_NOT_FOUND";
}

try {
  return await action(...args);
} catch (error) {
  if (isNextControlFlowError(error)) throw error; // not a failure — propagate
  captureException(error);
  throw error;
}
```

### Rule 4: Don't `redirect()` inside a `try` you also use for error handling

Within a single server-side function, calling `redirect()` inside a `try`
whose `catch` does real work means you catch your own signal. Either put the
`redirect()` after the `try/catch`, or `unstable_rethrow` in the catch. The
cleanest shape: do fallible work in the `try`, `redirect()` on the success
path *after* it.

## Implementation Pattern: client mutation handler

```tsx
"use client";
import { unstable_rethrow, useRouter } from "next/navigation";
import { toast } from "sonner";

function useDeleteHandler(id: string, redirectAfter?: string) {
  const router = useRouter();

  return async () => {
    try {
      const result = redirectAfter
        ? await deleteThingAction(id, { redirectAfter }) // server redirect()s — never returns on success
        : await deleteThingAction(id);

      // Only reached when NOT redirecting:
      if (!result.success) {
        toast.error(result.error ?? "Failed to delete");
        return;
      }
      toast.success("Deleted");
      router.refresh();
    } catch (error) {
      // The server action redirected → re-throw so Next.js navigates.
      unstable_rethrow(error);
      // Genuine failure → surface it.
      toast.error(error instanceof Error ? error.message : "Something went wrong");
    }
  };
}
```

## Anti-Patterns

### Anti-pattern 1: Stringifying the caught error into UI

```tsx
// ❌ Leaks "NEXT_REDIRECT;replace;/x;307;" to users when the code redirected
catch (error) { toast.error(String(error)); }
```

### Anti-pattern 2: Detecting the digest by hand in client code

```tsx
// ❌ Brittle — the digest format is internal and changes between Next versions
catch (error) {
  if ((error as any)?.digest?.startsWith("NEXT_REDIRECT")) throw error;
  toast.error(...);
}
```
Use `unstable_rethrow` — it tracks every signal type (redirect, notFound,
forbidden, unauthorized, dynamic-usage bailouts) across versions.

### Anti-pattern 3: Removing server-side `redirect()` to "avoid the throw"

```tsx
// ❌ Trades a real architectural benefit away to dodge a 1-line fix
// action returns { success: true }; client does router.push() afterwards
```
This reintroduces the client/server race and the flash of deleted content the
server-side redirect was chosen to prevent. Keep the `redirect()`; fix the
`catch`.

### Anti-pattern 4: Capturing the signal to Sentry in a server wrapper

```ts
// ❌ Every successful redirect now pages on-call
catch (error) { captureException(error); throw error; }
```
Detect and skip control-flow signals before capturing.

## Audit Checklist

Find every client `catch` that wraps a server action:

```bash
rg -n -g '*.tsx' -B8 'catch \(' | rg -B8 'toast\.error|String\(error\)' | rg 'Action\('
```

For each `try/catch` wrapping a server action, Server Component, or route handler:

- [ ] Can anything in the `try` redirect, `notFound()`, or call an action that does?
- [ ] If yes, is `unstable_rethrow(error)` the **first** statement in the `catch`?
- [ ] Does the `catch` avoid stringifying the raw error into user-facing UI?
- [ ] If there's a server-side action wrapper (tracing/logging), does it
      re-throw control-flow signals **without** capturing them?
- [ ] Is there a regression test asserting a `NEXT_REDIRECT` rejection is
      re-thrown, not toasted?

## Testing the Fix

Use the **real** `unstable_rethrow` (don't stub it) so the test exercises the
actual signal-detection logic:

```tsx
vi.mock("next/navigation", async () => {
  const actual = await vi.importActual<typeof import("next/navigation")>("next/navigation");
  return { ...actual, useRouter: () => ({ push: vi.fn(), refresh: vi.fn() }) };
});

function makeRedirectError(path: string): Error {
  const err = new Error("NEXT_REDIRECT");
  (err as Error & { digest: string }).digest = `NEXT_REDIRECT;replace;${path};307;`;
  return err;
}

it("does not toast when the action redirects", async () => {
  mockAction.mockRejectedValue(makeRedirectError("/things"));
  await clickDelete();
  expect(toastError).not.toHaveBeenCalled();
  expect(toastSuccess).not.toHaveBeenCalled();
});

it("toasts a genuine error", async () => {
  mockAction.mockRejectedValue(new Error("db exploded"));
  await clickDelete();
  expect(toastError).toHaveBeenCalledWith("db exploded");
});
```

## Canonical Incident (origin story)

A B2B SaaS app, Next.js App Router. The call-delete flow: a server action
deletes the call row, then calls `redirect("/calls")` so the user lands on the
list in a single round-trip instead of briefly rendering against the deleted
record. The server-side tracing wrapper already knew to let `NEXT_REDIRECT`
propagate without a Sentry capture.

But the **client** dialog `await`ed the action inside a `try/catch`. When the
action redirected, the `NEXT_REDIRECT` signal surfaced at the client `await`,
the `catch` ran `toast.error(error.message)`, and the user saw a toast reading
`NEXT_REDIRECT;replace;/calls;307;` — while the navigation was cancelled.

The bug report was three words: *"we see NEXT_REDIRECT in the toast??"*

Fix: `unstable_rethrow(error)` as the first line of the `catch`. Two delete
dialogs shared the exact shape (`redirectAfter` option → server `redirect()`);
both were fixed and given regression tests in the same change. A
codebase-wide grep confirmed only those two server actions called `redirect()`
at the time — but the skill exists so the *next* redirecting action doesn't
rediscover this.

## Why This Bites Repeatedly

1. **"Throw to navigate" is counterintuitive.** Every other use of `throw`
   means failure. `redirect()` overloads it for control flow, so a
   well-meaning `try/catch` does exactly the wrong thing.
2. **It crosses the server/client boundary invisibly.** The signal originates
   server-side but only becomes a problem at the client `await` — two files,
   two mental models, no type that says "this can throw a navigation."
3. **The failure mode is silent in dev tooling.** No Sentry event (the server
   wrapper correctly skips it), no TypeScript error, no lint warning. The only
   evidence is the user-facing toast showing an internal digest string.

The fix is one line. The audit grep is mechanical. Codify it once.
