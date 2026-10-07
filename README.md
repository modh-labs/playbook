# The Modh Playbook

> How Modh Labs builds production software. Battle-tested patterns, standards, and AI agent skills from shipping SaaS at scale.

This is the engineering playbook we use every day. It started as a collection of agent skills — reusable rules that teach AI coding assistants how we write code. But the patterns behind those skills are more valuable than the skills themselves. So we wrote them down.

25 chapters across 7 sections. Each chapter covers one pattern: the problem it solves, the principle behind it, the concrete implementation, and why it matters to the business. We also ship 61 AI agent skills that enforce these patterns automatically in your editor.

## Quick Start

```bash
# Add to your project as a git submodule
git submodule add https://github.com/modh-labs/playbook .agents/modh-playbook

# Install skills (creates symlinks into .claude/skills/)
./.agents/modh-playbook/install.sh
```

## The Chapters

### 1. Data Layer

How we access, mutate, and think about data. No raw queries. No client-side fetching. Type-safe from database to UI.

| Chapter | Core Idea |
|---------|-----------|
| [The Repository Pattern](chapters/01-data-layer/repository-pattern.md) | Why we never write raw database queries |
| [Server Actions](chapters/01-data-layer/server-actions.md) | Type-safe mutations that just work |
| [Data Fetching](chapters/01-data-layer/data-fetching.md) | Server Components changed everything |
| [Database Standards](chapters/01-data-layer/database-standards.md) | Schema-first, types-generated, RLS-enforced |

### 2. Architecture

How we structure applications. Routes own their code. Dependencies point inward. Webhooks are first-class citizens.

| Chapter | Core Idea |
|---------|-----------|
| [Route Colocation](chapters/02-architecture/route-colocation.md) | Files live next to the route that uses them |
| [Webhook Architecture](chapters/02-architecture/webhook-architecture.md) | One handler per event, SOLID registry, idempotency |
| [Multi-Tenant Isolation](chapters/02-architecture/multi-tenant-isolation.md) | RLS enforces org boundaries at the database level |

### 3. Quality

How we keep code correct. Types catch bugs at compile time. Tests catch bugs at merge time. Linters catch bugs before you finish typing.

| Chapter | Core Idea |
|---------|-----------|
| [TypeScript Strict](chapters/03-quality/typescript-strict.md) | Zero `any`, generated types, strict mode always on |
| [Testing Strategy](chapters/03-quality/testing-strategy.md) | Vitest for units, Playwright for flows, mocks for Supabase |
| [CI Pipeline](chapters/03-quality/ci-pipeline.md) | Cheapest checks first, no deploy in CI, fail fast |
| [Code Quality Audit](chapters/03-quality/code-quality-audit.md) | Detect parallel systems, delete dead code, validate against production |
| [Code Review](chapters/03-quality/code-review.md) | Seven dimensions, educational feedback, severity classification |

### 4. Security

How we protect data. RLS is not optional. Validation happens at every boundary. Secrets never touch client code.

| Chapter | Core Idea |
|---------|-----------|
| [Row Level Security](chapters/04-security/row-level-security.md) | Every table has RLS policies, no exceptions |
| [Input Validation](chapters/04-security/input-validation.md) | Zod schemas at every boundary — forms, actions, webhooks |
| [Security Headers](chapters/04-security/security-headers.md) | CSP, CORS, and webhook signature verification |

### 5. Observability

How we understand what is happening in production. Structured logs. Distributed traces. Domain-specific captures. No `console.log`.

| Chapter | Core Idea |
|---------|-----------|
| [Structured Logging](chapters/05-observability/structured-logging.md) | Module loggers with context, never console.log |
| [Error Tracking](chapters/05-observability/error-tracking.md) | Sentry with domain captures, not generic exceptions |
| [Webhook Observability](chapters/05-observability/webhook-observability.md) | Every webhook traced end-to-end with searchable tags |

### 6. Process

How we work as a team. Features start with design, not code. Tickets have acceptance criteria. PRs tell a story.

