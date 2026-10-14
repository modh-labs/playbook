---
name: webhook-architecture
description: >
  Enforce SOLID principles in webhook architecture for maintainability and
  extensibility. Use when creating webhook routes, adding event handlers,
  building handler registries, or refactoring webhook code. Enforces registry
  pattern, single responsibility, and dependency injection.
---

# Webhook Architecture Skill

## When This Skill Activates

- Creating new webhook routes
- Adding new webhook event handlers
- Refactoring webhook architecture for maintainability
- Discussing webhook extensibility or testability
- Adding a new event type to an existing webhook endpoint

---

## Core Principles

### Single Responsibility (SRP)

- **Route handler**: HTTP concerns only (signature verification, routing, responses)
- **Event handlers**: Business logic for ONE event type each
- **Services**: Shared logic (organization resolution, side effects)

### Open/Closed (OCP)

- New handlers do NOT modify route.ts
- Use a handler registry for event routing
- Extend by adding files, not modifying existing ones

### Dependency Injection (DI)

- Pass execution context to handlers
- No hidden service creations inside handlers
- Testable, mockable dependencies

---

## Core Rules

### 1. Route Handler = HTTP Concerns ONLY

Route handlers should ONLY handle signature verification, request parsing, handler routing, and HTTP responses.

```typescript
// WRONG - Route doing business logic
export async function POST(req: Request) {
  const body = await req.json();

  if (body.type === "order.created") {
    const db = await createServiceClient();
    const { data } = await db
      .from("orders")
      .select("*")
      .eq("external_id", body.id)
      .single();
    // ... 200 lines of business logic ...
  }
}

// CORRECT - Route only handles HTTP
export async function POST(req: Request) {
  // 1. Verify signature
  const body = await req.text();
  const signature = req.headers.get("x-provider-signature");
  if (!verifySignature(body, signature)) {
    return NextResponse.json({ error: "Invalid signature" }, { status: 401 });
  }

  // 2. Parse and route to handler
  const parsed = JSON.parse(body);
  const { eventType, payload } = parseWebhook(parsed);
  const handler = WEBHOOK_HANDLERS[eventType];

  if (!handler) {
    return NextResponse.json({ success: true }); // ACK unknown events
  }

  // 3. Build context
  const context = await buildWebhookContext(payload, eventType);

  // 4. Execute handler
  await handler.execute(payload, context);

  // 5. Return HTTP response
  return NextResponse.json({ success: true });
}
```

### 2. Use Handler Registry Pattern (Open/Closed)

Adding new event types should NOT modify route.ts. Use a registry:

```typescript
// lib/handler-registry.ts
import type { z } from "zod";

export interface WebhookHandler<T = unknown> {
  /** Zod schema for payload validation */
  schema: z.ZodSchema<T>;
  /** Handler function */
  execute: (payload: T, context: WebhookContext) => Promise<WebhookResult>;
  /** Does this handler need organization context? */
  requiresOrganization?: boolean;
}

export interface WebhookContext {
  organizationId?: string;
  supabase: SupabaseClient;
  logger: WebhookLogger;
}

export interface WebhookResult {
  success: boolean;
  [key: string]: unknown;
}

// Register all handlers -- ONE place to add new events
export const WEBHOOK_HANDLERS: Record<string, WebhookHandler> = {
  "order.created": {
    schema: OrderCreatedSchema,
    execute: handleOrderCreated,
    requiresOrganization: true,
  },
  "order.cancelled": {
    schema: OrderCancelledSchema,
    execute: handleOrderCancelled,
    requiresOrganization: true,
  },
  "account.connected": {
    schema: AccountEventSchema,
    execute: handleAccountConnected,
    requiresOrganization: false,
  },
  // Adding new handler = add entry here + create handler file
  // NO changes to route.ts needed!
};
```

**Benefits of Registry Pattern**:
- Adding new handler = 1 registry entry + 1 handler file
- Validation schemas colocated with handlers
- Route.ts stays small (100-150 lines)
- Easy to test handlers in isolation
- Clear inventory of all supported events

### 3. Extract Organization Resolution to Service

Organization lookup is shared logic -- extract to a service:

