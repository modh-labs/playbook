---
name: nextjs-server-client-boundary
description: 'Enforce the server/client module boundary in Next.js App Router projects. Use when creating client components, providers, hooks, or debugging "node: protocol" errors in Storybook/webpack/test environments. Prevents client components from importing server-side modules.'
---

# Next.js Server/Client Boundary

## When This Skill Activates

- Creating or modifying a `"use client"` component
- A component imports from a `repositories/`, `server/`, or database module
- Storybook/webpack build fails with `node:async_hooks`, `node:crypto`, or similar
- A provider component needs to trigger a server-side mutation
- Reviewing code for proper separation of concerns

## The One Question

> **Does this `"use client"` file import — directly or transitively — from any module that uses Node.js built-ins, database clients, or server-only APIs?**

If yes, you have a boundary violation. Fix it before it breaks your tooling.

## Why This Matters

Next.js App Router has two worlds:

```
SERVER WORLD                    CLIENT WORLD
─────────────                   ─────────────
Server Components               Client Components ("use client")
Server Actions ("use server")   React hooks (useState, useEffect)
Repositories (DB access)        Browser APIs (localStorage, Intl)
Node.js built-ins               Event handlers
```

The boundary between them is **one-directional**:

```
Client → can call → Server Actions (via RPC)
Client → can import → types (type-only imports are erased at build)
Client → CANNOT import → repositories, server-only modules

Server → can import → anything
Server → passes data → to Client via props
```

When a client component imports a server module, the bundler (webpack/Turbopack) tries to include that module in the browser bundle. Server modules import `node:async_hooks`, `node:crypto`, etc. — these don't exist in browsers. The result:

- **Storybook**: `UnhandledSchemeError: Reading from "node:async_hooks" is not handled`
- **Tests**: Module resolution failures in jsdom/vitest
- **Production**: Works in Next.js (it has special handling), but the code is architecturally broken

## Decision Tree

```
Is this a "use client" file?
├─ NO → You can import anything. No boundary issue.
└─ YES → Check each import:
    ├─ From types/ or lib/ (no node: deps) → SAFE
    ├─ From actions/ ("use server") → SAFE (Next.js handles the RPC)
    ├─ From repositories/ → VIOLATION — fix it
    ├─ From server-only services/ → VIOLATION — fix it
    └─ From @clerk/nextjs/server, @supabase/supabase-js (server) → VIOLATION
```

## Core Rules

### Rule 1: Client components import from `actions/`, never `repositories/`

```typescript
// ❌ VIOLATION: Client importing repository
"use client"
import { updateUser } from "@/repositories/users.repository";
// This pulls in Supabase → node:async_hooks → build crash

// ✅ CORRECT: Client importing server action
"use client"
import { updateUserAction } from "@/actions/user.actions";
// Server action is called via RPC — no server code in client bundle
```

### Rule 2: Providers accept data as props, don't fetch internally

```typescript
// ❌ VIOLATION: Provider imports repository
"use client"
import { getCurrentUser } from "@/repositories/users.repository";

export function UserProvider({ children }) {
  useEffect(() => { getCurrentUser().then(setUser) }, []);
  // ...
}

// ✅ CORRECT: Server component fetches, provider receives props
// In page.tsx (server component):
const user = await getCurrentUser();
return <UserProvider user={user}>{children}</UserProvider>;

// In UserProvider.tsx (client component):
"use client"
export function UserProvider({ user, children }) {
  return <UserContext.Provider value={user}>{children}</UserContext.Provider>;
}
```

### Rule 3: If a provider MUST trigger a server mutation, use a server action

```typescript
// ❌ VIOLATION: Provider calls repository function
"use client"
import { updateTimezone } from "@/repositories/users.repository";

useEffect(() => {
  updateTimezone(detected); // Direct repository call from client
}, []);

// ✅ CORRECT: Provider calls server action
"use client"
import { persistTimezone } from "@/actions/timezone.actions";

useEffect(() => {
  persistTimezone(detected); // Server action — Next.js handles the RPC
}, []);
```

### Rule 4: Type-only imports from server modules are safe

```typescript
// ✅ SAFE: type-only imports are erased at build time
import type { Call } from "@/repositories/calls.repository";

// ⚠️ BUT PREFER: importing from a dedicated types file
import type { Call } from "@/types/calls.types";
// This is cleaner and makes the boundary explicit
```

## Implementation Pattern

When you need to add server functionality to a client component:

### Step 1: Create a server action

```typescript
// actions/timezone.actions.ts
"use server"
import { updateTimezone } from "@/repositories/users.repository";

export async function persistTimezone(tz: string): Promise<void> {
  await updateTimezone(tz);
}
```

### Step 2: Import the action in the client component

```typescript
// providers/TimezoneProvider.tsx
"use client"
import { persistTimezone } from "@/actions/timezone.actions";
// NOT: import { updateTimezone } from "@/repositories/users.repository"
```

### Step 3: The action works everywhere

- **Next.js**: Calls the action via RPC (automatic)
- **Storybook**: Mocked via webpack alias
- **Tests**: Mocked via `vi.mock()`

## Anti-Patterns

### 1. "It works in Next.js, so it's fine"

Next.js has special handling that makes boundary violations work in production. But they break everywhere else. Design for portability.

### 2. "I'll just mock it in Storybook"

If you need a webpack mock to render a component, the component has a boundary violation. Fix the component, don't add mocks. Mocks should only be needed for third-party services (Clerk, Sentry), not your own code.

### 3. "It's just a type import"

`import type { X }` is safe. But `import { X }` (even if X is only used as a type) pulls in the module. Use explicit `type` imports.

### 4. Dual-mode components

```typescript
// ❌ Component that sometimes fetches, sometimes receives props
function Details({ id, data }: { id?: string; data?: Data }) {
  if (data) return <Render data={data} />;
  // Falls back to fetching — this is two components pretending to be one
  const fetched = useFetch(id);
  return <Render data={fetched} />;
}
```

Split into a data-fetching parent and a pure rendering child.

## Audit Checklist

Run this against any `"use client"` file:

- [ ] No imports from `repositories/` (except `type` imports)
- [ ] No imports from server-only `services/`
- [ ] No imports from modules that use `node:` built-ins
- [ ] Props interface is exported
- [ ] Component receives data via props (not internal fetching)
- [ ] Any server mutations use server actions, not repository functions
- [ ] Component renders correctly in Storybook without custom webpack mocks
- [ ] Provider components accept data as props from server parent

## The Import Chain

```
                    ┌─────────────────────────┐
                    │    Server Components     │
                    │    (page.tsx, layout)     │
                    └──────────┬──────────────┘
                               │ fetches data via
                               ▼
                    ┌─────────────────────────┐
                    │     Repositories         │
                    │  (database access)       │
                    └──────────┬──────────────┘
                               │ returns typed data
                               ▼
                    ┌─────────────────────────┐
          props ──▶ │   Client Components      │ ◀── "use client"
                    │  (interactive UI)        │
                    └──────────┬──────────────┘
                               │ mutations via
                               ▼
                    ┌─────────────────────────┐
                    │    Server Actions         │
                    │  ("use server")           │
                    └──────────┬──────────────┘
                               │ calls
                               ▼
                    ┌─────────────────────────┐
                    │     Repositories         │
                    └─────────────────────────┘
```

Data flows down (props), mutations flow through server actions. Client never touches repositories directly.
