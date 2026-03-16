---
title: "Security Headers"
subtitle: "CSP, CORS, and webhook signature verification"
chapter: 12
section: "Security"
seo_title: "Security Headers — CSP, CORS, Webhook Signatures for Next.js 2026"
seo_description: "HTTP security headers, webhook signature verification, and CORS configuration. The transport-layer security that most teams skip until after the breach."
keywords: ["security headers", "CSP", "CORS", "webhook signatures", "X-Frame-Options", "Next.js security", "HTTP headers"]
reading_time: "8 min"
difficulty: "intermediate"
tech_stack: ["Next.js", "Supabase", "TypeScript"]
business_case: "Eliminates clickjacking, MIME-sniffing, replay attacks, and forged webhook payloads — four vulnerability classes that cost nothing to prevent and everything to recover from."
---

# Security Headers

> "The cheapest security fix is the one you ship before the breach."

## The Problem

A developer builds a SaaS application. They implement authentication with JWTs. They add Row Level Security to the database. They validate inputs with Zod. They feel secure.

Then a security auditor runs a scan and produces a report with fourteen findings. The application has no clickjacking protection — anyone can embed it in an iframe and overlay a fake login page on top. The MIME type is not locked down — a malicious file upload could be interpreted as executable JavaScript. The referrer policy leaks the full URL — including auth tokens in query parameters — to every third-party service the page connects to. The webhook endpoint accepts replayed payloads from last month.

None of these are application logic bugs. They're transport-layer omissions. Missing HTTP headers that take five minutes to configure and cost nothing to maintain. But the remediation — after the fact — costs days: incident response, forensic analysis, customer notification, compliance documentation.

Security headers are the seatbelt of web development. They protect against attacks that are trivial to execute and devastating in impact. Not configuring them is not a risk calculation — it's negligence.

## The Principle

Every HTTP response from your application must include the standard security headers. Every webhook endpoint must verify signatures before processing. Every sensitive API must reject stale requests. These are not features. They are baseline requirements that ship with the first deploy.

## The Pattern

### The required security headers

Configure these in your `next.config.mjs`. They apply to every response from the application:

```typescript
// next.config.mjs
const nextConfig = {
  async headers() {
    return [
      {
        source: "/(.*)",
        headers: [
          // Prevent MIME type sniffing — stops XSS via file uploads
          {
            key: "X-Content-Type-Options",
            value: "nosniff",
          },
          // Prevent clickjacking — blocks iframe embedding
          {
            key: "X-Frame-Options",
            value: "DENY",
          },
          // XSS protection for legacy browsers
          {
            key: "X-XSS-Protection",
            value: "1; mode=block",
          },
          // Control referrer leakage to third parties
          {
            key: "Referrer-Policy",
            value: "origin-when-cross-origin",
          },
          // Enforce HTTPS
          {
            key: "Strict-Transport-Security",
            value: "max-age=31536000; includeSubDomains",
          },
          // Restrict browser features
          {
            key: "Permissions-Policy",
            value: "camera=(), microphone=(), geolocation=()",
          },
        ],
      },
    ];
  },
};
```

What each header prevents:

| Header | Attack Prevented | Without It |
|--------|-----------------|------------|
| `X-Content-Type-Options: nosniff` | MIME confusion attacks | Uploaded `.txt` file executes as JavaScript |
| `X-Frame-Options: DENY` | Clickjacking | Your app embedded in attacker's iframe with a fake UI overlay |
| `X-XSS-Protection: 1; mode=block` | Reflected XSS (legacy) | Older browsers execute injected scripts in URLs |
| `Referrer-Policy: origin-when-cross-origin` | URL leakage | Full URL (with tokens) sent to third-party analytics |
| `Strict-Transport-Security` | SSL stripping | Downgrade attacks force HTTP connection |
| `Permissions-Policy` | Feature abuse | Malicious scripts access camera/microphone |

### Webhook signature verification

Webhook payloads arrive from the public internet. Without signature verification, anyone who discovers your endpoint URL can forge events — creating fake payments, fake user signups, fake calendar changes.

Every webhook provider signs their payloads. We must verify that signature before reading a single field from the body.

```typescript
// app/api/webhooks/payments/route.ts
import { createHmac, timingSafeEqual } from "crypto";

export async function POST(req: Request) {
  const signature = req.headers.get("x-webhook-signature");
  if (!signature) {
    return Response.json({ error: "Missing signature" }, { status: 401 });
  }

  // CRITICAL: Use req.text(), never req.json()
  // Parsing and re-serializing changes the bytes, breaking the signature
  const body = await req.text();

  const expectedSignature = createHmac("sha256", process.env.WEBHOOK_SECRET!)
    .update(body)
    .digest("hex");

  // Use timing-safe comparison to prevent timing attacks
  const isValid = timingSafeEqual(
    Buffer.from(signature),
    Buffer.from(expectedSignature)
  );

  if (!isValid) {
    return Response.json({ error: "Invalid signature" }, { status: 401 });
  }

  // Now safe to parse and process
  const event = JSON.parse(body);
  await processEvent(event);
  return Response.json({ received: true });
}
```

