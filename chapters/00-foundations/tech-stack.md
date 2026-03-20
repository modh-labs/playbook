---
title: "Tech Stack Selection"
subtitle: "Why every tool in our stack exists, and why yours might be different"
chapter: 0
section: "Foundations"
seo_title: "Production SaaS Tech Stack: Next.js, Supabase, TypeScript, Stripe & More (2026)"
seo_description: "An opinionated guide to choosing a tech stack for production SaaS. Battle-tested choices from shipping real products, with reasoning you can adapt to your own constraints."
keywords: ["tech stack", "Next.js", "Supabase", "TypeScript", "Stripe", "shadcn/ui", "Vitest", "Playwright", "Turborepo", "Sentry", "Mastra", "Hono", "Nylas", "Clerk", "Biome", "Inngest", "Linear", "Slack", "Granola"]
reading_time: "18 min"
difficulty: "beginner"
tech_stack: ["Next.js", "Supabase", "TypeScript", "Stripe", "Clerk", "Tailwind CSS", "shadcn/ui", "Vitest", "Playwright", "Biome", "Turborepo", "Sentry", "Mastra", "Hono", "Nylas", "Inngest", "Linear", "Slack", "Granola"]
business_case: "Every tool choice either accelerates your team or creates drag. This chapter documents the reasoning behind each decision so you can make yours deliberately."
---

# Tech Stack Selection

> "The best stack is the one that disappears. You should be thinking about your product, not fighting your tools."

## The Problem

Most tech stack decisions happen by accident. Someone starts a tutorial, copies a boilerplate, or picks whatever they used at their last job. The codebase grows. Dependencies accumulate. Six months later the team is debugging a library they never consciously chose, reading GitHub issues from 2019, and wondering why everything feels so hard.

The opposite failure is just as common. Teams spend weeks evaluating frameworks, building proof-of-concept projects, writing comparison matrices, and still end up second-guessing their decisions once real complexity arrives. Analysis paralysis dressed up as due diligence.

We have shipped multiple production SaaS products. Along the way we have made every mistake on this spectrum: adopting tools without thinking and overthinking tools that did not matter. What follows is the stack we actually use, the reasoning behind each choice, and (critically) which decisions matter and which ones you should spend exactly zero hours debating.

## The Principle

A tech stack is a set of bets. You are betting that each tool will solve more problems than it creates over the lifetime of the product. Good bets share three qualities: the tool has a thriving ecosystem, the failure modes are well-documented, and switching costs are contained.

Notice what is not on that list: performance benchmarks, GitHub stars, or what a thought leader tweeted last week. Those are noise. The signal is whether the tool will still be a good choice when you are debugging a production incident at 2am with a customer on the phone.

Every tool in our stack was chosen because it solved a real problem we hit in production. Not because it was trending. Not because it had the best landing page. Because we needed it, tried the alternatives, and this one caused the least pain.

## The Stack

### Framework: Next.js (App Router)

Server Components changed the game. Before React Server Components, every SaaS product shipped a JavaScript-heavy client that fetched data after the page loaded. Users stared at loading spinners. Developers maintained two mental models, one for the server and one for the client. Data fetching libraries like React Query existed because the default path was bad.

With the App Router, data fetching happens on the server. Components render with data already present. The client receives HTML, not a loading skeleton. The mental model collapses to one: your component is a function that takes data and returns UI. If it needs interactivity, you push that boundary to the smallest leaf component possible.

Why App Router over Pages Router: colocated layouts mean you define your navigation shell once and it persists across route transitions without re-rendering. Streaming lets you show critical content immediately while slower data loads in the background. Parallel routes let independent sections of a page load independently. These are not nice-to-haves. They are the features that make complex SaaS dashboards feel instant.

We use Next.js because the productivity delta between "server-rendered by default" and "client-rendered with a fetching library" is enormous. Less code, faster pages, simpler architecture.

### Language: TypeScript Strict

Zero `any`. Not as an aspiration, but as a linting rule that blocks your commit.

