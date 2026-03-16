---
title: "Multi-Tenant Security"
subtitle: "RLS: the database does the auth checking"
chapter: 7
section: "Architecture"
seo_title: "Multi-Tenant Security with Row Level Security & Supabase — Best Practices 2026"
seo_description: "Stop writing authorization checks in application code. Row Level Security enforces tenant isolation at the database level, making cross-tenant data leaks impossible."
keywords: ["multi-tenant", "row level security", "RLS", "Supabase", "tenant isolation", "authorization", "defense in depth"]
reading_time: "8 min"
difficulty: "advanced"
tech_stack: ["Next.js", "Supabase", "TypeScript"]
business_case: "Makes cross-tenant data leaks structurally impossible instead of relying on developers to remember WHERE clauses in every query."
---

# Multi-Tenant Security

> "Authorization bugs don't show up in tests. They show up in lawsuits."

## The Problem

Every multi-tenant application has the same nightmare lurking in its codebase: a query without a `WHERE organization_id = ?` clause. One missing filter and Customer A can see Customer B's data. It's the most common security vulnerability in SaaS applications, and it's the hardest to catch in code review because the absence of a line is invisible.

Here's how it typically happens. A developer writes a new feature — a product search page. They write the query, add pagination, wire up the UI. Everything works in development, where there's only one organization's test data. The PR gets reviewed. The reviewer reads the query, sees it looks correct, and approves it. No one notices that the query doesn't filter by organization because the results look right in a single-tenant test environment.

In production, the search returns products from every organization. Sometimes a customer notices. Sometimes they don't — they just see unfamiliar products and assume they're demo data. Sometimes a competitor sees the other company's pricing.

The root cause isn't negligence. It's architecture. When tenant isolation depends on every developer remembering to add a filter to every query, it's only a matter of time before someone forgets. Code review can't reliably catch the absence of a line among hundreds of lines changed. Tests pass because test environments are single-tenant.

Application-level authorization is a bet that no developer, ever, across the lifetime of the codebase, will forget a single WHERE clause. That's not a bet we're willing to take.

## The Principle

Move authorization out of application code and into the database. Row Level Security (RLS) policies run on every query, automatically, regardless of how the query was constructed. The database becomes the authorization layer — not a suggestion, but an enforcement mechanism that cannot be bypassed by application bugs.

This is defense in depth applied to data access. The application still authenticates users and validates their roles. But the database independently enforces that every row returned belongs to the authenticated user's organization. Even if the application has a bug, even if a query is missing a filter, the database will not return rows that violate the policy.

## The Pattern

### The authentication chain

The security model is a pipeline. Each layer adds a guarantee that the next layer trusts.

```
User Request
  -> Identity Provider (verify who they are)
    -> JWT with org_id claim (scope their context)
      -> Supabase client (authenticated with JWT)
        -> RLS Policy (filter every query by org_id)
          -> Repository (executes query)
            -> Response (only this org's data, guaranteed)
```

The identity provider authenticates the user and issues a JWT containing the user's organization ID. The database client is initialized with this JWT. Every query that hits the database passes through RLS policies that read `org_id` from the JWT and filter rows accordingly.

### RLS policies: one pattern, every table

Every table that holds tenant data gets the same policy. The policy reads the organization ID from the authenticated user's JWT and filters rows to match.

```sql
-- Enable RLS on the table
ALTER TABLE "public"."orders" ENABLE ROW LEVEL SECURITY;

-- Authenticated users can only access their own org's data
CREATE POLICY "org_isolation" ON "public"."orders"
  FOR ALL
  USING (organization_id = (auth.jwt() ->> 'org_id')::text);
```

This single policy covers SELECT, INSERT, UPDATE, and DELETE. A user in Organization A literally cannot read, write, or delete Organization B's orders. The database won't return the rows, and it won't accept writes to rows that don't match.

### Role-based access within a tenant

RLS can enforce role-based permissions within an organization. Admin-only tables restrict access based on the user's role claim.

```sql
-- Only admins can manage billing settings
CREATE POLICY "admin_only" ON "public"."billing_settings"
  FOR ALL
  USING (
    organization_id = (auth.jwt() ->> 'org_id')::text
    AND (auth.jwt() ->> 'org_role') = 'org:admin'
  );

-- All members can read their own org's products
CREATE POLICY "member_read" ON "public"."products"
  FOR SELECT
  USING (
    organization_id = (auth.jwt() ->> 'org_id')::text
  );
```

