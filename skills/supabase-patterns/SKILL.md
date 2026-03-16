---
name: supabase-patterns
description: Implement database access and schema management with Supabase. Use when writing repository functions, database queries, creating tables, running migrations, RLS policies, or generating types. Enforces repository pattern, select *, schema-first workflow, and org isolation via RLS.
allowed-tools: Read, Grep, Glob, Edit, Write, Bash
tier: backend
icon: database
title: "Supabase & Repository Patterns"
seo_title: "Supabase & Repository Patterns — Modh Engineering Skill"
seo_description: "Implement database access and schema management with Supabase. Enforces repository pattern, select *, schema-first workflow, and org isolation via RLS."
keywords: ["supabase", "repository pattern", "database", "RLS", "migrations"]
difficulty: intermediate
related_chapters: []
related_tools: []
---

# Supabase Patterns Skill

## When This Skill Activates

This skill automatically activates when you:
- Write or modify repository files (`*.repository.ts`)
- Create database queries using the Supabase client
- Discuss database schema changes, migrations, or RLS
- Need CRUD operations for an entity
- Work with generated TypeScript types from the database

---

## Section 1: Repository Pattern

### Core Principle

All database access goes through repository functions. Pages and server actions never call `supabase.from()` directly.

```
Server Action / Page
    | calls
Repository Function (typed, tested)
    | queries
Supabase Client (with RLS)
    | returns
Typed Data
```

### Rule 1: Always use `select *`

Never pick specific columns. Always `select *` for the main table and all relations.

```typescript
// Wrong -- column picking
.select("id, title, created_at")
.select(`id, title, user:users(id, name, email)`)

// Correct -- always select *
.select("*")
.select(`
  *,
  user:users!items_user_id_fkey(*)
`)
```

Why: Types automatically stay in sync with the schema. No maintenance burden when columns change.

### Rule 2: Accept SupabaseClient as the first parameter

Every repository function receives the client -- it never creates one internally.

```typescript
// Wrong -- creating client inside function
export async function getItems() {
  const supabase = await createClient();
  // ...
}

// Correct -- accept client as parameter
export async function getItems(
  supabase: Awaited<ReturnType<typeof createClient>>,
  filters?: ItemFilters
) {
  // ...
}
```

Why: Allows both authenticated clients (RLS-scoped) and service role clients (webhooks). Enables testing with mocks.

### Rule 3: Use generated types from the database schema

Never create custom interfaces for database entities.

```typescript
// Wrong -- custom interface
interface Item {
  id: string;
  title: string;
  created_at: string;
}

// Correct -- generated types
import type { Database } from "@/lib/supabase/database.types";
type Item = Database["public"]["Tables"]["items"]["Row"];
type ItemInsert = Database["public"]["Tables"]["items"]["Insert"];
type ItemUpdate = Database["public"]["Tables"]["items"]["Update"];
```

### Rule 4: Let RLS handle organization_id

Never pass organization_id in queries. RLS policies read it from the JWT automatically.

```typescript
// Wrong -- manual org filter
.eq("organization_id", orgId)

// Correct -- RLS handles it
const { data } = await supabase.from("items").select("*");
```

### Repository File Template