We generate types directly from the database schema. When a column gets renamed, the type changes. When the type changes, every file that references it gets a compile-time error. The developer follows the red squiggles, fixes each reference, and ships with confidence. No grepping. No "I think I got them all." The compiler tells you exactly what broke and where.

Strict mode catches entire categories of bugs at compile time: null reference errors, missing function arguments, incorrect return types, property access on potentially undefined values. These are the bugs that waste hours in production because they surface as undefined values deep in a call stack, far from where the actual mistake was made.

The cost is ten minutes of configuration. The return is thousands of hours of avoided debugging across the lifetime of the project. This is the single highest-leverage decision in the entire stack.

### Database: Supabase (PostgreSQL + RLS)

PostgreSQL is the most reliable open-source database. That is not an opinion. It is 35 years of production deployment history. Supabase wraps PostgreSQL with a developer experience layer: instant REST and GraphQL APIs, real-time subscriptions via websockets, built-in auth, and a dashboard that makes schema exploration fast.

But the real reason we chose Supabase is Row Level Security.

In a multi-tenant SaaS, every query must be scoped to the current organization. Without RLS, that scoping happens in application code: a `WHERE org_id = ?` clause that every developer must remember to add to every query. One missed clause and you have a data leak. We have seen this happen in production on multiple codebases. It is not a theoretical risk.

RLS enforces tenant isolation at the database level. The policy says "users can only see rows where the org_id matches their JWT claim." No application code can bypass it. No developer can forget it. The database itself is the security boundary. This is defense in depth that actually works because it requires zero ongoing discipline from the team.

### Auth: Clerk

Authentication is a solved problem. Building it yourself is one of the most expensive decisions you can make, not because the initial login flow is hard, but because the long tail is brutal. Password reset flows. Email verification. Session management. Organization switching. Invite-based onboarding. Admin dashboards for managing users. SAML SSO for enterprise customers.

Clerk handles all of this. Organizations are first-class: creating an org, inviting members, managing roles, switching between orgs. It all works out of the box. Webhooks fire on every membership change so your database stays in sync. The JWT includes the organization ID, which plugs directly into Supabase RLS.

Why not NextAuth: no built-in organization management, no admin dashboard, and significantly more DIY work for features that every SaaS needs. NextAuth is excellent for simple auth, but multi-tenant SaaS auth is not simple.

Why not Auth0: pricing becomes unpredictable at scale, the developer experience has more friction, and the documentation sprawl makes it hard to find answers quickly. Clerk's documentation is a competitive advantage.

### Payments: Stripe

Stripe is not the cheapest payment processor. It is the most capable. The difference matters when your billing model evolves, and it will evolve.

We have built subscription billing with monthly and yearly intervals, seat-based pricing with prorated upgrades, usage-based add-ons, and mixed-interval billing where extra seats bill monthly on a yearly subscription. Every one of these scenarios has edge cases that only surface in production: prorations during plan changes, failed payment retries, subscription pauses, refund calculations.

Stripe handles all of this. The webhook system is reliable and well-documented. The customer portal lets users manage their own billing without you building UI. The invoicing system handles tax calculation. The ecosystem (Stripe Tax, Stripe Billing, Stripe Connect) means you are not hitting walls as the business grows.

Why Stripe over alternatives: the alternatives are catching up on features but not on ecosystem depth. When you need to debug a failed payment at 2am, you want the platform with the most StackOverflow answers and the most battle-tested webhook patterns.

### UI: Tailwind CSS + shadcn/ui

Utility CSS divides opinion. We have used it long enough to be past the aesthetic debate and into the practical reality: Tailwind is faster for building production interfaces than any alternative we have tried.

The reason is simple. When you write `className="flex items-center gap-2 p-4 rounded-lg border"`, every property is visible at the point of use. You do not need to context-switch to a CSS file. You do not need to name things. You do not need to worry about specificity conflicts. The mental overhead of styling drops to near zero, and that overhead compounds across every component in your application.