```typescript
// lib/resolve-organization.ts

/**
 * Resolve organization ID from webhook payload.
 * Different providers store org context differently.
 */
export async function resolveOrganization(
  provider: string,
  payload: unknown
): Promise<string | undefined> {
  const db = await createServiceClient();

  switch (provider) {
    case "payment-provider": {
      // Check metadata first, then lookup by customer
      const metadata = (payload as any).metadata;
      if (metadata?.organization_id) return metadata.organization_id;
      const customerId = (payload as any).customer;
      const { data } = await db
        .from("billing")
        .select("organization_id")
        .eq("customer_id", customerId)
        .single();
      return data?.organization_id;
    }
    case "calendar-provider": {
      const configId = (payload as any).configuration_id;
      const { data } = await db
        .from("scheduling_configs")
        .select("organization_id")
        .eq("external_config_id", configId)
        .single();
      return data?.organization_id;
    }
    case "auth-provider": {
      return (payload as any).organization_id;
    }
  }
}
```

### 4. Pass Execution Context to Handlers

Handlers should receive all dependencies via context -- no hidden creations:

```typescript
// WRONG - Handler creates own dependencies
export async function handleOrderCreated(payload: OrderPayload) {
  const db = await createServiceClient();       // Hidden dependency
  const logger = createModuleLogger("orders");  // Hidden dependency
  // ...
}

// CORRECT - Dependencies injected via context
export async function handleOrderCreated(
  payload: OrderPayload,
  context: WebhookContext
): Promise<WebhookResult> {
  const { supabase, logger, organizationId } = context;
  // All dependencies explicit and testable
}
```

### 5. One Handler Per Event Type

Each handler file should handle ONE event type:

```
handlers/
  order-created.ts         # Only order.created
  order-cancelled.ts       # Only order.cancelled
  order-updated.ts         # Only order.updated
  account-connected.ts     # Only account.connected
  account-expired.ts       # Only account.expired
```

**NOT**:
```
handlers/
  order-handler.ts         # WRONG: Handles multiple events
  account-handler.ts       # WRONG: Big switch statement inside
```

### 6. Colocate Validation Schemas with Handlers

Keep Zod schemas near the code that uses them:

```typescript
// handlers/order-created.ts
import { z } from "zod";

export const OrderCreatedSchema = z.object({
  order_id: z.string().min(1),
  customer_email: z.string().email(),
  items: z.array(z.object({
    product_id: z.string(),
    quantity: z.number().positive(),
    price: z.number().nonnegative(),
  })),
  total: z.number().nonnegative(),
  created_at: z.number(),
});

export type OrderCreatedPayload = z.infer<typeof OrderCreatedSchema>;

export async function handleOrderCreated(
  payload: OrderCreatedPayload,
  context: WebhookContext
): Promise<WebhookResult> {
  // Handler implementation
}
```

---

## Adding a New Event Handler (Checklist)

1. **Create handler file**: `handlers/[event-name].ts`
   - Export Zod schema for payload validation
   - Export handler function accepting `(payload, context)`
   - Follow observability patterns (webhook logger lifecycle)

2. **Register in registry**: `lib/handler-registry.ts`
   - Add entry with schema, handler function, and flags
   - Set `requiresOrganization` appropriately

3. **Done!** No route.ts changes needed.

---

## Directory Structure

```
app/api/webhooks/[provider]/
  route.ts                     # HTTP concerns only (~100-150 lines)
  lib/
    handler-registry.ts        # Event -> handler mapping
    resolve-organization.ts    # Org resolution service
  handlers/
    order-created.ts           # One file per event
    order-cancelled.ts
    order-updated.ts
    account-connected.ts
```

---

## Common Mistakes

| Mistake | Impact | Fix |
|---------|--------|-----|
| Business logic in route.ts | Monolithic, untestable route | Extract to handler files |
| Big switch statements | Hard to extend, violates OCP | Use handler registry |
| Modifying route.ts for new events | Merge conflicts, risk to existing handlers | Use registry pattern |
| Hidden dependencies in handlers | Untestable, hard to mock | Pass via context |
| Multiple events per handler file | Violates SRP, hard to find code | One file per event |
| Inline validation schemas | Not reusable, not testable | Colocate and export from handler |
| Duplicated org lookup logic | DRY violation, inconsistent behavior | Extract to service |

---

## Quick Reference

| Concern | Location | Size Guide |
|---------|----------|------------|
| Signature verification | route.ts | ~10 lines |
| Event routing | route.ts -> registry | ~5 lines |
| Payload validation | registry + schema | ~20 lines |
| Org resolution | lib/resolve-organization.ts | ~30 lines |
| Business logic | handlers/*.ts | As needed |
| HTTP response | route.ts | ~5 lines |

**Target**: Route.ts should be <=200 lines. If larger, extract logic.

---

## Detailed References

- Generic TypeScript handler template: `references/handler-template.ts`
