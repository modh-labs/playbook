---
title: "Webhook Architecture"
subtitle: "Building webhooks that never lose events"
chapter: 5
section: "Architecture"
seo_title: "Webhook Architecture — Idempotent, Secure, Observable Patterns 2026"
seo_description: "Build webhooks that survive retries, reject replays, and leave an audit trail. Covers signature verification, idempotency, and multi-tenant event routing."
keywords: ["webhooks", "idempotency", "signature verification", "event-driven", "multi-tenant", "API routes"]
reading_time: "9 min"
difficulty: "advanced"
tech_stack: ["Next.js", "Supabase", "TypeScript"]
business_case: "Prevents duplicate charges, data loss from missed events, and security breaches from forged payloads — the three ways webhooks fail in production."
---

# Webhook Architecture

> "A webhook that processes the same event twice is worse than one that drops it entirely. At least the dropped event gets retried."

## The Problem

Webhooks are the nervous system of modern applications. Payment providers tell you when money moves. Auth providers tell you when users sign up. Calendar providers tell you when meetings change. Your application's correctness depends on processing these events reliably.

But webhooks are also the least reliable communication channel in your stack. The provider sends an HTTP request to your endpoint. If your server is slow, restarting, or temporarily unreachable, the request fails. The provider retries — sometimes immediately, sometimes minutes later, sometimes both. Your endpoint might process the original request and the retry, creating a duplicate payment record or sending a confirmation email twice.

And that's just the happy path failure. An attacker can forge webhook payloads if you don't verify signatures. A stale event replayed hours later can revert a user's state to a previous version. A bug in your event handler can cause a 500 response, triggering an infinite retry loop that hammers your database.

We've seen teams lose revenue because a refund webhook was processed twice, doubling the refund amount. We've seen teams leak data because they trusted a webhook payload without verifying the signature. We've seen teams bring down their database because an unhandled event type caused 500 responses, and the payment provider retried every 30 seconds for 72 hours.

Webhooks are deceptively simple to build and remarkably difficult to build correctly.

## The Principle

Every webhook handler must answer three questions before it processes a single byte of data: Is this payload authentic? Have we seen this event before? Is this event still relevant?

Signature verification answers the first. Idempotency answers the second. Replay protection answers the third. Skip any one of them and you've built a vulnerability, not a feature.

## The Pattern

### Signature verification: trust nothing

Every webhook provider includes a signature header. Verify it before doing anything else. Use the raw request body — not the parsed JSON — because signature algorithms are sensitive to byte-level differences.

```typescript
// app/api/webhooks/payments/route.ts
export async function POST(req: Request) {
  const signature = req.headers.get("x-webhook-signature")!;
  const body = await req.text(); // Raw body, not req.json()

  let event: WebhookEvent;
  try {
    event = verifyWebhookSignature(body, signature, process.env.WEBHOOK_SECRET!);
  } catch {
    return Response.json({ error: "Invalid signature" }, { status: 401 });
  }

  // Only reach here if signature is valid
  await processEvent(event);
  return Response.json({ received: true });
}
```

The critical detail: call `req.text()`, not `req.json()`. If you parse the body first, the re-serialized JSON may differ from the original bytes, causing the signature check to fail.

### Idempotency: process once, acknowledge forever

Every webhook provider retries on failure. Your handler must produce the same result whether it runs once or ten times for the same event.

The strongest approach is a database constraint. If the event's unique identifier already exists in your table, the insert fails and you return 200 without doing any work.

```typescript
async function handlePaymentCompleted(
  supabase: ServiceClient,
  event: PaymentEvent
) {
  // Attempt to insert — UNIQUE constraint on provider_payment_id
  // prevents duplicates at the database level
  const { created, record } = await createPaymentIdempotent(supabase, {
    provider_payment_id: event.payment_id,
    amount_cents: event.amount,
    currency: event.currency,
    organization_id: event.metadata.org_id,
  });

  if (!created) {
    // Already processed — acknowledge and move on
    return;
  }

  // First time seeing this event — process downstream effects
  await updateCustomerStats(supabase, record.customer_id, event.amount);
  await notifyTeam(record);
}
```

For reversal events like refunds, use the reversal's own ID for idempotency — not the original transaction's ID.

```typescript
async function handleRefund(supabase: ServiceClient, event: RefundEvent) {
  // Use the refund ID, not the original charge ID
  const alreadyProcessed = await isRefundProcessed(supabase, event.refund_id);
  if (alreadyProcessed) return;

  await processRefund(supabase, event);
}
```

### Replay protection: reject the stale