### Service role: the escape hatch

Webhooks and background jobs run outside a user's authentication context. They use a service-role client that bypasses RLS entirely. This is intentional — these processes need to write to any organization's data as directed by verified external events.

```typescript
// Only for webhooks and system operations
function createServiceRoleClient() {
  return createClient<Database>(
    process.env.SUPABASE_URL!,
    process.env.SUPABASE_SERVICE_ROLE_KEY!,
    { auth: { autoRefreshToken: false, persistSession: false } }
  );
}
```

The service role key is a secret that never leaves the server. It's never exposed to client code, never included in client bundles, and never used for user-initiated operations.

### Don't duplicate what RLS enforces

With RLS in place, application code should not redundantly check organization ownership. Redundant checks create a maintenance burden and a false sense of security — if the RLS policy changes but the application check doesn't, they drift apart silently.

```typescript
// WRONG — redundant with RLS, and now you have two
// authorization implementations that can drift apart
export async function deleteOrderAction(id: string) {
  const { orgId } = await auth();
  const order = await getOrderById(supabase, id);

  if (order.organization_id !== orgId) {
    throw new Error("Unauthorized");
  }

  await deleteOrder(supabase, id);
}

// RIGHT — trust RLS, keep the action simple
export async function deleteOrderAction(id: string) {
  const supabase = await createClient();
  // If the order belongs to a different org,
  // RLS ensures this returns zero rows — no error needed
  await deleteOrder(supabase, id);
  revalidatePath("/orders");
}
```

### Verifying RLS coverage

Trust, but verify. A SQL query can check that every table in the public schema has RLS enabled.

```sql
SELECT
  schemaname,
  tablename,
  rowsecurity
FROM pg_tables
WHERE schemaname = 'public'
  AND rowsecurity = false;
```

If this query returns any rows, you have tables without RLS. This check should run in CI or as a periodic audit.

### The security properties

The layered model provides five guarantees:

1. **Fail-closed.** Missing authentication means denied access. There's no fallback to a permissive mode.
2. **Defense in depth.** Authentication at the middleware layer and authorization at the database layer. Either one can catch a bug in the other.
3. **Least privilege.** API keys have scoped permissions. Service role access is limited to system operations.
4. **Immutable audit trail.** All credential lifecycle events are logged and cannot be modified.
5. **Server-side scoping only.** The organization ID is never read from client code or URL parameters. It comes from the server-verified JWT.

### Security headers

Every response includes hardened headers as an additional defense layer.

```typescript
// next.config.mjs headers
{
  "Strict-Transport-Security": "max-age=63072000; includeSubDomains; preload",
  "X-Content-Type-Options": "nosniff",
  "Permissions-Policy": "camera=(), microphone=(), geolocation=()",
  "Referrer-Policy": "origin-when-cross-origin",
  "X-XSS-Protection": "1; mode=block"
}
```

### Webhook signature verification

External events must be verified before they're trusted. Every webhook provider offers a signature mechanism. Verify it before processing.

```typescript
// Auth provider webhook
const payload = await svix.verify(body, headers);

// Payment provider webhook
const event = provider.webhooks.constructEvent(body, signature, secret);

// Calendar provider webhook
const isValid = verifyHmacSignature(body, signature, secret);
```

## The Business Case

- **Structural impossibility of cross-tenant leaks.** RLS makes it impossible for a missing WHERE clause to expose another tenant's data. This is a property of the architecture, not a property of developer discipline.
- **SOC 2 compliance by default.** RLS on every table, signature verification on every webhook, audit logging on every credential operation. The controls matrix is built into the code, not bolted on after.
- **Faster feature development.** Developers don't write authorization logic for every query. They trust RLS and focus on business logic. The security layer is invisible in application code because it operates at a lower level.

## Try It

Install the Modh Playbook skills to enforce this pattern automatically:
```bash
# Add to your project
git submodule add https://github.com/modh-labs/playbook .agents/modh-playbook
./.agents/modh-playbook/install.sh
```