shadcn/ui is not a component library in the traditional sense. You do not install it as a dependency. You copy the component source code into your project. This means you own every line. When you need to customize the DatePicker behavior, you edit the file directly. No forking, no monkey-patching, no waiting for a maintainer to merge your PR.

Why shadcn over other component libraries: version lock-in is the silent killer of component libraries. We have been through upgrade cycles on Material UI and Chakra where a major version bump required touching every component in the application. With shadcn, there is no version to upgrade. You own the code.

### Testing: Vitest + Playwright

Vitest for unit tests. It is fast, ESM-native, and has excellent TypeScript support without configuration. The watch mode re-runs only affected tests, which keeps the feedback loop under two seconds. The API is Jest-compatible, so the learning curve is flat if your team already knows Jest.

Playwright for end-to-end tests. It is the most reliable browser automation tool we have used. The auto-waiting mechanism means you do not write `sleep(2000)` and pray. Playwright waits for elements to be interactive before acting on them. Multi-browser support is built in. The codegen tool records user interactions and generates test code, which is a massive time-saver for complex flows.

Why not Jest: Jest is CJS-first in a world that has moved to ESM. TypeScript support requires additional configuration. The test runner is measurably slower on large suites. Vitest is the natural successor.

### Code Quality: Biome

One tool for linting and formatting. That sentence alone is the argument.

ESLint + Prettier is two tools, two configurations, and a plugin (`eslint-config-prettier`) to prevent them from fighting each other. The configuration surface area is enormous. The execution speed, even with caching, is noticeably slow on large codebases.

Biome does both jobs in a single pass, ten times faster, with a single configuration file. It formats on save. It catches lint errors at commit time. The rules are opinionated and sensible defaults, which means less time debating configuration and more time writing code.

### Monorepo: Turborepo

A SaaS product is never one package. You have the web app, the API, shared types, shared components, shared database access, maybe a marketing site. Without a monorepo, these packages live in separate repositories with version management, publish cycles, and the constant question of "did I update the shared types in all three consumers?"

Turborepo makes this simple. It understands task dependencies: "run the type generation before the type check, run the type check before the build." It caches results: if the shared types package has not changed, do not rebuild it. Remote caching means your CI pipeline benefits from the same cache your laptop built.

Why not Nx: Nx is more powerful and more complex. For the monorepo needs of a typical SaaS product (five to ten packages, straightforward dependency graphs) Turborepo is the right tool. It does less, and that is the point.

### Observability: Sentry

Your application will break in production. The question is whether you find out from a customer email or from your monitoring platform.

Sentry captures errors with full stack traces, request context, and user information. But the real value is in how you use it. We build domain-specific capture functions, not generic `captureException(error)` calls, but typed functions that attach business context to every error. When a booking fails, the Sentry issue shows you exactly which user, which provider, and which entity was involved. No log diving.

Session replay lets you watch exactly what a user did before they hit an error. Distributed tracing connects a webhook arrival to the database write to the email send. Performance monitoring shows you which API routes are slow before users complain.

Why Sentry over alternatives: it is a single platform for errors, performance, session replay, and logging. The alternative is stitching together Datadog for APM, LogRocket for session replay, and PagerDuty for alerting. That is three vendor relationships, three billing cycles, and three dashboards to check.

### Background Jobs: Inngest

Every SaaS product eventually needs to do work outside the request-response cycle. Sending emails after a booking. Processing a recording after a call ends. Syncing data from a third-party webhook. Retrying a failed payment. These are background jobs, and getting them right is surprisingly hard.

Inngest is an event-driven job system. You define functions that respond to events, and Inngest handles execution, retries, concurrency, and observability. The mental model is clean: "when this event happens, run this function." If the function fails, Inngest retries it with exponential backoff. If the function needs to wait for something (a recording to finish processing, a third-party API to respond), it can sleep and resume without holding a connection open.

Why not a raw queue (SQS, Redis, BullMQ): because you end up rebuilding retry logic, dead letter queues, concurrency controls, and observability from scratch. Inngest gives you all of that out of the box, with a dashboard that shows you every function execution, its inputs, its outputs, and where it failed. When a background job breaks at 2am, you want a dashboard, not `grep`.

