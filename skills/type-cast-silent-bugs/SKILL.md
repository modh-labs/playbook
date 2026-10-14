---
name: type-cast-silent-bugs
description: Type-assertion casts between a database query and consumer code (`as any`, `as unknown as { ... }`, `useState<any[]>`) are silent-bug indicators — they hide column/table drift from the type system. Activates during any type-tightening migration (Drizzle migration, schema rename, ORM swap), any audit that grep-counts these casts, or any "this dashboard's been broken forever, why hasn't it alerted?" investigation.
---

# Type-Cast Silent Bugs

## When This Skill Activates

- You're scoping a Drizzle migration / TypeORM rewrite / library swap that tightens types on DB query results
- You're auditing a codebase for `as any`, `as unknown as`, or `(supabase as any)` patterns
- You're investigating a "this dashboard has been silently broken" report
- You see a query result piped through a cast before its fields are read
- You're writing a new repository function and tempted to use `as any` to "make the type checker happy"

## The Core Principle

> A type-assertion cast between a database query and consumer code is **not a type-safety problem** — it's a **silent-bug smoke alarm**. The cast almost always hides column drift, missing tables, or wrong field names. The bug is downstream; the cast is the giveaway.

## Decision Tree

```
You see a cast like `(supabase as any).from(...)`, `as unknown as { foo_bar: string }`,
or `useState<any[]>` near a database query.

  ↓

Ask the diagnostic question:
  "If I removed this cast, would TypeScript complain about a real column,
   table, or field that no longer matches the schema?"

  ↓                          ↓
 YES (likely)               NO (rare)
  ↓                          ↓
You have a silent bug.       The cast is defensive but
The cast is hiding it.       not hiding behavior. Still
Treat the consumer's         worth removing — it's a
field reads as suspect       liability for future drift.
until verified against
the actual schema.
```

## Why Casts Become Silent-Bug Carriers

Three mechanics combine:

1. **The cast disables structural checking.** TypeScript can no longer verify that `row.foo_bar` exists on the actual return shape.
2. **Postgres tolerates many "wrong" queries silently.** `WHERE non_existent_column IS NULL` returns all rows. `SELECT non_existent_column` returns undefined in some clients. There's no runtime exception.
3. **The wrong-but-plausible data passes integration tests.** Dashboards still render. APIs still respond. Counts are still numbers. The bug only shows up if someone manually verifies against ground truth — which nobody does for "background" admin tooling.

## Core Rules

### Rule 1: When you migrate a repository layer, expect to find silent bugs equal to the cast count

```typescript
// WRONG mental model: "Drizzle migration is mechanical — just swap the syntax"
// RIGHT mental model: "Drizzle migration is bug-detection — every cast is a hypothesis"

// Before: (supabase as any).from("calls").select("recording_status, transcript_status")
// After:  adminDb.select({ recordingStatus: calls.recordingStatus,
//                          transcriptStatus: calls.transcriptStatus }).from(calls)
// Typecheck output: "Property 'recordingStatus' does not exist on type calls"
// → The schema never had these columns. The dashboard has always been broken.
```

### Rule 2: Grep for cast patterns when scoping migration work

```bash
# Three patterns to count, all silent-bug indicators:
grep -rn "(supabase as any)" src/      # most acute (compat layer)
grep -rn "as unknown as" src/          # explicit reshape
grep -rn "useState<any\[\]>" src/      # client-side state cover-up
```

Each match is a hypothesis you'll verify during migration. Budget 5-15 minutes per match for: read the cast, check the schema, find the consumer, decide if the silent bug is fixable in-scope or needs a ticket.

### Rule 3: Don't preserve the cast's shape — verify it

```typescript
// WRONG: trust the cast's claimed shape
const rows = (await supabase.from("users").select("*")) as unknown as Array<{
  id: string;
  nylas_grant_id: string | null;  // ← claimed shape
  nylas_last_sync: string | null;
}>;
// (users.nylas_grant_id doesn't exist — every row's nylas_grant_id is undefined)

// RIGHT: query against the typed schema, see what TypeScript says
const rows = await adminDb
  .select({ id: users.id, nylasGrantId: users.nylasGrantId })  // ERROR
  .from(users);
// "Property 'nylasGrantId' does not exist on type 'users'"
// → The right table is nylas_connections, not users.
```

### Rule 4: When you find a silent bug, fix it forward (don't defer)

The cast was hiding it for months or years. Fixing it costs 10-30 minutes. The cleanup PR that finally surfaces it is the right place to fix it — by the time someone else touches this code they'll be deep in unrelated work and the bug will resurface as a "production incident" instead of a "type cleanup byproduct."

### Rule 5: Document the silent bug in the commit message — not just the cleanup

The cleanup-without-context commit is hard to retroactively understand. Future you will not remember why `recording_status` got replaced with `mediaProcessingStatus`.

