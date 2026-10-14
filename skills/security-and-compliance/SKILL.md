---
name: security-and-compliance
description: >
  Enforce security standards including RLS policies, webhook signature verification,
  Zod validation, environment variable safety, GDPR consent, and SOC 2 compliance.
  Use when adding tables, webhook handlers, server actions, authentication, or
  preparing for security audits. Prevents XSS, injection, and data leakage.
---

# Security & Compliance Skill

## When This Skill Activates

- Creating or modifying database tables (RLS policies)
- Writing webhook handlers (signature verification)
- Creating server actions (input validation)
- Working with environment variables or secrets
- Modifying authentication or authorization flows
- Adding tracking scripts or analytics pixels (consent gating)
- Creating public-facing forms that collect user data
- Working on data export, deletion, or retention features
- Preparing for SOC 2 audit or security questionnaires
- Adding third-party scripts or external service integrations

---

## 1. Row-Level Security (RLS)

### Trust RLS -- Don't Duplicate Permission Checks

```typescript
// WRONG - Redundant with RLS
export async function deleteRecord(id: string) {
  const auth = await getAuth();
  const record = await repository.getById(id);
  if (record.organization_id !== auth.orgId) {
    throw new Error("Unauthorized"); // RLS already does this!
  }
  await repository.remove(id);
}

// CORRECT - Trust RLS
export async function deleteRecord(id: string) {
  await repository.remove(id);
  // If RLS rejects, the database throws automatically
}
```

### Enable RLS on ALL Tables with User Data

```sql
ALTER TABLE "public"."my_table" ENABLE ROW LEVEL SECURITY;

-- Use a helper function for org isolation
CREATE POLICY "my_table_authenticated_read" ON "public"."my_table"
  FOR SELECT
  TO authenticated
  USING (can_access_organization_data("organization_id"));

CREATE POLICY "my_table_service_role_write" ON "public"."my_table"
  FOR ALL
  TO service_role
  USING (true)
  WITH CHECK (true);
```

The `can_access_organization_data()` helper handles all JWT formats and service_role bypass. See `references/rls-checklist.md` for full policy patterns.

### Service Role: Webhook Handlers ONLY

```typescript
// ONLY in webhook handlers
import { createServiceRoleClient } from "@/lib/supabase/server";

export async function POST(req: Request) {
  const supabase = await createServiceRoleClient();
  // Bypasses RLS - use carefully!
}

// NEVER in server actions or components
```

```
Using createServiceRoleClient()?
  Is it in a webhook handler? -> OK
  Is it in a server action?   -> STOP -- use authenticated client
  Is it in a cron job?        -> OK (document why in code comment)
  Cross-user data for shared resources? -> OK (document scope)
```

---

## 2. Webhook Security

### Always Verify Signatures

```typescript
// Payment provider (e.g., Stripe)
const body = await req.text();
const signature = req.headers.get("stripe-signature")!;
const event = stripe.webhooks.constructEvent(body, signature, webhookSecret);

// Auth provider (Svix-based signature)
const body = await req.text();
const headers = {
  "svix-id": req.headers.get("svix-id")!,
  "svix-timestamp": req.headers.get("svix-timestamp")!,
  "svix-signature": req.headers.get("svix-signature")!,
};
const payload = await svix.verify(body, headers);

// Calendar provider (HMAC)
const body = await req.text();
const signature = req.headers.get("x-provider-signature")!;
const isValid = verifyHmacSignature(body, signature, process.env.WEBHOOK_SECRET!);
```

### ALWAYS Use req.text() for Webhook Body

```typescript
// CORRECT - Raw body preserves signature
const body = await req.text();
const event = provider.webhooks.constructEvent(body, signature, secret);
const parsed = JSON.parse(body); // Parse separately after verification

// WRONG - Parsed JSON breaks signature verification
const body = await req.json(); // Re-serialization changes whitespace/ordering
```

### Reject Stale Webhook Events

```typescript
const MAX_EVENT_AGE_SECONDS = 300; // 5 minutes

const eventAge = Math.floor(Date.now() / 1000) - event.created;
if (eventAge > MAX_EVENT_AGE_SECONDS) {
  return NextResponse.json({ error: "Event too old" }, { status: 400 });
}
```

---

## 3. Input Validation

### Zod Validation at Server Action Boundary