Why not cron jobs: because cron is fire-and-forget with no retry semantics, no concurrency control, and no visibility into what happened. Inngest functions are durable, observable, and composable.

### AI Agents: Mastra

AI agents in production SaaS are not chatbots. They are tools that process data, make decisions, and take actions: summarizing a sales call, scoring a lead, generating a report. The framework you use for this needs tool calling (so the agent can interact with your systems), memory (so it can reference prior context), and observability (so you can debug what it did and why).

Mastra is TypeScript-native, which means it shares types with the rest of the codebase. It integrates with Sentry tracing, so agent execution shows up as spans in the same traces as your API routes. It supports multiple LLM providers without lock-in.

The agent framework space is moving fast. Mastra is our current choice because it prioritizes production concerns (observability, type safety, testability) over demo concerns like "look what it can do in a notebook."

### API: Hono

When you need a standalone API server (for partner integrations, webhooks, or services that do not fit inside a Next.js route) Hono is the framework.

It is lightweight, fast, and runs anywhere: Node, Edge workers, Bun, Cloudflare Workers, Deno. The middleware system composes cleanly. Routes are type-safe. The API surface is small enough that a new developer can read the documentation in an afternoon.

Why Hono over Express: Express is from 2010. It predates async/await, ES modules, and modern deployment targets. It works, but every project built on Express carries fifteen years of backward-compatible decisions. Hono was designed for the current ecosystem: edge-native, middleware-composable, and TypeScript-first.

### Scheduling: Nylas

Calendar integrations are a special kind of pain. Google Calendar, Microsoft Outlook, and iCloud all use different APIs, different OAuth flows, different event formats, and different webhook systems. Building direct integrations means maintaining three sets of credentials, three OAuth refresh flows, three webhook parsers, and three sets of calendar format translations.

Nylas abstracts all of this behind a single API. You send one request to create an event, and it works across providers. You receive one webhook format for event changes, regardless of the source calendar. The grant system handles OAuth complexity. Users connect their calendar once, and Nylas manages the token lifecycle.

Why not build it yourself: because the edge cases will eat you alive. Recurring event exceptions. Timezone handling across providers that interpret "floating time" differently. OAuth token refresh races. Webhook deduplication. We have spent enough time on calendar integrations to know that this is a problem worth paying someone else to solve.

### Project Management: Linear

Issue trackers shape how your team thinks about work. Most tools (Jira, Asana, Monday) optimize for project managers: dashboards, Gantt charts, custom fields, approval workflows. Linear optimizes for engineers: keyboard-first navigation, sub-second performance, opinionated workflows that eliminate configuration decisions.

The speed matters more than you think. When opening a ticket takes two seconds instead of eight, engineers actually read the ticket before starting work. When creating an issue is faster than sending a Slack message, people document bugs instead of mentioning them in passing. The tool's speed changes the team's behavior.

Linear's cycle system (two-week sprints with automatic rollover) keeps work moving without the ceremony of sprint planning meetings. The API is clean and well-typed, which makes automation straightforward. Triage workflows surface unplanned work before it derails a sprint. Labels, projects, and initiatives create just enough hierarchy without the nesting hell of Jira epics inside epics inside initiatives.

Why not Jira: because Jira is optimized for process compliance, not developer velocity. Every Jira workspace we have inherited has 47 custom fields, three approval workflows, and a board nobody trusts. Linear's constraints are its strength.

### Team Communication: Slack

Slack is not a productivity tool. It is the connective tissue between every other tool in your stack. Stripe webhook failed? Slack alert. Deployment completed? Slack notification. Customer reported a bug? Slack thread that becomes a Linear ticket. New team member joined? Clerk webhook triggers a Slack welcome message.

The value of Slack is not chat. It is integration. Every tool in this stack has a Slack integration, which means Slack becomes the single place where your team sees what is happening across the product. Channel conventions matter: a `#deploys` channel for deployment notifications, an `#alerts` channel for production errors, a `#billing` channel for payment events. When channels have clear purposes, Slack becomes a dashboard, not a distraction.