Two details that trip up every team:

First, use `req.text()` to get the raw body. If you call `req.json()`, the runtime parses the JSON and later re-serializes it. The re-serialized bytes may differ from the original — different whitespace, different key ordering — and the signature check fails intermittently. This is one of the most common webhook bugs in production, and it's extremely difficult to debug because it works in testing (where the body happens to round-trip cleanly) and fails on certain payloads in production.

Second, use `timingSafeEqual` for the comparison. A naive `===` comparison leaks timing information — an attacker can determine how many characters of the signature match by measuring response times. Timing-safe comparison takes the same time regardless of how many bytes match.

### Replay protection

Even with valid signatures, an attacker who captures a webhook payload can replay it hours later. The payment was already processed, but the replay creates a duplicate record.

Most providers include a timestamp in the event. Reject anything older than five minutes:

```typescript
const MAX_AGE_SECONDS = 300; // 5 minutes

function isEventFresh(event: { created: number }): boolean {
  const age = Math.floor(Date.now() / 1000) - event.created;
  return age >= 0 && age <= MAX_AGE_SECONDS;
}

// In the webhook handler, after signature verification
if (!isEventFresh(event)) {
  return Response.json({ error: "Event too old" }, { status: 400 });
}
```

The `age >= 0` check catches events with timestamps in the future — a sign of clock skew or tampering.

### CORS: default secure, open when needed

Next.js API routes are same-origin by default. They don't need CORS headers. Webhook endpoints are server-to-server — they don't need CORS headers either.

The only time you configure CORS is for a public API consumed by third-party frontends:

```typescript
// app/api/public/route.ts
export async function GET(req: Request) {
  const origin = req.headers.get("origin");
  const allowedOrigins = process.env.ALLOWED_ORIGINS?.split(",") ?? [];

  const headers: Record<string, string> = {
    "Content-Type": "application/json",
  };

  if (origin && allowedOrigins.includes(origin)) {
    headers["Access-Control-Allow-Origin"] = origin;
    headers["Access-Control-Allow-Methods"] = "GET, POST";
    headers["Access-Control-Allow-Headers"] = "Content-Type, Authorization";
    headers["Access-Control-Max-Age"] = "86400";
  }

  const data = await fetchPublicData();
  return Response.json(data, { headers });
}
```

Notice the explicit allowlist. We never set `Access-Control-Allow-Origin: *` on authenticated endpoints. A wildcard CORS header on an endpoint that reads cookies or Authorization headers is a data exfiltration vulnerability.

### Environment variable protection

Secrets must never reach the client. Next.js enforces this with the `NEXT_PUBLIC_` prefix convention — only variables starting with `NEXT_PUBLIC_` are included in the client bundle.

Enforce this with lint-staged to catch accidental commits:

```json
{
  "*.env*": [
    "echo 'Environment files must not be committed' && exit 1"
  ]
}
```

And organize your variables with a clear separation:

```bash
# Client-safe — exposed in the browser
NEXT_PUBLIC_SUPABASE_URL=https://...
NEXT_PUBLIC_SUPABASE_ANON_KEY=eyJ...
NEXT_PUBLIC_CLERK_PUBLISHABLE_KEY=pk_...

# Server-only — never leaves the server
CLERK_SECRET_KEY=sk_...
SUPABASE_SERVICE_ROLE_KEY=eyJ...
STRIPE_WEBHOOK_SECRET=whsec_...
WEBHOOK_SECRET=...
```

### Rate limiting for public endpoints

Any endpoint exposed to the internet needs rate limiting. Without it, an attacker can brute-force passwords, exhaust database connections, or run up your cloud bill:

```typescript
import { Ratelimit } from "@upstash/ratelimit";
import { Redis } from "@upstash/redis";

const ratelimit = new Ratelimit({
  redis: Redis.fromEnv(),
  limiter: Ratelimit.slidingWindow(10, "10s"), // 10 requests per 10 seconds
});

export async function POST(req: Request) {
  const ip = req.headers.get("x-forwarded-for") ?? "anonymous";
  const { success, remaining } = await ratelimit.limit(ip);

  if (!success) {
    return Response.json(
      { error: "Too many requests" },
      {
        status: 429,
        headers: { "Retry-After": "10" },
      }
    );
  }

  // Process the request
}
```

## The Business Case

- **Five minutes of configuration, years of protection.** Security headers are configured once and never touched again. They prevent four major vulnerability classes — clickjacking, MIME sniffing, referrer leakage, and SSL stripping — with zero ongoing maintenance.
- **Webhook integrity without custom infrastructure.** Signature verification and replay protection ensure that only legitimate events from real providers trigger actions in your system. No duplicate payments. No forged user signups. No replayed cancellations.
- **Audit readiness.** When a security auditor or SOC 2 assessor scans your application, every header check passes on the first run. The alternative — failing the scan, remediating, and re-testing — costs days of engineering time and delays compliance milestones.

## Try It

Install the Modh Playbook skills to enforce this pattern automatically:
```bash
# Add to your project
git submodule add https://github.com/modh-labs/playbook .agents/modh-playbook
./.agents/modh-playbook/install.sh
```