```typescript
import type { QueryData } from "@supabase/supabase-js";
import type { Database } from "@/lib/supabase/database.types";
import { createClient } from "@/lib/supabase/server";

type Item = Database["public"]["Tables"]["items"]["Row"];
type ItemInsert = Database["public"]["Tables"]["items"]["Insert"];
type ItemUpdate = Database["public"]["Tables"]["items"]["Update"];

// Query builder with standard relations
function buildItemQuery(
  supabase: Awaited<ReturnType<typeof createClient>>
) {
  return supabase.from("items").select(`
    *,
    category:categories!items_category_id_fkey(*)
  `);
}

export type ItemWithRelations = QueryData<
  ReturnType<typeof buildItemQuery>
>[number];

export async function getItems(
  supabase: Awaited<ReturnType<typeof createClient>>,
  filters?: { status?: string }
): Promise<ItemWithRelations[]> {
  let query = buildItemQuery(supabase)
    .order("created_at", { ascending: false });

  if (filters?.status) {
    query = query.eq("status", filters.status);
  }

  const { data, error } = await query;
  if (error) throw error;
  return data || [];
}

export async function getItemById(
  supabase: Awaited<ReturnType<typeof createClient>>,
  id: string
): Promise<ItemWithRelations | null> {
  const { data, error } = await buildItemQuery(supabase)
    .eq("id", id)
    .single();
  if (error) throw error;
  return data;
}

export async function createItem(
  supabase: Awaited<ReturnType<typeof createClient>>,
  input: ItemInsert
): Promise<Item> {
  const { data, error } = await supabase
    .from("items")
    .insert(input)
    .select("*")
    .single();
  if (error) throw error;
  return data;
}

export async function updateItem(
  supabase: Awaited<ReturnType<typeof createClient>>,
  id: string,
  updates: ItemUpdate
): Promise<Item> {
  const { data, error } = await supabase
    .from("items")
    .update(updates)
    .eq("id", id)
    .select("*")
    .single();
  if (error) throw error;
  return data;
}

export async function deleteItem(
  supabase: Awaited<ReturnType<typeof createClient>>,
  id: string
): Promise<void> {
  const { error } = await supabase
    .from("items")
    .delete()
    .eq("id", id);
  if (error) throw error;
}
```

---

## Section 2: Schema-First Workflow

### Core Workflow

Never manually write migration files. Always follow this sequence:

```
1. Edit domain SQL  ->  2. Run db diff  ->  3. Review migration  ->  4. Apply  ->  5. Generate types
```

### Step 1: Update Domain SQL

Schema definitions live in domain-specific SQL files (e.g., `schemas/items.sql`, `schemas/users.sql`). Edit the appropriate domain file:

```sql
-- schemas/items.sql

CREATE TABLE items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id text NOT NULL,
  title text NOT NULL,
  description text,
  status text DEFAULT 'active',
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

-- Indexes
CREATE INDEX idx_items_org ON items(organization_id);
CREATE INDEX idx_items_status ON items(status);

-- RLS
ALTER TABLE items ENABLE ROW LEVEL SECURITY;

CREATE POLICY "org_isolation" ON items
  FOR ALL USING (organization_id = (auth.jwt() ->> 'org_id')::text);
```

### Step 2: Generate Migration from Diff

```bash
supabase db diff -f <migration_name> --linked
```

This creates a timestamped migration file automatically.

### Step 3: Review the Generated Migration

Always review before applying. Check for correct table definitions, RLS policies, and no unintended changes.

### Step 4: Apply Migration

```bash
supabase db push --linked
```

### Step 5: Generate TypeScript Types

```bash
supabase gen types typescript --linked > lib/supabase/database.types.ts
```

### Safe Migration Patterns

**Adding columns:**
```sql
-- Safe: nullable column (no downtime)
ALTER TABLE items ADD COLUMN notes text;

-- Safe: column with default
ALTER TABLE items ADD COLUMN is_active boolean DEFAULT true;

-- Requires backfill: NOT NULL without default
-- Step 1: Add nullable
ALTER TABLE items ADD COLUMN timezone text;
-- Step 2: Backfill
UPDATE items SET timezone = 'UTC' WHERE timezone IS NULL;
-- Step 3: Add constraint
ALTER TABLE items ALTER COLUMN timezone SET NOT NULL;
```

**Renaming columns (multi-step):**
```sql
-- Dangerous: direct rename breaks production
ALTER TABLE items RENAME COLUMN name TO title;  -- Don't do this

-- Safe: multi-step
-- Migration 1: Add new column
ALTER TABLE items ADD COLUMN title text;
-- Migration 2: Backfill + update code to use both
UPDATE items SET title = name WHERE title IS NULL;
-- Migration 3: After code deployed, drop old column
ALTER TABLE items DROP COLUMN name;
```

### Full migration workflow: `references/migration-workflow.md`

---

## Section 3: RLS Policies

### Every Table Needs organization_id + RLS

No exceptions. Multi-tenancy requires org isolation at the database level.

### Standard Pattern: Org Isolation