The MCP (Model Context Protocol) integration with Slack lets AI agents read channel history, search for discussions, and post updates. This means your AI coding assistant can check "what did the team decide about this feature?" before proposing an implementation. Context that used to live only in people's heads becomes searchable and actionable.

### Meeting Intelligence: Granola

Meetings happen. Decisions get made. And then everyone walks away with a slightly different understanding of what was decided. Two weeks later, nobody can find the notes, and the same discussion happens again.

Granola records and transcribes meetings with AI-generated summaries, action items, and decision logs. The transcripts are searchable and linkable, which means "we discussed this in the March 5th call" becomes a clickable reference instead of a vague memory.

The MCP integration is where Granola becomes powerful for engineering teams. When an AI agent is helping you design a feature, it can query Granola for relevant meeting context: "What did the stakeholder say about this requirement? What constraints were mentioned? What was the timeline?" This turns meeting discussions into structured context that informs implementation decisions. Design documents reference specific meeting notes. Linear tickets link to the conversation where the requirement originated.

Why not just take notes manually: because manual notes capture what the note-taker thought was important, which is not always what turns out to be important. Full transcripts with AI summarization give you both the summary and the source material when you need to go deeper.

## The Decision Framework

Not every tool decision carries equal weight. We think about stack decisions in three tiers:

**Tier 1: Hard to change.** Your framework, your language, your database. These decisions cascade through every file in your codebase. Choose deliberately, and accept that switching costs are high. Spend time here.

**Tier 2: Medium to change.** Your auth provider, your payment processor, your UI library. These have integration surfaces throughout the application, but they sit behind abstraction layers (or should). A migration is a project, not a rewrite.

**Tier 3: Easy to change.** Your linter, your test runner, your monorepo tool, your project tracker. These affect developer experience but do not affect your product architecture. Switching from Vitest to Jest is a weekend. Do not agonize over these.

The mistake we see most often is spending Tier 1 energy on Tier 3 decisions. Teams debate linter configurations for weeks while making their database choice in an afternoon. Invert that. Spend your deliberation budget where the switching costs are highest.

## Make It Yours

Everything in this chapter is opinionated. That is the point. Opinions based on production experience are more useful than a neutral comparison matrix that leaves you exactly where you started.

But these are our opinions, shaped by the products we have built, the problems we have hit, and the constraints we operate under. Your constraints are different. Your team's experience is different. Your product's requirements are different.

Here is what matters: the patterns in this playbook transcend any specific tool.

- If you use **Prisma instead of Supabase**, the repository pattern still applies. You change the implementation inside the repository file. The rest of your codebase never knows the difference.
- If you use **NextAuth instead of Clerk**, the multi-tenant isolation pattern still applies. You just wire the org ID from a different source.
- If you use **Drizzle instead of raw Supabase queries**, the generated-types-from-schema principle still applies. The tool changes; the discipline does not.
- If you use **Jest instead of Vitest**, the testing strategy still applies. Unit tests for logic, integration tests for data flows, E2E tests for critical user journeys.
- If you use **ESLint + Prettier instead of Biome**, the code quality principle still applies. Automate formatting and linting so humans never argue about it.
- If you use **BullMQ instead of Inngest**, the background job patterns still apply. Retry logic, observability, and idempotency matter regardless of the queue system.
- If you use **Jira instead of Linear**, the triage and ticket quality patterns still apply. Clear acceptance criteria and severity classification transcend any tool.

The skills in this playbook are designed to be forked and adapted. Every skill file uses your stack's conventions, but the underlying patterns (repository layers, domain captures, traced actions, webhook registries, Zod validation at boundaries) work regardless of which ORM, which auth provider, or which component library you chose.

Your tech stack is yours. The patterns matter more than the tools.

## Try It

Install the Modh Playbook skills to get opinionated defaults that you can customize:
```bash
# Add to your project
git submodule add https://github.com/modh-labs/playbook .agents/modh-playbook
./.agents/modh-playbook/install.sh
```
