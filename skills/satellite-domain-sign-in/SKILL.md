---
name: satellite-domain-sign-in
description: >
  Serve one app on two domain families with one sign-in. Use when adding a second
  domain (a rebrand, a new market, a product spin-off) to an app that already
  signs people in; when configuring a satellite domain in an auth provider (Clerk
  satellites, Auth0 custom domains, a shared session across domains); when a
  sign-in started on one domain ends on the other; or when reviewing middleware
  that redirects between an app host and a marketing host.
---

# Satellite Domain Sign-In

A cookie, and so a session, cannot cross a domain family: `old.com` cannot set or
read a cookie for `new.io`. So a second domain cannot simply "share" the first
domain's sign-in. One domain stays the **primary**, where sign-in actually
happens; the other is a **satellite** that hands visitors to the primary and gets
them back with a session of its own.

**The principle:** every hand-off to the primary carries its own way back, and
every page on the satellite sends people to the satellite's app, never to the
primary's. A redirect without a return address quietly undoes the new domain.

**The diagnostic question:** *if a visitor starts on the new domain, which domain
do they end on, and what did they lose on the way?*

## When This Skill Activates

- Adding a second domain to an app that already has sign-in
- Configuring an auth provider's satellite or multi-domain feature
- A sign-in, sign-up or OAuth connect started on one domain finishes on another
- Middleware that redirects between a marketing host and an app host, or that reads `APP_URL`/`NEXT_PUBLIC_APP_URL` to build a redirect
- Setting the auth provider's allowed redirect origins

## Decision Tree

```
A request arrives. Which host family is it?
├── Primary family (old.com, app.old.com)
│     → normal sign-in. Allowed redirect origins = provider defaults + satellite family.
├── Satellite family (new.io, www.new.io, app.new.io)
│   ├── Is it a sign-in or sign-up page?
│   │     → redirect to the primary's sign-in page WITH a return address:
│   │        no return address        → add one: https://app.new.io/<landing>
│   │        relative (/x)            → make it absolute on https://app.new.io/x
│   │        absolute (https://...)   → keep it; the provider's allow-list judges it
│   │        protocol-relative (//x)  → keep it as is; it is NOT relative
│   │        every other parameter    → keep byte for byte (ad click ids, UTMs)
│   ├── Is it the satellite's marketing site asking for an app page?
│   │     → redirect to the SATELLITE's app host, not the configured app URL
│   └── Otherwise → serve it; the provider syncs the session on first visit
└── Anything else (localhost, preview URLs)
      → provider defaults; never satellite
```

## Core Rules

### 1. Decide "satellite or not" per request, from the host

One deployment serves both families, so the choice cannot be a build-time constant.

```ts
// CORRECT: derive from the request host, in middleware and in the provider
export default clerkMiddleware(handler, (req) => {
  const { isSatellite, domain, signInUrl, signUpUrl } =
    deriveDomainOptions(req.headers.get("host") ?? "");
  return isSatellite ? { isSatellite, domain, signInUrl, signUpUrl } : {};
});

// WRONG: one env flag for the whole deployment
const isSatellite = process.env.NEXT_PUBLIC_IS_SATELLITE === "true";
```

Pass plain values, not functions, to the client provider: a server component
cannot hand a function prop across the client boundary.

### 2. Setting allowed redirect origins replaces the defaults: restate them

```ts
// CORRECT: the provider's default list, then the satellite family
allowedRedirectOrigins: [
  requestOrigin,             // default: the request's own origin
  "https://old.com",         // default: the instance's domain
  "https://*.old.com",       // default: its subdomains
  "https://new.io",
  "https://*.new.io",
]

// WRONG: only the new origins; every redirect to the old domain now fails
allowedRedirectOrigins: ["https://new.io", "https://*.new.io"]
```

Read the provider's source or docs for its exact default before restating it.

### 3. Every hand-off carries a way back

```ts
// CORRECT
function withReturnAddress(search: string): string {
  // keep every other pair byte for byte; only add or fix redirect_url
  if (!hasParam(search, "redirect_url"))
    return append(search, "redirect_url", `${SATELLITE_APP}/dashboard`);
  return rewriteParam(search, "redirect_url", (v) =>
    v.startsWith("/") && !v.startsWith("//") ? `${SATELLITE_APP}${v}` : v,
  );
}

// WRONG: re-encoding the whole query (URLSearchParams.toString())
// changes bytes of unrelated parameters, which breaks ad-click attribution
```

Default the return to the same landing page the primary's sign-in falls back to,
so a visitor lands on the same page whichever domain they started on.

### 4. The satellite's site sends app pages to the satellite's app

```ts
// CORRECT
const appUrl = deriveSatelliteAppUrl(host) ?? process.env.APP_URL;

// WRONG: the configured app URL names the primary until the move is finished,
// so every "Sign in" or "Dashboard" link on new.io leaves the new domain
redirect(`${process.env.APP_URL}${path}`);
```

### 5. Check every middleware branch a satellite host can reach

Middleware usually splits by host kind (docs, marketing, app) and returns early. A
satellite rule placed only in the app branch never runs for the satellite's
marketing host, which catches the same paths first. Test each host of the family
against each path type: sign-in, sign-up, an app page, a public page.

## Anti-Patterns

| Anti-pattern | What breaks |
|---|---|
| Moving the provider's primary domain to the new domain | Every existing session, OAuth callback and webhook bound to the old domain; the riskiest change available, for no visitor benefit |
| A redirect to the primary with no `redirect_url` | The visitor signs in and stays on the old domain |
| A `redirect_url` that is relative | It resolves on the primary, not the satellite |
| Rewriting a protocol-relative `//host` as relative | Turns a value the allow-list would refuse into an open redirect on your own domain |
| Satellite logic only in the app branch of middleware | The marketing host of the satellite never reaches it |
| Allowed-redirect list without the provider defaults | Redirects back to the primary family start failing |
| Treating "deploy succeeded" as "sign-in works" | Only a real sign-in proves the session crossed; curl proves the redirects |

## Verification

Redirects are checkable without an account:

```bash
for u in https://new.io/sign-in https://app.new.io/sign-in \
         "https://app.new.io/sign-up?utm_source=x" \
         "https://app.new.io/sign-in?redirect_url=%2Fonboarding" \
         https://new.io/dashboard; do
  printf '%s -> ' "$u"; curl -s -o /dev/null -w '%{http_code} %{redirect_url}\n' "$u"
done
```

Then one real sign-in in a private window, started on the satellite: it must end
on the satellite, signed in. That last step needs a person's account.

## Audit Checklist

- [ ] One primary domain for sign-in; the new domain is a satellite
- [ ] Satellite decided per request from the host, in middleware and in the client provider
- [ ] Allowed redirect origins = provider defaults + satellite family
- [ ] Sign-in and sign-up on every satellite host redirect with a return address
- [ ] Missing return → satellite app landing; relative → absolute on satellite; absolute and `//` → kept
- [ ] Every other query parameter preserved byte for byte
- [ ] The satellite's marketing host sends app pages to the satellite's app host
- [ ] Each satellite host tested against each path type, through every middleware branch
- [ ] OAuth callbacks built from the request host are registered for the satellite app host
- [ ] One real sign-in proven end to end on the satellite