```sql
ALTER TABLE "public"."items" ENABLE ROW LEVEL SECURITY;

-- Authenticated users: own org data only
CREATE POLICY "items_org_read" ON "public"."items"
  FOR SELECT
  TO authenticated
  USING (organization_id = (auth.jwt() ->> 'org_id')::text);

-- Service role: full access (webhooks, system operations)
CREATE POLICY "items_service_role" ON "public"."items"
  FOR ALL
  TO service_role
  USING (true)
  WITH CHECK (true);

-- Grants
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE "public"."items" TO "authenticated";
GRANT ALL ON TABLE "public"."items" TO "service_role";
```

### Security Function Pattern (recommended for new tables)

If your project defines a reusable security function (e.g., `can_access_organization_data()`), prefer it for new tables. It handles multiple JWT formats and service role bypass centrally:

```sql
CREATE POLICY "items_authenticated_read" ON "public"."items"
  FOR SELECT
  TO authenticated
  USING (can_access_organization_data("organization_id"));
```

### Admin-Only Operations

```sql
CREATE POLICY "admin_only_delete" ON "public"."sensitive_items"
  FOR DELETE USING (
    organization_id = (auth.jwt() ->> 'org_id')::text
    AND (auth.jwt() ->> 'org_role') = 'org:admin'
  );
```

### Public Read, Org Write

```sql
CREATE POLICY "public_read" ON "public"."public_content"
  FOR SELECT USING (true);

CREATE POLICY "org_write" ON "public"."public_content"
  FOR INSERT USING (organization_id = (auth.jwt() ->> 'org_id')::text);
```

---

## Section 4: Type Generation

### Generated Types Are the Source of Truth

Never define custom TypeScript interfaces for database entities. Use the generated types:

```typescript
import type { Database } from "@/lib/supabase/database.types";

// Row types (for reads)
type Item = Database["public"]["Tables"]["items"]["Row"];

// Insert types (for creates -- optional fields have defaults)
type ItemInsert = Database["public"]["Tables"]["items"]["Insert"];

// Update types (for updates -- all fields optional)
type ItemUpdate = Database["public"]["Tables"]["items"]["Update"];
```

### Inferred Types from Query Builders

For queries with joins, infer the type from the query builder:

```typescript
import type { QueryData } from "@supabase/supabase-js";

function buildItemQuery(supabase: SupabaseClient) {
  return supabase.from("items").select(`
    *,
    category:categories!items_category_id_fkey(*)
  `);
}

// Inferred type includes the joined relation
export type ItemWithCategory = QueryData<
  ReturnType<typeof buildItemQuery>
>[number];
```

### When to Regenerate Types

- After applying any migration
- After adding/removing columns
- After changing column types or constraints
- CI should auto-generate types on every PR

---

## Section 5: Anti-Patterns

| Anti-Pattern | Why It Is Wrong | Correct Alternative |
|-------------|-----------------|---------------------|
| `supabase.from()` in pages/actions | Bypasses repository, no reuse | Use repository functions |
| `select("id, title, ...")` | Types break when schema changes | `select("*")` |
| `createClient()` inside repository | Cannot swap client for tests/webhooks | Accept client as parameter |
| Custom `interface Item {}` | Drifts from schema, manual maintenance | Use generated `Database` types |
| `.eq("organization_id", orgId)` | Duplicates RLS, error-prone | Let RLS handle org isolation |
| Manually writing migration SQL | Drift between schema and migrations | Use `db diff` from domain SQL |
| Editing generated migration files | Changes lost on next diff | Edit domain SQL, re-diff |
| Missing RLS on new tables | Data leaks across organizations | Always enable RLS + policy |
| Missing `organization_id` column | Cannot enforce multi-tenancy | Required on every table |
| Forgetting type generation after migration | TypeScript types out of sync | Run type generation after apply |

### Quick Reference

| Pattern | Correct | Wrong |
|---------|---------|-------|
| Select | `select("*")` | `select("id, name")` |
| Client | Function parameter | `createClient()` inside repo |
| Types | `Database["public"]["Tables"]["x"]["Row"]` | `interface X {}` |
| Org filter | Let RLS handle it | `.eq("organization_id", x)` |
| Migration source | Domain SQL files | Manual migration SQL |
| Generate migration | `db diff` command | Write by hand |
| After migration | Generate types | Skip type generation |
