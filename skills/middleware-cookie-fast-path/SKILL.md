---
name: middleware-cookie-fast-path
description: >
  Eliminate post-hydration fetch waterfalls on edge-cached pages. When a
  client component needs request-scoped data (geo, timezone, AB variant,
  feature flag) and the page is edge-cached, stamp a client-readable
  cookie in middleware so the client reads the value synchronously.
  Use when edge-cached pages depend on request-scoped data, when a
  fetch-after-hydration is blocking a third-party script, or when N
  components are firing the same `/api/something` request in parallel.
---

# Middleware Cookie Fast Path

## When This Skill Activates

- A client component on an edge-cached page fetches `/api/geo`, `/api/timezone`, `/api/ab-variant`, or similar after hydration
- The Meta Pixel, Google Analytics, Hyros, or any other tracking script is gated behind a client-side consent or jurisdiction check
- Multiple components use the same hook and each fires its own fetch (visible as N+ duplicate requests in the Network tab)
- You see a waterfall: HTML → hydrate → fetch → state update → render-the-thing - and the "thing" is latency-sensitive
- You need to read `headers()` / `cookies()` on a page that uses `"use cache"`, ISR, or is served from a CDN

## The One Question

> **Is a client component on an edge-cached page fetching request-scoped data after hydration, causing a waterfall that blocks something the user sees or something that tracks the user?**

If yes - that fetch is the bottleneck. Stamp the data as a cookie in middleware and read it synchronously on the client.

## Why This Matters

Edge-cached pages (`"use cache"`, ISR, static, CDN-cached) are fast because the HTML body is pre-rendered once and served to many visitors. But the server can't inject per-visitor data into that cached body - that would defeat the cache.

So teams reach for the obvious fix: "the client will fetch the per-visitor data after it hydrates." Which works, but creates three problems:

1. **Waterfall latency.** The client must: parse HTML → download JS → hydrate → mount effect → fire fetch → await response → set state → re-render the gated component. On slow mobile (4G, Slow-3G, iOS low-power mode) this is 5-30 seconds. Anything gated behind this - tracking pixels, personalization, AB variants - doesn't exist for the user until the waterfall completes.

2. **Duplicate requests.** Every component that needs the data fires its own fetch. If six components use the same hook, you see six identical requests. No React built-in dedups them. Your edge cache hides the server load, but the client still pays the round-trip cost per request.

3. **Failure modes diverge silently.** Each consumer's `.catch()` picks its own fallback - some fail open, some fail closed. The same visitor can end up with inconsistent state across components on the same page.

The middleware can read request headers (geo, IP, `Sec-GPC`, `Accept-Language`, `User-Agent`) on every request - even requests that will be served from the edge cache. It can set a `Set-Cookie` header on the outgoing response. That cookie lands in the browser before the HTML parser reaches `</body>`. The client reads it synchronously in `useState`'s initializer. No fetch. No waterfall.

## Decision Tree

