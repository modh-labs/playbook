---
name: status-rollup-chip
description: >
  When an admin table shows N raw state columns that the admin only cares about
  as a rolled-up "is this entity ready?" question, collapse them into one
  derived chip + popover nudge + row-click detail sheet. Use when a table is
  overflowing horizontally, or when admins repeatedly scan 5+ columns just to
  answer a single readiness question.
---

# Status Rollup Chip

## When This Skill Activates

- An admin table has **6+ columns** and is showing horizontal-scroll / truncated text
- The columns represent **prerequisites** for one underlying question ("is this ready?", "can this go live?", "is this configured?")
- Admins scan the page for a **single yes/no answer per row**, not to read individual field values
- You're reaching for "smaller font size" or "abbreviated headers" to fix density

**Do NOT use when:**
- The table is primarily for **data entry** (admins edit multiple fields inline)
- Each column represents **independent data** (not prerequisites of a single status)
- The table has <5 columns — plain columns are fine
- Admins actually compare values across the raw columns (sorting, filtering, exporting)

## The Core Principle

> **Admins don't scan columns — they scan for answers. Replace "here are 5 facts, you infer readiness" with "here's the answer to the question you were going to ask anyway."**

The failure mode we're fixing is the admin who reads Calendar ✓, Zoom ✓, Availability ✓, Timezone: Dublin, Bookings: ON, then thinks "ok, they're good to take bookings." You've made the admin run a derivation in their head that belongs in your code.

## The One Question

> "When an admin opens this page, are they scanning for **readiness** or for **data values**?"

- Readiness → roll up into a chip
- Data values → keep raw columns

If you can't decide, watch one admin use the page for 30 seconds. If their eye sweeps vertically down one column and they pause on the yellow/red cells, it's a readiness scan.

## The Triad

A status rollup is never just a chip. It's three components that together replace the old dense table:

```
┌─ Summary row (grid) ─────────────────────────────┐
│ Member   Roles   [Chip]   [Payout]    ⋯          │
│                    ▲                             │
│                    │ click = open popover        │
│                    ▼                             │
│              ┌─ Popover ─────────┐               │
│              │ "Why not ready"   │               │
│              │ ✗ Calendar        │               │
│              │ ✗ Availability    │               │
│              │ [Resume] ◯        │               │
│              └───────────────────┘               │
└──────────────────────────────────────────────────┘
       ▲
       │ row click (anywhere except a button) = open sheet
       ▼
┌─ Detail sheet (right) ───────────────────────────┐
│ Readiness: [Chip] [Payout]                       │
│ Setup:    Calendar   Zoom   Availability   TZ    │
│ Roles: [Setter] [Closer]                         │
│ (the raw columns we removed live here)           │
└──────────────────────────────────────────────────┘
```

1. **Chip in the grid** — derived status, 3-5 possible states max
2. **Popover on chip** — what's missing (with deep links) + inline toggle for the one common mutation
3. **Row click → detail sheet** — the raw columns for admins who still need them

Omitting any of the three breaks the pattern. Chip without popover = admins can't fix blockers. Popover without sheet = admins can't see the raw data. Sheet without chip = admins must open every row to find the yellow ones.

## Decision Tree

```
Is the table overflowing horizontally OR do admins squint at it?
  NO  → You don't need this pattern.
  YES → continue

Do ≥3 of the visible columns together answer one readiness question?
  NO  → Density is real but the pattern doesn't fit. Try column hiding,
        virtualization, or a two-column-group freeze instead.
  YES → continue

Does the question have clear states (ready/blocked/paused/etc)?
  NO  → Define them first. Usually 3 states is right, rarely more than 5.
  YES → continue

Is there ONE common mutation admins make repeatedly (pause/resume,
enable/disable)?
  YES → Put an inline toggle in the popover (preserves 1-click muscle memory)
  NO  → Popover is read-only; deep-link to the page that edits

Do admins ever need the raw column values (not just the roll-up)?
  YES → Add the row-click sheet — this is almost always yes, don't skip it
  NO  → Chip + popover alone is fine
```

## Core Rules

### 1. Status derivation is a pure function

No React. No DB. Unit-testable without a render tree.

```ts
// ✅ CORRECT
export type ReadinessStatus =
  | { kind: "ready"; missing: readonly Blocker[] }
  | { kind: "paused"; missing: readonly Blocker[] }
  | { kind: "incomplete"; missing: readonly Blocker[] };

export function deriveReadiness(entity: ReadinessInput): ReadinessStatus {
  const missing: Blocker[] = [];
  if (!entity.calendarConnected) missing.push("calendar");
  if (!entity.availabilitySet) missing.push("availability");

  if (!entity.acceptingBookings) return { kind: "paused", missing };
  if (missing.length > 0) return { kind: "incomplete", missing };
  return { kind: "ready", missing };
}
```

```tsx
// ❌ WRONG — derivation inside a cell renderer
function ReadinessCell({ row }) {
  let status;
  if (!row.calendar) status = "incomplete";
  else if (!row.accepting) status = "paused";
  // ... untestable without mounting the component
}
```

### 2. Discriminated union with a common field

Every variant carries the **same** auxiliary data (e.g., `missing`). Callers predicate on the field, not the kind.

```ts
// ✅ CORRECT — consumers predicate cleanly
if (status.missing.length > 0) showNudge(status.missing);

// ❌ WRONG — each kind has a different shape, consumers need a switch
type BadStatus =
  | { kind: "ready" }
  | { kind: "paused"; reason: string }
  | { kind: "incomplete"; blockers: string[] };
// Now everywhere you check blockers you need a switch, which is leaky.
```

