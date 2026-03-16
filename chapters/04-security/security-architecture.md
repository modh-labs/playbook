---
title: "Security Architecture"
subtitle: "Defense in depth for multi-tenant SaaS"
chapter: 10
section: "Security"
seo_title: "Security Architecture for Multi-Tenant SaaS — Defense in Depth with Supabase, Clerk, TypeScript — 2026"
seo_description: "Defense-in-depth security architecture for multi-tenant SaaS: RLS, auth, input validation, encryption, security headers, webhook verification, and audit trails."
keywords: ["SaaS security", "multi-tenant security", "defense in depth", "RLS", "row level security", "webhook security", "Supabase security"]
reading_time: "10 min"
difficulty: "advanced"
tech_stack: ["Next.js", "Supabase", "TypeScript", "Clerk"]
business_case: "A single tenant isolation failure can end a SaaS company. Defense in depth ensures that no single layer's failure leads to a breach."
---

# Security Architecture

> "Security is not a feature you ship. It is a property you maintain at every layer, in every commit, through every dependency update."

## The Problem

You are building multi-tenant SaaS. Ten customers share the same database. Their data must be invisible to each other. This is not optional -- it is existential. A single cross-tenant data leak does not just trigger a compliance investigation. It destroys the trust that your entire business model depends on.

The naive approach is to check permissions in application code: every query includes a `WHERE organization_id = ?` clause, every server action validates the user's org before proceeding. This works until it does not. One developer forgets the check. One new feature queries a table without filtering. One refactor drops a condition that seemed redundant.

Application-level security is necessary but brittle. It relies on every developer, in every commit, never making a mistake. That is not a security model. That is a hope.

The alternative is defense in depth: security enforced at multiple independent layers, where no single layer's failure leads to a breach.

## The Principle

Defense in depth means that an attacker -- or a careless developer -- must defeat multiple independent controls to access data they should not see.

We stack seven layers:

| Layer | What It Does | Technology |
|-------|-------------|------------|
| **Identity** | Proves who you are | Auth provider (MFA, sessions, organizations) |
| **Authorization** | Proves what you can access | JWT claims fed into database policies |
| **Data Isolation** | Enforces tenant boundaries at the database | Row Level Security |
| **Input Validation** | Rejects malformed data before it reaches business logic | Zod schemas |
| **Encryption** | Protects data at rest and in transit | AES-256-GCM, HSTS, TLS |
| **Transport Security** | Prevents protocol-level attacks | Security headers, CSP, CORS |
| **Audit Trail** | Records who did what, when, and from where | Immutable audit logs |

Each layer operates independently. If authentication breaks, RLS still prevents data leakage. If a developer forgets input validation, the database policy still rejects the unauthorized write. If RLS has a gap, the audit trail captures the anomalous access.

The key insight: **trust is transitive, but verification must not be.** Each layer verifies independently. No layer trusts another layer's output without its own check.

## The Pattern

### Layer 1: Identity

Authentication is delegated to a dedicated identity provider. We never store passwords, manage sessions, or implement MFA ourselves.

```typescript
// middleware.ts — protect all routes except public ones
import { clerkMiddleware, createRouteMatcher } from "@clerk/nextjs/server";

const isPublicRoute = createRouteMatcher([
  "/",
  "/sign-in(.*)",
  "/sign-up(.*)",
  "/api/webhooks/(.*)",
]);

export default clerkMiddleware(async (auth, req) => {
  if (!isPublicRoute(req)) {
    await auth.protect();
  }
});
```

The identity provider issues JWTs that contain the user's organization ID. This claim flows into every subsequent layer.

### Layer 2: Authorization via Database Policies

The JWT's `org_id` claim is read by the database engine and enforced at the row level. This is not application code -- it is a database constraint that cannot be bypassed by any query, from any client, regardless of how it was constructed.