```
Is the page edge-cached?
  NO → Read server-side via headers()/cookies(). Skip this pattern.
  YES → Continue.

Does a client component need request-scoped data?
  NO → Done.
  YES → Continue.

Is that data currently fetched client-side after hydration?
  NO → Good.
  YES → Apply this pattern.

Does the data come from a request header the middleware can read?
  (x-vercel-ip-country, Accept-Language, User-Agent, Sec-GPC, custom header)
  YES → Middleware stamps a cookie directly. Skip the `/api/*` route.
  NO, requires a DB lookup → Middleware does the lookup, then stamps. Still beats client fetch
      because you save the TLS handshake + one network round trip per visitor.
```

## Core Rules

### Rule 1: Stamp the cookie in middleware on every request

```typescript
// middleware.ts (Next.js 15) or proxy.ts (Next.js 16)
import { type NextRequest, NextResponse } from "next/server";

const COOKIE = "app-consent-required";

function stampCookie(response: NextResponse, req: NextRequest): void {
  const country = req.headers.get("x-vercel-ip-country");
  if (!country) return; // local dev: no header - let client fallback run
  const value = isGdprCountry(country) ? "1" : "0";
  response.cookies.set(COOKIE, value, {
    path: "/",
    maxAge: 60 * 60,           // align with your /api/* edge cache TTL
    sameSite: "lax",
    secure: process.env.NODE_ENV === "production",
    httpOnly: false,           // MUST be false - the client reads it
  });
}

export function middleware(req: NextRequest) {
  const response = NextResponse.next();
  stampCookie(response, req);
  return response;
}
```

### Rule 2: Read the cookie synchronously in the client hook

```typescript
// use-consent-required.ts
"use client";

export function useConsentRequired(): boolean | undefined {
  const [value, setValue] = useState<boolean | undefined>(() => {
    if (typeof document === "undefined") return undefined;
    const cookie = readCookie("app-consent-required");
    if (cookie !== undefined) return cookie === "1";  // FAST PATH
    return undefined;                                  // fall through to fetch
  });

  useEffect(() => {
    if (value !== undefined) return;
    fetchOnce()                  // dedup'd across consumers
      .then((v) => setValue(v))
      .catch(() => setValue(false));
  }, [value]);

  return value;
}

function readCookie(name: string): "0" | "1" | undefined {
  const m = document.cookie.match(
    new RegExp(`(?:^|;\\s*)${name}=([01])(?:;|$)`),
  );
  return m ? (m[1] as "0" | "1") : undefined;
}
```

### Rule 3: Dedupe the fallback fetch with a module-level promise

```typescript
let promise: Promise<boolean> | null = null;

function fetchOnce(): Promise<boolean> {
  if (!promise) {
    promise = fetch("/api/consent-required")
      .then((r) => r.json())
      .then((d) => d.consentRequired)
      .catch((err) => {
        promise = null;          // reset on error so future mounts can retry
        throw err;
      });
  }
  return promise;
}
```

Without this, every component using the hook fires its own fetch. With it, the first one starts the fetch and every subsequent one joins the same promise.

### Rule 4: HttpOnly must be false

This is the one line that trips people up. The client needs to read the cookie - `HttpOnly: true` makes that impossible. This is not a security downgrade: the cookie contains non-sensitive routing data (jurisdiction, variant, flag), which the client is about to know anyway.

### Rule 5: Cookie value must be tiny and parseable

```
GOOD: "0" or "1"                          - 1 byte, unambiguous
GOOD: "en-US" or "us-east-1"              - short, standard format
WRONG: JSON.stringify({ country: "US" })  - bloats every request header
WRONG: "true" / "false"                   - two-byte diff the parser has to handle
```

Every request from the browser sends all cookies back. A 200-byte cookie on a 50-request page load adds 10 KB of wasted upstream traffic.

## Implementation Pattern

### The three-file shape

```
app/
├── middleware.ts (or proxy.ts)           # Stamps cookie on response
├── lib/edge-data/
│   ├── consent-required-cookie.ts        # Shared constants + client reader
│   └── __tests__/consent-required-cookie.test.ts
└── hooks/
    └── use-consent-required.ts           # Client hook with cookie→fetch cascade
```

### Shared module (client + server import it)

```typescript
// lib/edge-data/consent-required-cookie.ts
export const COOKIE_NAME = "app-consent-required";
export const COOKIE_MAX_AGE = 60 * 60;

/** Read on the client. Returns undefined if the cookie is missing. */
export function getFromCookie(): boolean | undefined {
  if (typeof document === "undefined") return undefined;
  const m = document.cookie.match(
    /(?:^|;\s*)app-consent-required=([01])(?:;|$)/,
  );
  return m ? m[1] === "1" : undefined;
}

/** Serialize on the server. Kept here so middleware + any future
 *  consumer agree on the "0"/"1" format. */
export function serialize(value: boolean): "0" | "1" {
  return value ? "1" : "0";
}
```

### Fallback `/api/*` route (still needed for local dev)

The middleware can't stamp the cookie in local dev where `x-vercel-ip-country` is missing. Keep the `/api/*` route as a fallback path, but the cookie path carries production traffic.

## Anti-Patterns

### ✗ Fetching from N consumers without dedup

```tsx
// Six components each do this:
const [consentRequired, setConsentRequired] = useState<boolean>();
useEffect(() => {
  fetch("/api/geo").then(/* ... */);
}, []);