| Chapter | Core Idea |
|---------|-----------|
| [Feature Design](chapters/06-process/feature-design.md) | Think before you code — 2-3 approaches, then decide |
| [Linear Tickets](chapters/06-process/linear-tickets.md) | User stories, architecture context, sub-task breakdown |
| [Pull Requests](chapters/06-process/pull-requests.md) | CI passes first, then a rich description with test plan |
| [Documentation](chapters/06-process/documentation.md) | Three layers — README, AGENTS.md, inline docs |

### 7. Frontend Craft

How we build interfaces. Server Components by default. Client boundaries pushed to the leaves. Every interaction feels instant.

| Chapter | Core Idea |
|---------|-----------|
| [Component Architecture](chapters/07-frontend-craft/component-architecture.md) | Composition over configuration, colocation over abstraction |
| [Performance Patterns](chapters/07-frontend-craft/performance-patterns.md) | Suspense, streaming, and instant UI feedback |
| [Design Standards](chapters/07-frontend-craft/design-standards.md) | shadcn/ui, semantic tokens, premium by default |
| [Internal Tools](chapters/07-frontend-craft/internal-tools.md) | Data density over visual impact, scannability first |

---

## Agent Skills

61 AI agent skills that enforce these patterns automatically. Compatible with Claude Code, Cursor, GitHub Copilot, Windsurf, and OpenAI Codex.

### Tier 1: Universal (Any Stack, Any Language)