```typescript
// CORRECT - Validate all user input
import { createRecordSchema } from "@/lib/validation/records.schema";

export async function createRecord(data: unknown) {
  const validated = createRecordSchema.safeParse(data);
  if (!validated.success) {
    return { error: validated.error.issues[0]?.message };
  }
  await repository.create(supabase, validated.data);
}

// WRONG - Trusting client input
export async function createRecord(data: CreateRecordInput) {
  // data could be anything!
  await repository.create(supabase, data);
}
```

---

## 4. Environment Variable Safety

```
New environment variable?
  Contains a secret (API key, token, password)?
    NEVER prefix with NEXT_PUBLIC_ (exposes to client bundle)
    Add to deployment platform env vars, NOT .env files in repo
  Safe for client (publishable key, public URL)?
    Prefix with NEXT_PUBLIC_
  Added to .env.example with placeholder?
    Required for developer onboarding
```

- Lint-staged should block `.env` file commits
- Client-safe variables use `NEXT_PUBLIC_*` prefix only
- Never commit `.env` files to the repository

---

## 5. HTTP Security Headers

Every web application MUST include these headers in its config:

| Header | Value | Purpose |
|--------|-------|---------|
| `Strict-Transport-Security` | `max-age=63072000; includeSubDomains; preload` | HSTS (2 years) |
| `Content-Security-Policy` | (project-specific directives) | XSS prevention |
| `X-Content-Type-Options` | `nosniff` | MIME sniffing prevention |
| `X-Frame-Options` | `DENY` | Clickjacking prevention |
| `X-XSS-Protection` | `1; mode=block` | Browser XSS filter (legacy) |
| `Permissions-Policy` | `camera=(), microphone=(), geolocation=()` | Disable unused browser APIs |
| `Referrer-Policy` | `origin-when-cross-origin` | Referrer leakage prevention |

Full header config: `references/http-headers.md`

---

## 6. Sensitive Data Handling

```typescript
// Error tracker MUST disable PII
Sentry.init({ sendDefaultPii: false });

// Encrypt credentials at rest
import { encrypt, decrypt } from "@/lib/encryption/credentials";
const encryptedKey = encrypt(apiKey, process.env.ENCRYPTION_KEY!);
```

### PII in Logs

```typescript
// CORRECT -- structured attribute (auto-redacted by logger)
logger.info("Record created", { guest_email: email });

// WRONG -- PII in unstructured string (bypasses redaction)
logger.info(`Record created for ${email}`);
```

**Rule:** Never interpolate PII into log message strings. Always pass PII as structured attributes where the redaction layer can catch it.

---

## 7. Consent & Privacy (GDPR/CCPA)

### Consent Gating

Every tracking script must be gated behind cookie consent. Zero-load policy: no tracking code executes until the user explicitly consents.

```
New tracking script?
  Is it in the consent-aware wrapper?
    YES -> Verify it checks hasConsent before rendering
    NO  -> STOP -- add it to the consent wrapper first
  Does it set cookies?
    YES -> Must be gated behind consent acceptance
    NO  -> Still needs consent if it collects behavioral data
  Is it a third-party iframe?
    Must lazy-load after consent (no pre-connect without consent)
```

### Dark Pattern Check

- Accept and reject must be equally prominent (same size, same visual weight)
- No pre-checked consent boxes
- "Reject all" must be a single click (no multi-step dismissal)
- Cookie banner must not block page content on mobile

### Privacy Policy Links

Every public form that collects data must link to the privacy policy adjacent to the submit button.

---

## 8. GDPR Compliance Checklist

### Consent Proof (Art. 7)

- [ ] Cookie consent recorded with timestamp before any tracking fires
- [ ] Consent is granular (analytics vs marketing vs functional)
- [ ] Users can withdraw consent as easily as they gave it
- [ ] Pre-checked boxes are never used

### Data Subject Access Request (Art. 15)

- [ ] Users can request a copy of all their personal data
- [ ] Response includes all relevant tables containing PII
- [ ] Data export format is machine-readable (JSON or CSV)
- [ ] Response within 30 days

### Right to Erasure (Art. 17)

- [ ] Account deletion removes personal data from all relevant tables
- [ ] Audit logs are retained (legal basis: legitimate interest for security)
- [ ] File storage (recordings, uploads) is deleted
- [ ] Third-party data is deletion-requested (auth provider, payment provider)