// Result: 6 identical requests in the Network tab.
```

Fix: extract into one hook with a module-level promise cache.

### ✗ Reading the cookie server-side on a cached page

```tsx
// layout.tsx with "use cache"
"use cache";
export default async function Layout() {
  const country = (await cookies()).get("country"); // ERROR or silently wrong
  return <Shell country={country} />;
}
```

Cached layouts can't read request-scoped APIs. The cookie must be read on the client.

### ✗ `HttpOnly: true` on the fast-path cookie

```typescript
response.cookies.set(COOKIE_NAME, value, {
  httpOnly: true,  // ← client can't read it. Useless for this pattern.
});
```

### ✗ Using the cookie to store PII

```typescript
response.cookies.set("user-email", email, { httpOnly: false });
// Now PII is in every request header, accessible to client JS,
// and shared with every third-party script that reads document.cookie.
```

The fast-path cookie is for routing decisions only. Non-sensitive, non-identifying.

### ✗ Cookie set in a cached API route instead of middleware

```typescript
// app/api/geo/route.ts
export async function GET(req: NextRequest) {
  "use cache";                // Now the response is cached
  const country = req.headers.get("x-vercel-ip-country");
  const response = NextResponse.json({ country });
  response.cookies.set("country", country);  // Set inside cached response - wrong visitor gets it
  return response;
}
```

Cookies must be set by code that runs per-request. Middleware runs per-request even when the page body is cached. API route handlers might not.

### ✗ Forgetting the fallback fetch path

Local dev, reverse proxies that strip `x-vercel-ip-country`, self-hosted deployments without geo enrichment - these have no header. The middleware correctly skips, but the client must fall back to `/api/*` or the feature breaks in dev.

## Audit Checklist

Reviewing an edge-cached page with request-scoped client data:

- [ ] Middleware reads the request header and stamps a cookie on the outgoing response
- [ ] Cookie is `HttpOnly: false`, `SameSite: Lax`, `Secure` in production, `Path: /`
- [ ] Cookie value is a tiny scalar ("0"/"1", short code, small number) - not JSON
- [ ] Cookie `Max-Age` aligns with the TTL of the fallback `/api/*` route
- [ ] Shared module exports the cookie name as a constant + a client reader helper
- [ ] Client hook reads the cookie in `useState`'s initializer (synchronous, no effect)
- [ ] Client hook falls back to a module-level deduplicated promise for missing cookies
- [ ] Failure modes are consistent across all consumers (all fail-open OR all fail-closed)
- [ ] Unit test covers: cookie present, cookie absent, cookie malformed, substring matches (e.g. `xapp-consent-required`)
- [ ] Observability: emit a metric/event once per page load recording which path resolved the value (cookie vs session vs fetch vs default)

## Generalizes To

The same pattern applies whenever a cached page needs request-scoped client data:

| Data | Source header | Cookie name |
|------|---------------|-------------|
| GDPR jurisdiction | `x-vercel-ip-country` | `app-consent-required` |
| Timezone (for fast formatting) | `x-vercel-ip-timezone` | `app-tz` |
| AB test variant | (hash of user IP / cookie) | `app-variant` |
| Feature flag | (DB lookup keyed by IP/user) | `app-flag-{name}` |
| Device class | `User-Agent` parsed | `app-device` |
| Preferred language | `Accept-Language` | `app-lang` |

If the value is small, stable-for-the-session, and non-sensitive - it's a fast-path cookie candidate.

## Related Patterns

- **Server Component first** - if the page isn't edge-cached, read the header server-side and pass as a prop. Cookie fast-path only applies to cached pages.
- **Edge config / feature flags** - for truly global data (not per-visitor), skip cookies and use edge config.
- **Signed cookies** - if the value must be tamper-resistant (rare for routing data), sign it server-side.

## Origin

This pattern was extracted from a real Meta Pixel LPV (Landing Page View) incident: a growth lead reported a 30-point drop in LPV-to-click rate after GDPR consent detection was added. The hypothesis was "the cookie banner is blocking the pixel for everyone." A live Playwright diagnostic revealed the actual cause - the pixel was gated behind a client-side `/api/geo` fetch that took 34 seconds to resolve on simulated Slow 3G mobile, and 6+ components each fired their own duplicate request. Moving the geo detection to the middleware cookie fast path eliminated the waterfall, and the expected LPV recovery was 15-25% of mobile cold traffic.

The failure mode had been invisible for weeks: US visitors were unaffected (they'd get `grant` mode anyway), but mobile ad visitors were silently bouncing before the pixel could fire. The hypothesis that had been proposed ("cookie banner blocks pixel") was superficially plausible but factually wrong, and would have led to ripping out GDPR compliance - a regulatory disaster for a 45-country jurisdiction.

The lesson beyond the technical pattern: **observe the live system before acting on a hypothesis**. A 30-minute diagnostic saved weeks of wrong-direction work.