| Skill | When It Activates | What It Does |
|-------|------------------|--------------|
| [`design-taste`](skills/design-taste/) | Building any user-facing UI | Enforces premium design — anti-AI pattern detection, typography rules, color calibration, tunable dials for variance/motion/density |
| [`internal-tools-design`](skills/internal-tools-design/) | Building admin panels, dashboards, ops tools | Optimizes for scannability and data density over visual impact — monospace numbers, dark mode, CSS-only transitions |
| [`output-enforcement`](skills/output-enforcement/) | Any code generation task | Bans `// ...`, `// TODO`, truncation patterns — forces complete, production-ready output |
| [`cross-editor-setup`](skills/cross-editor-setup/) | Setting up AI config for a project | Guides AGENTS.md + CLAUDE.md + Cursor rules setup for multi-agent team compatibility |
| [`provision-live-to-learn-contract`](skills/provision-live-to-learn-contract/) | Scripting create/update against an API (dashboards, webhooks, resources) whose field/enum shape you're inferring; a dry-run that can't validate acceptance | Stop guessing from docs — make ONE real, reversible call and let the error body teach you the exact contract (a single 400 named the transactions→spans deprecation). A green dry-run/typecheck validates only your code, never the server's acceptance |
| [`code-review`](skills/code-review/) | Reviewing PRs, checking branch before push, batch quality sweeps | Seven-dimension review (observability, testing, SOLID, type safety, security, business logic, clean code) with pass/fail verdicts and educational findings |
| [`weekly-infra-health-review`](skills/weekly-infra-health-review/) | Telemetry exists but nobody reads it on a cadence; "is our infra healthy/cheap?" has no one-glance answer; cost or performance drifts unnoticed until it breaks; standing up a scheduled health/cost review for any stack | A dashboard shows numbers but never says what CHANGED or what to DO — the ask is "tell me what to improve", not "collect telemetry". A recurring fresh-session agent runs a fixed checklist (DB advisors + connection headroom, telemetry-quota canary, config-drift-vs-documented-posture, field web-vitals p75, ticket movement) from a SHARED runbook, diffs against last week's posted digest, INTERPRETS signals into causes (errors-live-but-spans-dead → quota exhausted; 118 zero-scan indexes → prune), and posts a tight week-over-week digest ending in 1-3 prioritized "areas of improvement", red first. Distinct from `cron-monitor-checkin` (that detects a job NOT running; this interprets telemetry that exists) |
| [`metric-definition-trap`](skills/metric-definition-trap/) | Putting any number on a report, dashboard, exec deck, or stakeholder message; building/auditing a KPI surface; reporting revenue/MRR/conversions/churn/ROAS/signups; repeating a "we can source this metric" claim | Every metric must name its population and definition, and the number must be adversarially re-queried against live data before it ships. Catches one label hiding two populations (our SaaS revenue vs customers' GMV — a fake $3.9M "revenue" claim) and gross-vs-net inflation (1,812 conversions that were 88% intentional `skipped` rows → 220 real, an 8x overstatement), plus wrong constants ($49 vs real $97 price). Companion to `project-charter` |
| [`print-report-pagination`](skills/print-report-pagination/) | Generating a report/invoice/export PDF from HTML or markdown (Puppeteer, weasyprint, wkhtmltopdf, print CSS); a PDF showing half-cards or stranded headings at page edges; reviewing paged-media CSS | Paginate by what you FORBID from breaking, not where you force breaks — `break-inside: avoid` on boxes/bullets/rows, `break-after: avoid` on headings, let unboxed prose flow. Load-bearing method: stress-test a deliberately 3–4 page render so boxes land near page edges, then inspect every boundary (a short 2-page sample exercises none). Pairs with `browser-pdf-reports` |
| [`progressive-disclosure-ctas`](skills/progressive-disclosure-ctas/) | Designing settings/config forms with many optional fields | Hide optional inputs behind "+ Add X" CTAs that reveal inline editors; LivePreview strip narrates current state; Remove is symmetric to Add; no stuck states |
| [`stale-bot-pr-triage`](skills/stale-bot-pr-triage/) | A bot (Sentry Seer, Dependabot, Renovate, Cursor) opens a fix PR; sweeping a bot-PR backlog; before merging any machine-authored branch | Diff the PR's intent against current main before actioning — they're stale snapshots, often already-fixed (close with the superseding SHA), fixed-better, or regressive (a fix that silently removes a guard). Re-implement genuine value on main against current APIs; never cherry-pick the stale branch |
| [`surface-upstream-errors`](skills/surface-upstream-errors/) | A `catch` around an external SDK/API call (Stripe, Clerk, auth/payment/calendar/email providers); logging just `error.message`; before calling a provider's bulk/batch endpoint | Parse the provider's structured error (status, code, longMessage, trace id) instead of flattening to "Please try again" — surface the real reason in the UI, tag observability by the upstream code, and fingerprint by it so failure modes don't collapse into one opaque bucket. Corollary: pre-filter known conflicts before atomic bulk endpoints so one bad item can't fail the batch |
| [`pii-redaction-parity`](skills/pii-redaction-parity/) | Adding a second log/trace sink; declaring a PII posture ("id + org only"); writing a redact/scrub/beforeSend config; "email in logs even though Sentry scrubbed it" | Enforce ONE sensitive-key list across every egress path (Sentry events/spans/logs + structured-logger redact). Covers the counterintuitive pino flat-dotted key trap — a key named "user.email" is matched only by the path `["user.email"]`, not `"user.email"` — and fixing leaks at the source (stop emitting PII onto spans) not just the sink |
| [`error-report-dedup`](skills/error-report-dedup/) | A capture-and-rethrow wrapper (span/critical-path/retry) nested inside an outer catch that also captures; duplicate tracker issues for one failure | Tag the Error with a non-enumerable `Symbol.for` marker so the second handler skips a duplicate event. Headline bug: the marker is identity-bound, so the inner producer must rethrow the SAME normalized+marked Error, not the raw original. Test both producer and consumer sides |
| [`prove-your-telemetry`](skills/prove-your-telemetry/) | Adding or changing any log line, error capture, tag or metric; an error report at volume that carries no useful detail; a field that is always `undefined`; a signal that went quiet with no deploy; you cannot confirm a shipped fix landed | Broken instrumentation looks exactly like a healthy system, so it survives for months. Ask "if this were completely broken, would it look any different?", then go read a REAL emitted event, not the code that emits it. Five mechanisms: the wrapper (real error on `cause`, the tell is a field empty on 100% of events), the scrubber (`[Filtered]` values, so log structured facts not free text), the pre-handler filter (deny-list entries that can match your own minified code), the wrong hook (instrumented a path events never take), and the dead subject (volume hit zero because the thing got switched off). Rule: health checks assert MOVEMENT, not configuration |

### Tier 2: React / Next.js / TypeScript

| Skill | When It Activates | What It Does |
|-------|------------------|--------------|
| [`react-architecture`](skills/react-architecture/) | Components >300 lines, >15 useState, decomposition work | Hook extraction, state machines, hydration safety, composition patterns, React 19 APIs |
| [`nextjs-patterns`](skills/nextjs-patterns/) | Data fetching, mutations, loading states | Server Components, Suspense boundaries, server actions with Zod, cache invalidation, prefetching |
| [`shadcn-components`](skills/shadcn-components/) | Creating UI components | shadcn/ui rules, CSS variables over hardcoded colors, Sheet toggle pattern, detail view architecture |
| [`nextjs-server-client-boundary`](skills/nextjs-server-client-boundary/) | Client components importing server modules, Storybook/test build failures | Enforces server/client module boundary — client imports actions, never repositories |
| [`form-builder-rhf-isolation`](skills/form-builder-rhf-isolation/) | Dynamic form-builders in React Hook Form + shadcn (question builders, field editors, row lists) | Prevents cascade re-renders + focus loss — `useFieldArray` for READ, `setValue` for WRITE, `useWatch` by index, blur-time key regen |
| [`status-rollup-chip`](skills/status-rollup-chip/) | Admin tables with 6+ columns, horizontal overflow, or columns that together answer one readiness question | Collapses dense columns into one derived chip + popover-with-deep-links + row-click sheet triad; preserves one-click muscle memory for common mutations |
| [`debug-hmr-stale-bundle`](skills/debug-hmr-stale-bundle/) | "Module factory is not available" errors, empty-object error logs, origin-specific failures in Next.js + Turbopack dev | Diagnoses browser-side stale bundles via subdomain/incognito parity test, fixes with site-data clearing, prevents wasted hours reading red-herring stack traces |
| [`middleware-cookie-fast-path`](skills/middleware-cookie-fast-path/) | Edge-cached page needs request-scoped client data (geo, timezone, AB variant, feature flag); tracking script gated behind client-side consent check; N components firing duplicate `/api/*` requests | Stamps client-readable cookie in middleware so client reads synchronously, eliminating post-hydration fetch waterfalls — reference incident was a 34-second mobile Meta Pixel fire on Slow 3G |
| [`navigate-before-dismiss`](skills/navigate-before-dismiss/) | Click handlers that both call `router.push` and close a Radix dismissable (Dialog/Sheet/Popover/CommandDialog/DropdownMenu); "I click the result, popup closes, URL never changes" bug reports; cmdk `asChild` + Next.js `<Link>` shapes | Reorders push-before-dismiss with `queueMicrotask` so Radix's synchronous unmount no longer cancels the intercepted Next.js navigation mid-event; collapses dual `onSelect` + `onClick` handlers via `preventDefault` while preserving anchor `href` for middle-click and copy-link |
| [`control-flow-exceptions`](skills/control-flow-exceptions/) | `try/catch` around a server action, Server Component, or route handler in Next.js App Router; "I see NEXT_REDIRECT in the toast" bug reports; a redirect that "sometimes doesn't happen" after a successful action | `redirect()` / `notFound()` throw control-flow signals, not failures — a naive `catch` swallows the signal, cancels the navigation, and renders the internal digest string to the user. Mandates `unstable_rethrow(error)` as the first line of any catch that wraps redirectable code; includes the server-wrapper digest-detection guard and a regression-test recipe |
| [`overlay-z-index-ladder`](skills/overlay-z-index-ladder/) | Two overlays open at once (hover-card + menu, tooltip + popover); a menu/submenu rendering UNDER another floating element; a dropdown opened inside a dialog appearing beneath it; adding a portal/popover component or auditing a design system's layering | Body-portaled overlays share one stacking context, so the higher z-index wins regardless of DOM order. Maintain one documented tier ladder (sheet → dialog → floating content → toast), keep every floating primitive in the shared floating tier (so a `<select>` works inside a dialog), and make actionable overlays outrank passive ones. Includes the ladder, the actionable-beats-passive rule, and the trapped-stacking-context (ancestor transform/overflow) gotcha |
| [`stream-behind-first-step`](skills/stream-behind-first-step/) | A multi-step client flow (wizard, booking form, checkout) consumes a slow server-prefetched promise via `use()` at the top of the component; first step shows a full-screen skeleton for a slow upstream (availability/search/recommendations); a "slow load" and an unrelated-looking post-load "snap"/double-render reported together | Don't suspend the whole component on data only a later step needs — top-level `use()` blocks the first interactive step (and defers its mount effects, which surfaces as a "double load"). Background-resolve the promise (effect → state) so step 1 paints now and the data streams in behind a localized stencil during the user's dwell; derive the step→step transition from a freshly AWAITED snapshot (not the closed-over memo, empty in the tail) via a pure helper shared with the steady-state render; keep a single upstream call |
| [`headless-form-engine`](skills/headless-form-engine/) | A form/wizard needs a second presentation (all-at-once → stepped/Typeform, modal → page, desktop → mobile); a designer asks to make an existing form "feel like Typeform"; reviewing a PR that adds a second form component reimplementing the first one's validation | One headless controller owns state, validation, and submit, exposed through an EXPLICIT named interface (never inferred) — every presentation is a pure consumer, zero controller edits per new layout (OCP). A state-shape projection (e.g. a step model) is validated at one boundary via a discriminated union, making illegal shapes unrepresentable. The load-bearing deliverable is a parity test: identical inputs → both presentations → byte-identical submit payload, exactly one submit call — covering a gated/consent step, not just the happy path |
| [`portable-component-bundle`](skills/portable-component-bundle/) | Shipping a React component library to a page outside its app build (design-system site, docs page, embed, artifact viewer); bundling components as an IIFE or window global; a bundled library carrying a second React ("Invalid hook call"); Tailwind classes in a shipped bundle rendering unstyled | React once as page globals (React 19 has no UMD, so bundle it as an IIFE), the library as one IIFE with every React entry point and both JSX runtimes mapped to those globals, and a Tailwind v4 stylesheet compiled with `source(none)` from exactly the shipped files so utilities resolve to the host's token names. Fails the build on React's internals key (not the element tag, which react-is also carries) and on `</script`, `<!--` or `</style`, and verifies every preview in every theme with headless Chrome `--dump-dom`, including the two false negatives that misreport a working preview |

### Tier 3: Backend / Infrastructure

| Skill | When It Activates | What It Does |
|-------|------------------|--------------|
| [`supabase-patterns`](skills/supabase-patterns/) | Database queries, migrations, RLS | Repository pattern, schema-first workflow, RLS policies, type generation |
| [`observability`](skills/observability/) | Adding logging, error tracking, tracing | Structured logger factory, Sentry integration, domain capture functions, webhook observability |
| [`write-criticality`](skills/write-criticality/) | Adding error handling for DB writes, retry logic | Three-tier write classification (tracking/retriable/critical), transient retry, alarm severity matching |
| [`observability-cost-quota`](skills/observability-cost-quota/) | A perf/RUM dashboard is empty, traces/spans "stopped", "no recent performance data", or you're about to raise a telemetry bill | Observability is a metered cost with a silent failure mode: errors flowing + spans/logs at zero = quota exhaustion, not an outage (categories meter separately). Diagnose via usage-by-outcome×category; FIX ORDER = cut low-value high-frequency emission first (child spans inherit the parent's sampling), THEN add headroom — so a tiny budget covers it instead of a money pit |
| [`dark-gate-flip-readiness`](skills/dark-gate-flip-readiness/) | Replacing a hot computed/derived read with a cheaper persisted-or-SQL projection; moving status/scoring/rollup derivation into SQL; any "same results, faster read" rewrite | Ship dark behind a default-off flag with the old path as fallback; pin the new path to the source of truth with an automated parity check + a drift invariant + a bounded keyset-streamed backfill; flip on a canary. The one question: "if the new path disagrees for one row, what turns red?" |
| [`webhook-architecture`](skills/webhook-architecture/) | Creating webhook handlers | SOLID handler registry, one handler per event, dependency injection, idempotency |
| [`webhook-patterns`](skills/webhook-patterns/) | Creating webhook routes, adding event handlers | Registry pattern, SRP route handlers, Zod validation, organization resolution service |
| [`webhook-observability`](skills/webhook-observability/) | Adding logging/tracing to webhooks | Webhook logger lifecycle, duration tracking, idempotency checks, error tracker integration |
| [`cron-monitor-checkin`](skills/cron-monitor-checkin/) | Adding/auditing a scheduled job (Vercel cron, GitHub Actions schedule, k8s CronJob) wired to a heartbeat monitor (Sentry Crons, Cronitor, Healthchecks.io); a monitor firing "missed check-in"/`monitor_check_in_failure` you can't trace to code | A monitor is only as real as the producer feeding it. Auto-registered monitors with no check-in report a permanent phantom outage that trains the team to ignore alerts. Centralize the `captureCheckIn` lifecycle in one wrapper (auth → in_progress → ok/error), pin the slug to the platform-derived slug, and orphan-audit monitors against jobs. Origin: a single orphaned canary monitor accrued 1,253 false failures |
| [`background-job-right-sizing`](skills/background-job-right-sizing/) | Adding any background/async job or side-effect; choosing between after()/waitUntil(), a durable queue (Vercel Queues, SQS), a workflow engine (Vercel Workflows, Temporal), or a dedicated orchestrator (Inngest); auditing a job fleet for over-engineering | Pick the LIGHTEST durable rung a job needs via four axes — durability, step count, concurrency shape, cross-app/bus. Most "background jobs" are single-step fire-and-forget side-effects: a durable queue, not a workflow engine. The trap: a consumer-group max-concurrency is account-scope, NOT per-tenant fairness (that needs a keyed primitive). Answer "should we migrate off X?" per-job with the ladder, never all-or-nothing |
| [`auth-webhook-race`](skills/auth-webhook-race/) | Adding tables that mirror auth-provider entities (Clerk, Auth0, WorkOS, Stytch); debugging FK violations on signup; "data missing for new users" reports | Sync-on-first-touch gate in authenticated layouts so the auth provider's webhook is a refresher, not the create path. Eliminates Postgres 23503 races. Includes the ORM `error.cause` unwrap for diagnosis |
| [`webhook-temporal-guard`](skills/webhook-temporal-guard/) | Webhook payloads carrying a time the action depends on (start_time, scheduled_at, expires_at); calendar webhooks (Nylas, Google, Microsoft); Stripe refund/dispute webhooks; "we sent an email about something that already happened" reports | Validates payload time against `now()` at handler boundary AND service entry (defense in depth). Captures past-time blocks as `level: warning` (not critical) since the input is unfixable. Origin: WorldBranding 2026-05-08 — closer edited a calendar event 17 minutes after start_time, integration "rescheduled" to the past |
| [`graphql-patterns`](skills/graphql-patterns/) | Adding GraphQL types, mutations, DataLoaders | Shopify-style graph-first design, Relay pagination, semantic types, N+1 prevention |
| [`datetime-patterns`](skills/datetime-patterns/) | Formatting dates, sending emails with times | Explicit timezone formatting, date boundary bug prevention, multi-recipient email patterns |
| [`hono-patterns`](skills/hono-patterns/) | Building Hono REST/GraphQL APIs | CLI workflow, middleware patterns, Zod validation, request testing without server startup |
| [`monorepo-patterns`](skills/monorepo-patterns/) | Configuring Turborepo, creating packages, CI | Task pipelines, caching strategies, --affected builds, package boundaries, transit nodes |
| [`bun-workspaces-catalog-hoisting`](skills/bun-workspaces-catalog-hoisting/) | Adding a shared dep to 3+ workspaces; auditing a framework family upgrade (Mastra, Next, React, Drizzle); a "low-risk" version bump that fails with "X not exported by Y" deep in the bundler | Hoists shared deps into `workspaces.catalog` (default) or `workspaces.catalogs.{name}` (named family). Default catalog dedupes plain shared deps; named catalogs structurally lock package families that hard-import each other's internals (Mastra is the worst offender) so partial bumps become impossible. Includes the 4-tier prioritization methodology and the bulk-rewrite Python script |
| [`source-export-internal-packages`](skills/source-export-internal-packages/) | Adding/auditing a workspace package's build setup; a just-added export not visible to a dependent until rebuild; a package with a `build` script + `dist/` exports consumed only by other buildable apps; a tracked `dist/` in git | Internal-only TS packages should export source (`exports` → `./index.ts`), never a compiled `dist/`. A built artifact goes stale on source edits and can ship outdated types to production (worse when the app build skips `^build` + ignores type errors). Convert to a Turborepo Just-in-Time package; verify by deleting `dist/` and typechecking. Counter-case: published-to-npm or runtime-`require`'d-untranspiled packages genuinely need a build |
| [`security-and-compliance`](skills/security-and-compliance/) | New tables, auth flows, input validation | RLS enforcement, Zod at boundaries, webhook signatures, GDPR consent, SOC 2 checklist |
| [`testing`](skills/testing/) | Writing tests | Vitest patterns, Supabase mocking, Playwright page objects, `__tests__/` conventions |
| [`e2e-testability`](skills/e2e-testability/) | Writing e2e tests, building UI components | Semantic locators (getByRole first), accessible names, flaky test elimination, Page Object fixtures |
| [`fix-e2e`](skills/fix-e2e/) | An e2e run has failing or skipped tests; before a release gate; after UI changes that break many specs | Four-rung triage ladder (locator drift → test bug → product bug → infra), strict skip policy, two-green-runs exit criteria — refuses retries/waitForTimeout/skip as flake-hiders |
| [`code-quality-audit`](skills/code-quality-audit/) | Auditing routes/modules for quality | Detect parallel systems, SOLID compliance, dead code removal, production data validation |
| [`type-cast-silent-bugs`](skills/type-cast-silent-bugs/) | Type-tightening migrations (Drizzle, ORM swap, schema rename); audits that grep for `as any` / `as unknown as` / `useState<any[]>`; "this dashboard's been silently broken for months" investigations | Reframes type-assertion casts on DB query results as silent-bug indicators rather than type-safety nits — the cast almost always hides column/table drift the type system would otherwise catch. Origin: Aura 2026-05-16 admin Drizzle sweep surfaced 11 silently-broken dashboards (calibration: ~1 silent bug per 9 casts). Includes the diagnostic question, three cast patterns to audit, and the in-scope-fix discipline that prevents follow-up-ticket erosion |
| [`github-ci-efficiency-audit`](skills/github-ci-efficiency-audit/) | "Make CI cheaper/faster without burning minutes"; a CI/Actions billing surprise; hardening a repo/org; a green pipeline that still merges red; `--affected` reding unrelated PRs | Two-question audit (which jobs run on metered runners + how often + is the every-PR install cached; does a red check actually block merge). Finds metered stragglers among third-party runners (Blacksmith/Depot), the dominant high-frequency cron, and the uncached every-PR install. Applies merge-hygiene + secret-scanning + Dependabot + CODEOWNERS via the `gh` CLI. Covers the required-checks ordering trap (don't require CI until the branch is PR-only) and the `--affected` traps that red unrelated PRs: `always()` coverage steps ENOENT-ing, base-ref fallback running everything, a broken base file reding every PR's merge-ref build, and `gh run rerun` replaying the stale merge commit |
| [`dedup-key-completeness`](skills/dedup-key-completeness/) | Writing an upsert/onConflict target, a unique constraint, or a "have we seen this already?" window; "my second booking/order/ticket disappeared or merged into the first" reports; reviewing idempotency on a create path that can fire twice | A dedup/idempotency guard must key on EVERY dimension that makes two records legitimately distinct — a missing dimension silently collapses separate records into one (a lost write with no error, no log). Keep true-retry idempotency (a unique upstream id) separate from fuzzy ±N-second near-duplicate windows; handle null key dimensions deliberately. Includes the diagnostic question, decision tree, CORRECT/WRONG examples, and an audit checklist |
| [`record-the-no-op`](skills/record-the-no-op/) | Code returns early with a `skipped`/`ignored`/`noop` reason; a criterion says a reason is "recorded"; the only trace of a skip is a log line; adding a history or audit write that swallows its own errors; support asks "why didn't this sync?" and the data cannot say | A deliberate no-op is an outcome and needs a durable record. Ask "if a customer asks tomorrow why this didn't happen, where do I read the answer, and will it still be there?" Record it on the entity (not a log), await it but never throw, dedup per entity + reason + window so a repeating skip writes once, label it for any customer-facing feed, prove every written value against the live schema's constraints (a caught rejection looks like a working feature with zero rows), and use production-shaped fixtures for anything a guard filters |
| [`retry-vs-reporting-classifier`](skills/retry-vs-reporting-classifier/) | A feature's error issue firing during every database/provider outage; a catch around a DB call; widening a retry/transient classifier | Keep "should I retry?" and "is this the code's fault?" as two classifiers. Never retry a full pool; file unreachable-dependency failures as a warning in their own group so a feature issue isn't a second outage alarm. Statement timeouts stay the code's own signal |
| [`session-token-claim-budget`](skills/session-token-claim-budget/) | Adding or reviewing claims in an auth provider's session token template; a template copies a whole metadata object; the provider warns about cookie size; a sign-in loop after a successful login; before editing a production token template | A cookie-held session token has a ~4 KB ceiling (Clerk leaves ~1.2 KB for custom claims) and past it the cookie is silently dropped. Ask "for each claim, who reads it and what bounds its size?" Read the live template from config in every environment, decode one real token from your own session, size every user, map each claim to its readers, narrow whole objects to field paths (types survive), cap growing lists where written, then back up, dry-run, prove on staging with a minted token, re-compare prod to the backup, apply, and prove again |

### Tier 4: Workflow / Process

| Skill | When It Activates | What It Does |
|-------|------------------|--------------|
| [`doc-audit`](skills/doc-audit/) | Auditing docs, adding features, before shipping | Three-layer doc system (README + AGENTS.md + CLAUDE.md), coverage reports, staleness detection, gap generation |
| [`feature-design`](skills/feature-design/) | Starting new features | Interactive brainstorming, 2-3 approach proposals, design specs before implementation |
| [`linear-tickets`](skills/linear-tickets/) | Creating issues or tickets | Rich tickets with user stories, architecture context, acceptance criteria, sub-task breakdown |
| [`pull-request`](skills/pull-request/) | Creating PRs | CI validation first, rich descriptions with summary + test plan |
| [`ci-pipeline`](skills/ci-pipeline/) | Modifying CI/CD | CI checks only (no deploy), cheapest-first ordering, extensible step pattern |
| [`documentation-architecture`](skills/documentation-architecture/) | Adding features, creating docs, organizing knowledge | Three-layer system (README + AGENTS.md + CLAUDE.md), JSDoc tiers, cross-editor compatibility |
| [`route-colocation`](skills/route-colocation/) | Creating routes, organizing files | Colocate with routes, share at 3+ usages, actions folder pattern |
| [`bug-cleanup-triage`](skills/bug-cleanup-triage/) | Planning a backlog cleanup session, before dispatching research agents, umbrella tickets stuck In Progress for weeks | Three-phase framework (hygiene → investigation → fixing) with git log pre-flight, Sentry module-tag verification, and umbrella breakdown auto-detection |
| [`verifying-commit-scope`](skills/verifying-commit-scope/) | Any `git commit` in a repo with husky/lefthook + lint-staged + auto-format `--write`, especially with concurrent unstaged work in the tree | Catches pre-commit auto-formatters silently absorbing concurrent agents' unstaged work into your commit. Run `git diff --cached --stat` before commit, `git show --stat HEAD` after, and reset cleanly when the file count doesn't match |

---

## Install

### Full Install (All Skills)

```bash
git submodule add https://github.com/modh-labs/playbook .agents/modh-playbook
./.agents/modh-playbook/install.sh
```

### Selective Install

```bash
# Just universal skills (works with any stack)
./install.sh . --tier=universal

# Universal + React/Next.js
./install.sh . --tier=universal --tier=react

# Backend only
./install.sh . --tier=backend

# Everything + generate configs for all agents
./install.sh . --all-agents
```

### Updating

```bash
cd .agents/modh-playbook && git pull
```

Because install.sh creates symlinks (not copies), pulling updates to the submodule immediately updates all skills. No reinstall needed.

---

## About

These are the patterns we actually use at [Modh Labs](https://modh.ca). They have been refined through building production SaaS products — finding what works, what the AI keeps getting wrong, and encoding those lessons so we do not repeat ourselves.

We are sharing them because we think they are useful. Take what works for you, ignore what does not.

## License

MIT — use freely in personal and commercial projects.
