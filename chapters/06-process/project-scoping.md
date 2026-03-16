---
title: "Project Scoping"
subtitle: "How we estimate and ship on time"
chapter: 20
section: "Process"
seo_title: "Project Scoping for Engineering Teams — Ship in 1-3 Weeks, Every Time (2026)"
seo_description: "Complexity tiers, milestone breakdowns, and anti-patterns for scoping engineering work that ships on time."
keywords: ["project scoping", "engineering estimation", "complexity tiers", "milestone breakdown", "shipping cadence"]
reading_time: "7 min"
difficulty: "beginner"
tech_stack: ["Next.js", "Supabase", "TypeScript"]
business_case: "Eliminate multi-month projects that never ship by enforcing a 3-week maximum with independently shippable milestones."
---

# Project Scoping

> "A project that cannot ship in three weeks is not a project. It is a series of projects pretending to be one."

## The Problem

Engineering teams fail at estimation in a predictable way. A feature gets estimated at "about six weeks." By week three, scope has expanded because someone discovered an edge case that doubles the work. By week five, morale is low because the finish line keeps moving. By week eight, the project ships with cut corners, exhausted engineers, and a backlog of tech debt that never gets addressed.

The root cause is not bad estimation. It is bad scoping. A six-week project was never one project — it was three or four smaller projects bundled together, each with its own dependencies, risks, and unknowns. Bundling them created the illusion of a single deliverable when in reality each piece could (and should) have shipped independently.

The second failure is estimating in abstractions. Story points mean different things to different people. "Large" is subjective. A team that estimates in story points is debating feelings about complexity instead of stating how many days the work will take.

## The Principle

**Every project must be scoped to 1-3 weeks.** If it is longer, break it down. This is not a guideline. It is a constraint that forces clarity.

Here is why the constraint works. Momentum dies after three weeks. Longer projects accumulate scope creep because the longer the timeline, the more stakeholders add "just one more thing." Faster feedback loops lead to better products because you learn from production usage, not from internal reviews. And shipping iteratively reduces risk because each milestone either works or it does not — you never discover in week eight that a foundational assumption was wrong.

**Estimate in days, not story points.** Days are concrete. "Two days" means the same thing to every engineer. "Three story points" triggers a philosophical debate.

**One person per project.** Most projects should have a single owner. One person means clear decision-making, zero coordination overhead, faster velocity, and full context in one head. Add a second person only when the project is two-plus weeks and has genuinely parallel work streams. Never add a third. If you need three people, the project is too big.

## The Pattern

### Complexity Tiers

Use these heuristics to estimate effort and decide if breakdown is needed.

#### Quick Win (0-2 days)

**Signals:** Single file or component change. Clear, well-defined scope. No database migrations. Existing patterns can be copied. Minimal or no new tests needed.

**Examples:**
- Add a status filter to an existing table
- Fix a bug with a known root cause
- Add validation to an existing form
- Update copy or styling

**Action:** Ship as-is. Label it "Quick Win" and do not over-engineer it.

#### Standard (3-5 days)

**Signals:** Multi-component feature. Includes database migration and UI changes. New server actions or repository functions. Requires comprehensive tests. Touches 3-5 files.

**Examples:**
- Add a new entity with CRUD operations (schema, repository, actions, UI)
- Build a new detail view with an expandable sheet
- Integrate a new webhook handler
- Add a new section to an existing page

**Action:** Ship as a single ticket with clear acceptance criteria.

#### Complex (6+ days)

**Signals:** Needs breakdown into 2-3 smaller tickets. Touches more than 10 files. Requires architectural decisions. Involves multiple API integrations. Introduces new patterns or infrastructure.

**Examples:**
- Build a new scheduling flow (calendar UI + API integration + logic)
- Add a new billing tier (payment webhooks + schema + UI + emails)
- Implement a new AI agent (framework config + prompts + UI + validation)

**Action:** Break down into independently shippable milestones. Label it "Needs Breakdown."

### Breaking Down Complex Work

#### Step 1: Identify Independently Shippable Milestones

Each milestone must deliver user value on its own.

**Bad breakdown (not independently shippable):**
1. Create database schema
2. Build API endpoints
3. Build UI

This is bad because milestone 1 and 2 deliver nothing to users. If the project gets paused after milestone 2, you shipped zero value.

**Good breakdown (each milestone ships value):**
1. Read-only view of existing data (no schema changes, reuse existing API)
2. Add create/edit functionality (schema + API + UI together)
3. Add bulk actions and filters (incremental improvement)

Each milestone works in production. If the project gets paused after milestone 1, users still get the read-only view.

#### Step 2: Separate Enablers from Features

**Enablers** are foundation work that does not ship user-facing value: schema migrations, new API endpoints, data pipelines.

**Features** are user-facing changes that deliver value: new UI, workflows, notifications.

Ship enablers first, then unblock feature work:

- **Ticket 1 (Enabler):** Add `status` column to `orders` table [1 day]
- **Ticket 2 (Feature):** Show order status in dashboard UI [2 days] — blocked by Ticket 1

Build enablers just-in-time — when the feature is next in the queue. Never build them speculatively.

#### Step 3: Validate Each Milestone

Before finalizing the breakdown, check each milestone against four criteria:

- **Independently shippable?** Can this go to production on its own?
- **Delivers user value?** Does the user get something from this?
- **Under one week?** Can this be completed in 5 days or less?
- **Clear owner?** Is there one person responsible?

If any answer is "no," re-scope the milestone.

### Project Specs for Large Work

Features estimated at more than one week get a lightweight spec document. The spec is not a novel. It is a forcing function for clarity.

**Key sections:**
- **Problem:** What are we solving? Why now?
- **Solution:** High-level approach (2-3 sentences)
- **Scope:** What is in, what is explicitly out
- **Enablers:** What must exist before we start?
- **Milestones:** 2-3 shippable chunks, each under one week
- **Success Metrics:** How do we know it worked?

**Target length:** Under two pages. If it is longer, the project is too complex. Break it down further.

### Anti-Patterns

**Mixing enabler work with feature work.** "Add calendar integration" bundles schema, API, UI, and webhooks into one ticket. Split it: enabler (schema + API), feature (connection UI), feature (booking flow).

**Tickets that could be three smaller tickets.** "Improve onboarding flow" is vague and multi-week. Split it: add connection status badge [1 day], add reconnection flow [2 days], add progress indicator [1 day].

**Building for hypothetical users.** "Add configurable dashboard widgets" is flexible but nobody asked for it. Build "add top 3 performing items widget" because a real user requested it.

**Estimating in story points.** We do not use story points. Use days. Days are concrete, universally understood, and leave no room for subjective interpretation.

## The Business Case

**Shipping cadence doubles.** When every project is 1-3 weeks and every milestone is independently shippable, teams ship real value to users every week instead of every quarter.

**Scope creep disappears.** A three-week maximum forces hard conversations about scope at the start. "This is a six-week project" becomes "which three weeks matter most?" The answer is always the first three weeks — the rest can ship as a follow-up.

**Risk drops to near zero.** When the longest commitment is three weeks of one person's time, a failed project costs three weeks. Not three months. Not a quarter of the roadmap. Three weeks.

**Estimation accuracy improves over time.** Engineers who estimate in days against a complexity tier system calibrate quickly. After a few cycles, "standard" consistently means 3-5 days because the definition is concrete and the feedback loop is tight.

## Try It

Install the [Modh Playbook](https://github.com/modh-ai/playbook) to get the complexity tier framework, milestone breakdown templates, and project spec format pre-configured for your team's workflow.