```
WRONG: "refactor: migrate /media to typed Drizzle"

RIGHT: "fix(media): migrate to Drizzle + fix non-existent column reads

The previous implementation tried to read recording_status and
transcript_status columns on the calls table — neither column has
ever existed in the schema. The dashboard was silently classifying
every call as 'pending' and updates were silent no-ops, hidden by
an `as unknown as` cast on the consumer side."
```

## Implementation Pattern

When you encounter a cast site during migration:

```typescript
// STEP 1: Identify the cast and the query it sits on
const { data } = await (supabase as any)
  .from("widgets")
  .select("color, size, weight_grams")
  .eq("organization_id", orgId);

// STEP 2: Replace with typed query against the actual schema
//         Let TypeScript surface what's wrong
const rows = await db
  .select({
    color: widgets.color,
    size: widgets.size,
    weightGrams: widgets.weightGrams,  // ← typechecks if column exists
  })
  .from(widgets)
  .where(eq(widgets.organizationId, orgId));

// STEP 3: If typecheck fails, the cast was hiding a silent bug
//         - Column renamed? Update consumer + grep for other consumers
//         - Column never existed? Investigate what the dashboard should do
//         - Wrong table? Migrate to the right table

// STEP 4: Update consumers (snake_case → camelCase for Drizzle)
//         - Each cast you remove makes the next consumer site explicit
//         - The type system propagates the truth outward
```

## Anti-Patterns

### Anti-Pattern 1: "Just preserve the existing behavior"

```typescript
// WRONG: keep the cast to "minimize migration risk"
const rows = await db.select().from(widgets) as unknown as LegacyShape[];

// What you're actually doing: preserving a silent bug.
// The legacy code returned wrong-but-plausible data.
// Your migration now also returns wrong-but-plausible data.
// The fix you skipped today is now a future incident.
```

### Anti-Pattern 2: "We'll fix the silent bug in a follow-up ticket"

```
// What happens: the ticket gets filed, deprioritized, eventually closed
// without comment. The migration ships. The silent bug ships with it.
// Future engineer finds it 6 months later as a P1 customer report.
```

The follow-up ticket has a 30% acceptance rate. The in-scope fix has a 100% acceptance rate.

### Anti-Pattern 3: Catching only `as any`, missing `as unknown as` and `useState<any[]>`

```typescript
// All three are silent-bug indicators. Audit for all three.

const rows = supabase.from("x") as any;                          // OBVIOUS
const rows = supabase.from("x") as unknown as { foo: string }[]; // SUBTLE
const [items, setItems] = useState<any[]>([]);                   // CONSUMER-SIDE
```

The third is especially insidious — it sits in a React component, far from the data source, and silently allows any shape from the action layer.

### Anti-Pattern 4: Replacing the cast with a wider type

```typescript
// WRONG: "I'll narrow `any` to `Record<string, unknown>` — that's better"
const rows = await query() as Record<string, unknown>[];

// You haven't fixed anything. Consumers still read row.foo_bar and get undefined.
// The silent bug still ships. The cast is a tiny bit narrower; that's all.
```

The only meaningful migration is to a **schema-derived type** that the type system can verify against the actual data source.

## Audit Checklist

When auditing a codebase for this pattern:

- [ ] Count all `(* as any)` casts near DB queries
- [ ] Count all `as unknown as { ... }` reshapes
- [ ] Count all `useState<any[]>` / `useState<any>` in client components that consume action data
- [ ] For each cast, identify the data source (which query) and the field reads (which consumer)
- [ ] Spot-check 5-10 random casts against the actual schema — measure your silent-bug hit rate
- [ ] Budget migration time as (cast count) × (5-15 min) for the silent-bug surfacing alone
- [ ] When fixing silent bugs in-scope, document each one in the commit message — not in a follow-up
- [ ] For UI-facing silent bugs (dashboard alerts, status counts), notify the team they're seeing real data for the first time — the "before" state was wrong-but-plausible

## Real-World Numbers

From a single Aura admin Drizzle migration sweep (2026-05-16):

| Cast count grepped | Actual silent bugs found |
|---|---|
| ~100 `(supabase as any)` / `as unknown as` sites | 11 silently-broken production dashboards |

That's roughly **1 silent bug per 9 casts**. The hit rate is high enough that "audit casts for silent bugs" is a real workflow, not a theoretical concern.

The 11 bugs broke down as:
- 4 read non-existent columns (`recording_status`, `nylas_grant_id`, `pending_invites`, `sale_id`)
- 3 queried non-existent tables (`organization_members`, `bookings`, `data_sync_logs` with wrong required fields)
- 2 read non-existent enum values (`media_status = 'processing'`, `outcome` instead of `status`)
- 1 filtered IS NULL on a primary key (always-zero result)
- 1 filtered IS NULL on a notNull column (always-zero result)

Each had been wrong for months. None had alerted. None had been caught by tests. The migration was the first event that surfaced them.