### 3. Separate hard blockers from advisory items

A missing "nice-to-have" should NOT demote a Ready entity to Incomplete. But the popover should still surface it as an upgrade path.

```ts
const hardMissing = missing.filter(m => m !== "zoom"); // "zoom" is advisory
if (!entity.accepting) return { kind: "paused", missing };
if (hardMissing.length > 0) return { kind: "incomplete", missing };
return { kind: "ready", missing }; // missing may still include "zoom"
```

The popover reads the full `missing` array; the chip kind reads only the hard blockers. Both stay in sync without branching logic.

### 4. The chip IS the popover trigger

No separate info icon. No hover-only tooltip (mobile breaks, no deep links). The badge itself is a button.

```tsx
<Popover>
  <PopoverTrigger asChild>
    <button aria-label={`Readiness for ${name}`}>
      <ReadinessBadge kind={status.kind} />
    </button>
  </PopoverTrigger>
  <PopoverContent>...</PopoverContent>
</Popover>
```

### 5. Row click opens the sheet, but interactive children do not

If your data grid doesn't already filter button/anchor targets out of row click handlers (reui does; raw TanStack doesn't), add that filter once at the table level. Do NOT add `stopPropagation` on every cell — that creates a scatter of invisible contract violations.

```tsx
// At the table row element:
onClick={(e) => {
  const target = e.target as HTMLElement;
  if (target.closest('button, a, input, [role="checkbox"], [role="menuitem"]')) return;
  onRowClick?.(row);
}}
```

### 6. Use semantic elements for the chip

`<output role="status">` with `aria-label` for testability. Add a `data-*` attribute carrying the discriminant so E2E tests can assert state without matching copy.

```tsx
<output
  aria-label={`Readiness: ${label}`}
  data-readiness={kind}
  className={cn("inline-flex ...", classes)}
>
  {label}
</output>
```

### 7. Consistent visual vocabulary across rollup chips

If your page has multiple rollup chips (e.g., "Call-ready" and "Payout"), they should share the badge primitive: same shape, same color semantics (green=ready, yellow=blocker, gray=inactive), same typographic rhythm. A reader glancing at the row should immediately see "2 green = fully live; yellow + green = one fix needed."

## Implementation Pattern

```
lib/
  derive-{status}.ts          # Pure util + unit tests
  __tests__/
    derive-{status}.test.ts

components/
  {entity}-rollup-badge.tsx        # Presentational, 3-state map
  {entity}-rollup-badge.stories.tsx
  {entity}-rollup-popover.tsx      # Wraps badge in Popover + inline toggle
  {entity}-detail-sheet.tsx        # shadcn Sheet, reads all raw fields
```

File budget: each piece fits comfortably under 150 lines. The popover grows first if you add more missing items — extract a `<MissingItemsList>` when it does.

## Anti-Patterns

### "Make the font smaller"

Compressing density doesn't solve the underlying problem (admin runs derivation in their head). It just makes the page harder to read. Density is a symptom; you want to fix the cause.

### "Move the columns to a sheet"

Sheet without the chip summary is worse, not better. Admins now click every row to find out who needs attention. The chip in the grid IS the reason this pattern works.

### "Hover-only tooltip instead of popover"

Tooltips are read-only. Popovers can contain buttons, toggles, and links. The pattern's superpower is the inline toggle — don't give it up by picking the wrong primitive. Also: tooltips are broken on mobile.

### "Put the pause toggle in the ... menu"

You just replaced a 1-click interaction with a 3-click interaction. The popover is explicitly designed to preserve fast mutations for the one common operation.

### "Add a column of dots (green/yellow/red)"

You've reinvented the chip with less information. A dot can't carry a label, can't contain a popover trigger affordance, and can't be tested against copy. Just use a chip.

### "Compute status in SQL"

Status derivation is business logic. It belongs in TypeScript where it's unit-testable, searchable, and editable without a migration. SQL computes the inputs; TS computes the answer.

## Audit Checklist

For each rollup chip:

- [ ] Derivation function is pure (no React, no DB, no I/O)
- [ ] Unit tests cover every kind variant + every missing-item combination
- [ ] Discriminated union has a common field (not variant-specific shapes)
- [ ] Hard blockers and advisory items are distinguishable in the derivation
- [ ] Badge uses `<output role="status">` with `aria-label` + `data-*` discriminant
- [ ] Popover trigger IS the badge (no separate info affordance)
- [ ] Popover contains deep-links to fix each missing item
- [ ] Popover contains the one common mutation as an inline toggle (if applicable)
- [ ] Row click opens the detail sheet
- [ ] Row click is NOT fired when the originating target is a button / form control
- [ ] Detail sheet contains every raw field that was removed from the grid
- [ ] All rollup chips on the page share the same primitive (consistent visual)
- [ ] Colocated story file exists for the badge

## Related Patterns

- `progressive-disclosure-ctas` — sibling pattern for hiding optional form fields behind "+ Add X" CTAs. Same underlying principle ("show what the system does, hide how to change it until asked"), different UI shape (form vs table).
- `shadcn-components` — the primitives this pattern composes (Badge, Popover, Sheet, Tabs).
- `e2e-testability` — the `data-*` discriminant and `role="status"` shape come from this skill's contract.
- `react-architecture` — the "pure function + presentational leaf + orchestrator" decomposition you'll use to stay under the file budget.