### Data Retention (Art. 5(1)(e))

- [ ] Define retention periods per data type
- [ ] Enforce TTL policies where applicable
- [ ] Audit logs retained for compliance period (typically 1 year)
- [ ] Cookie consent records retained for proof of consent

### CCPA Requirements

- [ ] "Do Not Sell My Personal Information" link (if applicable)
- [ ] Opt-out mechanism for data sale
- [ ] Privacy policy discloses categories of data collected

---

## 9. SOC 2 Evidence Checklist

### Access Control (CC6.1)

- [ ] Authentication enforced on all protected routes
- [ ] Middleware gates: auth check -> billing check -> onboarding check
- [ ] RLS isolates organization data at database level
- [ ] Service role access limited to webhook handlers

### Audit Trail (CC7.2)

- [ ] `audit_logs` table captures all sensitive mutations
- [ ] Audit logs are immutable (RLS DENY on UPDATE/DELETE)
- [ ] Logs include: who (user_id), what (action), when (timestamp), where (org_id)
- [ ] Error tracker captures all errors with correlation IDs

### Encryption (CC6.7)

- [ ] Data in transit: HTTPS enforced via HSTS
- [ ] Data at rest: database provider encrypts at rest
- [ ] Integration credentials: encrypted with application-level key
- [ ] Error tracker: `sendDefaultPii: false`

### Monitoring (CC7.1)

- [ ] Alerts on critical exceptions (payment, webhook, auth failures)
- [ ] Structured logging with automatic PII redaction
- [ ] Webhook processing failures trigger issues in error tracker
- [ ] Uptime monitoring via cron monitors or external service

---

## 10. PII Column Documentation

Document which columns contain personal data for DSAR fulfillment:

| Table | PII Columns | Retention |
|-------|-------------|-----------|
| `users` | email, name, avatar_url | Account lifetime |
| `records` | email, phone, name, notes | Org lifetime |
| `sessions` | guest_email, recording_url, transcript | Defined TTL |
| `organization_members` | user_id (links to PII) | Membership lifetime |

---

## Anti-Patterns

| Anti-Pattern | Why It's Wrong | Correct Alternative |
|-------------|---------------|-------------------|
| Duplicating RLS checks in code | Redundant, risk of divergence | Trust RLS |
| Using service role in server actions | Bypasses all security | Use authenticated client |
| `req.json()` for webhook body | Breaks cryptographic signatures | `req.text()` then `JSON.parse()` |
| Missing Zod validation on server actions | Accepts arbitrary input | Validate at boundary |
| Committing .env files | Exposes secrets | Use deployment platform env vars |
| String concatenation in SQL | Injection risk | Use parameterized queries |
| Exposing secrets in `NEXT_PUBLIC_*` vars | Client bundle exposure | Server-only env vars |
| PII in log message strings | Bypasses auto-redaction | Use structured attributes |
| Pre-checked consent boxes | GDPR violation | Default to unchecked |
| Tracking without consent gate | ePrivacy violation | Gate in consent wrapper |

---

## Quick Reference

| Pattern | Correct | Wrong |
|---------|---------|-------|
| Authorization | Trust RLS | Manual org_id checks |
| Webhook body | `req.text()` | `req.json()` |
| Input validation | Zod at boundary | Trust client input |
| Service role | Webhooks only | Server actions |
| Secrets | Deployment env vars | `.env` in repo |
| SQL | Parameterized queries | String concatenation |
| Tracking scripts | Consent-gated | Unconditional loading |
| PII in logs | Structured attributes | Interpolated strings |
| Data deletion | Remove PII, keep audit logs | Delete everything or nothing |
| Security headers | Full set (CSP + HSTS + all) | Only X-Frame-Options |

---

## Checklist for New Applications

- [ ] Security headers in web config
- [ ] Auth middleware for protected routes
- [ ] RLS on all tables with user data
- [ ] `sendDefaultPii: false` in error tracker
- [ ] Webhook signature verification
- [ ] Zod schemas for all inputs
- [ ] Rate limiting for public endpoints
- [ ] Cookie consent mechanism
- [ ] Privacy policy link on data collection forms
- [ ] Audit log table with immutable RLS policies
- [ ] .env blocked from commits

---

## Detailed References

- Full RLS policy patterns and service role guidelines: `references/rls-checklist.md`
- Full security headers configuration: `references/http-headers.md`