```sql
-- Every table with tenant data has this policy
ALTER TABLE "public"."orders" ENABLE ROW LEVEL SECURITY;

CREATE POLICY "tenant_isolation" ON "public"."orders"
FOR ALL USING (
  organization_id = (auth.jwt() ->> 'org_id')::text
);
```

This means you never write `WHERE organization_id = ?` in application code. The database handles it. You cannot forget it. You cannot bypass it.

### Layer 3: Input Validation

Every server action validates input with a Zod schema before touching business logic. Validation happens at the boundary -- where user input enters your system.

```typescript
// validation/orders.schema.ts
import { z } from "zod";

export const createOrderSchema = z.object({
  product_id: z.string().uuid(),
  quantity: z.number().int().positive().max(100),
  notes: z.string().max(500).optional(),
});

export type CreateOrderInput = z.infer<typeof createOrderSchema>;
```

```typescript
// Server action — validates before any business logic
"use server";
import { createOrderSchema } from "@/validation/orders.schema";

export async function createOrder(data: unknown) {
  const validated = createOrderSchema.parse(data);
  // Only valid, typed data reaches here
  return await orderRepository.create(validated);
}
```

SQL injection is structurally impossible when you use parameterized queries (which Supabase does automatically):

```typescript
// Parameterized — safe
const { data } = await supabase
  .from("orders")
  .select("*")
  .eq("id", userInput); // Supabase parameterizes this

// String concatenation — NEVER do this
const { data } = await supabase
  .rpc("get_order", { query: `id = '${userInput}'` }); // Vulnerable
```

### Layer 4: Encryption

Sensitive credentials stored in the database are encrypted at rest with AES-256-GCM. The encryption key lives in environment variables, never in code.

```typescript
import { encrypt, decrypt } from "@/lib/encryption/credentials";

// Store encrypted
const encryptedToken = encrypt(
  apiToken,
  process.env.INTEGRATION_ENCRYPTION_KEY!
);

// Retrieve and decrypt
const apiToken = decrypt(
  encryptedToken,
  process.env.INTEGRATION_ENCRYPTION_KEY!
);
```

API keys stored in the database are hashed with SHA-256. The plaintext is shown once at creation and never stored.

### Layer 5: Transport Security

Every response includes security headers that prevent entire classes of browser-based attacks:

```typescript
// next.config.mjs
async headers() {
  return [{
    source: "/(.*)",
    headers: [
      { key: "Strict-Transport-Security", value: "max-age=63072000; includeSubDomains; preload" },
      { key: "X-Content-Type-Options", value: "nosniff" },
      { key: "X-Frame-Options", value: "DENY" },
      { key: "X-XSS-Protection", value: "1; mode=block" },
      { key: "Referrer-Policy", value: "origin-when-cross-origin" },
      { key: "Permissions-Policy", value: "camera=(), microphone=(), geolocation=()" },
    ],
  }];
}
```

| Header | Attack Prevented |
|--------|-----------------|
| `Strict-Transport-Security` | Protocol downgrade, cookie hijacking |
| `X-Content-Type-Options` | MIME type sniffing XSS |
| `X-Frame-Options` | Clickjacking |
| `Permissions-Policy` | Unauthorized device access |
| `Referrer-Policy` | URL leakage to third parties |

### Layer 6: Webhook Security

Webhooks are the most dangerous attack surface in a SaaS application. They accept data from the internet and write to your database. Every webhook must verify its signature before processing.

```typescript
// Signature verification is non-negotiable
export async function POST(req: Request) {
  // CRITICAL: Use req.text(), not req.json()
  // Parsed JSON breaks signature verification
  const body = await req.text();
  const signature = req.headers.get("stripe-signature")!;

  const event = stripe.webhooks.constructEvent(
    body,
    signature,
    process.env.WEBHOOK_SECRET!
  );

  // Only process verified events
  await processEvent(event);
}
```

Additionally, we protect against replay attacks by rejecting stale events:

```typescript
const MAX_EVENT_AGE_SECONDS = 300; // 5 minutes

const eventAge = Math.floor(Date.now() / 1000) - event.created;
if (eventAge > MAX_EVENT_AGE_SECONDS) {
  return new Response("Event too old", { status: 400 });
}
```

And we enforce idempotency to prevent double-processing:

```typescript
// Check if event was already processed
const existing = await db
  .from("webhook_events")
  .select("id")
  .eq("provider", "stripe")
  .eq("event_id", event.id)
  .maybeSingle();

if (existing.data) {
  return new Response("Already processed", { status: 200 });
}
```

### Layer 7: Audit Trail

Every significant action is logged to an immutable audit table. The table has INSERT-only policies -- no updates, no deletes for regular users.

```typescript
await logAuditEvent({
  action: "order.created",
  entity_type: "order",
  entity_id: order.id,
  actor_id: userId,
  organization_id: orgId,
  ip_address: request.headers.get("x-forwarded-for"),
  changes: { status: { old: null, new: "pending" } },
});
```

What gets logged:
- Entity lifecycle events (create, update, delete)
- State transitions (status changes, assignments)
- Credential lifecycle (API key create, revoke, delete)
- Payment events (succeeded, failed, refunded)
- System events (webhook processing, scheduled jobs)

### PII Protection

Sensitive data is masked before it reaches logging and error tracking:

```typescript
import { maskEmail, maskPhone, maskApiKey } from "@/lib/pii";

// In logging — never log raw PII
logger.info("Processing order", {
  customer_email: maskEmail(email),  // "t***@example.com"
  phone: maskPhone(phone),           // "+1***4567"
});
```

Error tracking is configured to never send PII:

```typescript
Sentry.init({
  sendDefaultPii: false, // REQUIRED: prevents browser fingerprinting
});
```

### Environment Variable Discipline

Secrets never reach client-side code. Only `NEXT_PUBLIC_*` variables are exposed to the browser.

```bash
# Server only — never exposed
CLERK_SECRET_KEY=sk_...
SUPABASE_SERVICE_ROLE_KEY=eyJ...
STRIPE_WEBHOOK_SECRET=whsec_...

# Client safe — non-sensitive public keys
NEXT_PUBLIC_CLERK_PUBLISHABLE_KEY=pk_...
NEXT_PUBLIC_SUPABASE_URL=https://...
NEXT_PUBLIC_SUPABASE_ANON_KEY=eyJ...
```

Pre-commit hooks prevent `.env` files from being committed:

```json
{
  "*.env*": [
    "echo 'ERROR: Environment files should not be committed!' && exit 1"
  ]
}
```

## The Business Case

**Compliance readiness.** A defense-in-depth architecture maps directly to SOC 2 controls. When the auditor asks "How do you enforce access control?" you point to RLS policies. When they ask "How do you detect unauthorized access?" you point to audit logs. When they ask "How do you protect data in transit?" you point to HSTS preload. Each layer is a control, each control has evidence.

**Breach prevention.** In a single-layer architecture, one bug equals one breach. In a seven-layer architecture, an attacker must find and exploit vulnerabilities in multiple independent systems simultaneously. The probability of a successful breach drops exponentially with each independent layer.

**Developer confidence.** When security is enforced at the database layer, developers do not carry the cognitive burden of remembering to filter by organization on every query. They write straightforward code. RLS handles isolation. Zod handles validation. The architecture is secure by default, not secure by discipline.

**Customer acquisition.** Enterprise buyers require SOC 2, GDPR compliance, and encryption at rest before signing a contract. A documented security architecture with seven independent layers shortens the sales cycle from months to weeks.

The cost of implementing these layers up front is a fraction of the cost of retrofitting them after a breach -- both in engineering time and in lost trust.

## Try It

```bash
npx modh-playbook init security-architecture
```