Even with signature verification, an attacker who captures a valid webhook payload could replay it later. Most providers include a timestamp in the event. Reject events that are too old.

```typescript
const MAX_EVENT_AGE_SECONDS = 300; // 5 minutes

function validateEventFreshness(event: WebhookEvent): boolean {
  const eventAge = Math.floor(Date.now() / 1000) - event.created;
  return eventAge <= MAX_EVENT_AGE_SECONDS;
}

// In the handler
if (!validateEventFreshness(event)) {
  return Response.json({ error: "Event too old" }, { status: 400 });
}
```

### Event routing: switch and acknowledge

Route events through a switch statement. Always return 200 for unhandled event types — returning a non-2xx response causes the provider to retry indefinitely.

```typescript
switch (event.type) {
  case "payment.completed":
    await handlePaymentCompleted(supabase, event);
    break;

  case "payment.refunded":
    await handlePaymentRefunded(supabase, event);
    break;

  case "subscription.canceled":
    await handleSubscriptionCanceled(supabase, event);
    break;

  default:
    // Acknowledge events we don't handle — prevents retries
    console.info(`Unhandled event type: ${event.type}`);
}

return Response.json({ received: true });
```

### Reversals: update, never delete

When processing "undo" events (refunds, cancellations, revocations), update the status of the original record. Never delete it. Deletion destroys the audit trail.

```typescript
// WRONG — destroys audit trail
await supabase.from("payments").delete().eq("id", paymentId);

// RIGHT — preserves history
await supabase
  .from("payments")
  .update({
    status: "refunded",
    refund_status: "full",
    refunded_at: new Date().toISOString(),
  })
  .eq("id", paymentId);
```

When cascading updates to related entities, handle each independently. The primary record update must succeed even if a downstream update fails.

```typescript
// Primary record — always update
await markPaymentRefunded(supabase, payment.id, refundData);

// Related entity — only if linked
if (payment.customer_id) {
  await decrementCustomerPaymentStats(supabase, payment.customer_id, amount);
}

// Downstream entity — conditional
if (isFullRefund && payment.order_id) {
  await revertOrderFulfillment(supabase, payment.order_id);
}
```

### Multi-tenant webhook endpoints

When each organization has its own webhook secret (common with payment providers), use dynamic route segments to identify the tenant and look up the correct secret.

```typescript
// app/api/webhooks/payments/[org_id]/route.ts
export async function POST(
  req: Request,
  { params }: { params: { org_id: string } }
) {
  const { org_id } = params;
  const supabase = createServiceRoleClient();

  // Look up this org's webhook secret
  const secret = await getWebhookSecret(supabase, org_id);
  if (!secret) {
    return Response.json(
      { error: "Webhook not configured" },
      { status: 404 }
    );
  }

  const signature = req.headers.get("x-webhook-signature")!;
  const body = await req.text();
  const event = verifyWebhookSignature(body, signature, secret);

  await processEvent(supabase, org_id, event);
  return Response.json({ received: true });
}
```

Webhook handlers always use a service-role database client that bypasses Row Level Security. This is necessary because webhooks operate outside a user's authentication context — they need to write to any organization's data as directed by the verified event.

### Observability: trace every event

Every webhook handler should log a request ID, the event type, and the organization ID. When something goes wrong, these three fields let you reconstruct exactly what happened.

```typescript
const requestId = `wh_${Date.now()}_${crypto.randomUUID().slice(0, 8)}`;

console.info({
  requestId,
  organizationId: org_id,
  eventType: event.type,
  eventId: event.id,
}, "Webhook received");

// Include requestId in all subsequent logs
```

### Response codes

| Status | Meaning | Provider behavior |
|--------|---------|-------------------|
| 200 | Processed or already processed | Event marked delivered |
| 400 | Invalid request (bad org, stale event) | Event marked failed |
| 401 | Invalid signature | Event marked failed |
| 500 | Processing error | Provider retries |

Return 200 for business logic failures that shouldn't be retried. Return 500 only for transient errors where a retry might succeed.

## The Business Case

- **No duplicate transactions.** Idempotency guarantees that retried webhooks don't create duplicate records, duplicate charges, or duplicate notifications.
- **No forged events.** Signature verification ensures that only the legitimate provider can trigger actions in your system.
- **Full audit trail.** Update-not-delete and structured logging mean you can reconstruct the entire lifecycle of any record, months after the fact.

## Try It

Install the Modh Playbook skills to enforce this pattern automatically:
```bash
# Add to your project
git submodule add https://github.com/modh-labs/playbook .agents/modh-playbook
./.agents/modh-playbook/install.sh
```
