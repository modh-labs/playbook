---
name: internal-tools-design
description: Use when building or modifying admin dashboards, internal tools, ops panels, or back-office UIs. Enforces scannability, data density, tactile feedback, and dark-mode-safe patterns calibrated for daily-use operational tools.
tier: universal
icon: layout-dashboard
title: "Internal Tools Design"
seo_title: "Internal Tools Design — Modh Engineering Skill"
seo_description: "Use when building or modifying admin dashboards, internal tools, ops panels, or back-office UIs. Enforces scannability, data density, and dark-mode-safe patterns."
keywords: ["internal tools", "admin dashboard", "ops panel", "data density", "dark mode"]
difficulty: intermediate
related_chapters: []
related_tools: []
---

# Internal Tools Design

Calibrated for ops dashboards, admin panels, and back-office tools where the user checks this page 20 times a day. Every decision optimizes for **scannability, speed, and reliability** — not visual impact.

## Baseline Configuration

```
DESIGN_VARIANCE: 3   (predictable, symmetrical grids)
MOTION_INTENSITY: 2  (CSS transitions only, no libraries)
VISUAL_DENSITY: 6    (dense but readable, monospace numbers)
```

These values are non-negotiable for internal tools. If the user asks for a marketing page or public-facing UI, use a different design skill instead.

---

## The 10 Rules

### 1. Data Hierarchy Over Decoration

Every pixel serves the question: "Can the ops person find what they need in <2 seconds?"

- **Numbers are king.** Large, bold, `font-mono`. The first thing the eye hits.
- **Labels are secondary.** `text-sm font-medium text-muted-foreground` above the number.
- **Trends are tertiary.** Small percentage or sparkline beside the number, not a separate chart.
- **No decorative elements.** No gradients, no illustrations, no hero sections.

```
Good: 250 users (large mono) -> 35% coverage (small muted below)
Bad:  Users card with gradient background and decorative user icon taking 40% of the card
```

### 2. Consistent Page Anatomy

Every internal tool page follows this exact structure:

```tsx
<div className="space-y-8 p-6">
  {/* 1. Header: title + description + action buttons */}
  <div className="flex items-center justify-between">
    <div className="space-y-1">
      <h1 className="text-3xl font-bold tracking-tight">Page Title</h1>
      <p className="text-muted-foreground">One-line description</p>
    </div>
    <div className="flex items-center gap-2">
      {/* Export, Refresh, Create buttons */}
    </div>
  </div>

  {/* 2. Stats cards (if applicable) */}
  <div className="grid gap-4 sm:grid-cols-3">
    {/* MetricCard components */}
  </div>

  {/* 3. Main content (table, list, or detail view) */}
  <Card className="border-border/50 shadow-sm">
    {/* Search/filter bar -> data table */}
  </Card>
</div>
```

Deviate from this structure only with explicit justification.

### 3. Typography Rules

| Element | Classes | Never |
|---------|---------|-------|
| Page title | `text-3xl font-bold tracking-tight` | `font-semibold`, `text-2xl` |
| Card title | `text-lg font-semibold` | `text-xl`, `font-bold` |
| Body text | `text-sm` | `text-base` in dense tables |
| Muted/secondary | `text-muted-foreground` | Hardcoded grays |
| Numbers, IDs, dates, emails, phones | `font-mono` | Sans-serif for data |
| Table headers | `text-sm font-medium` | `font-bold` on headers |

### 4. Color System (Dark Mode First)

**Never use hardcoded colors.** Always pair light + dark:

| Use Case | Pattern |
|----------|---------|
| Success/healthy | `text-emerald-600 dark:text-emerald-400` + `bg-emerald-50 dark:bg-emerald-950/20` |
| Error/critical | `text-red-600 dark:text-red-400` + `bg-red-50 dark:bg-red-950/20` |
| Warning | `text-amber-600 dark:text-amber-400` + `bg-amber-50 dark:bg-amber-950/20` |
| Info | `text-blue-600 dark:text-blue-400` + `bg-blue-50 dark:bg-blue-950/20` |
| Neutral surface | `bg-muted` |
| Neutral text | `text-muted-foreground` |
| Borders | `border-border` or `border-border/50` |

**Banned:** `bg-gray-*`, `bg-slate-*`, `text-gray-*` without dark variant. Use semantic tokens.

### 5. Card & Surface Rules

- Cards use `border-border/50 shadow-sm` — never bare `border` or heavy `shadow-md`
- Stats cards: icon in `h-12 w-12 rounded-full bg-{color}-100 dark:bg-{color}-950/30` circle
- Table wrappers: `rounded-lg border border-border/50 overflow-hidden`
- Table headers: `bg-muted/50 hover:bg-muted/50`
- Table rows: `py-3` cell padding, `hover:bg-muted/30 transition-colors`

### 6. Interactive Feedback (CSS Only)

No Framer Motion. No animation libraries. Pure CSS:

```css
/* Buttons: tactile press */
.button { @apply active:scale-[0.98] transition-all; }

/* Table rows: scannable highlight */
.row { @apply hover:bg-muted/30 transition-colors; }

/* Sortable headers: cursor + hover */
.sort-header { @apply cursor-pointer hover:bg-muted/80 transition-colors; }

/* Refresh spinner: only during loading */
.refresh-icon { @apply animate-spin; } /* only when isLoading */

/* Copy button: appear on row hover */
.copy { @apply opacity-0 group-hover/row:opacity-100 transition-opacity; }
```

**Banned for internal tools:** Framer Motion, GSAP, staggered reveals, magnetic buttons, parallax, spring physics. These slow down daily-use interfaces.

### 7. Empty, Loading, Error States

Every page needs all three. No exceptions.

**Loading:** Skeleton matching the exact page layout. Never a centered spinner.

```tsx
// Skeleton rows should match table column widths
<Skeleton className="h-4 w-28" />  // name column
<Skeleton className="h-4 w-40" />  // email column (wider)
<Skeleton className="h-5 w-16 rounded-full" />  // badge column
```

**Empty:** Centered icon + title + subtitle. Never just text.

```tsx
<div className="flex flex-col items-center justify-center py-16">
  <div className="flex h-16 w-16 items-center justify-center rounded-full bg-muted mb-4">
    <Icon className="h-8 w-8 text-muted-foreground" />
  </div>
  <p className="text-muted-foreground font-medium">No items found</p>
  <p className="text-sm text-muted-foreground mt-1">Helpful next step</p>
</div>
```

**Error:** Capture to error tracking + user-friendly boundary with retry button.

```tsx
<div className="mx-auto h-12 w-12 rounded-full bg-destructive/10 flex items-center justify-center mb-4">
  <AlertCircle className="h-6 w-6 text-destructive" />
</div>
```

### 8. Table Design

Tables are the primary data display for internal tools.

- **Sortable columns:** Click header to sort. Show `ArrowUpDown` (inactive) or `ArrowUp`/`ArrowDown` (active).
- **Search bar:** Always `pl-10` with `Search` icon positioned absolutely at `left-3 top-1/2 -translate-y-1/2`
- **Filter dropdowns:** `w-[170px]` Select beside search bar
- **Row actions:** Appear on hover or in a `DropdownMenu` on the last column
- **Grouped cells:** Avatar + name + email in one cell for identity data (not 3 separate columns)
- **Relative timestamps:** `font-mono text-muted-foreground` with absolute time in a `Tooltip`
- **Status badges:** Use Badge component with semantic colors from Rule 4
- **Pagination info:** Show "X of Y items" in CardDescription

### 9. Component Rules

- **Always** use your project's component library (e.g., shadcn/ui). Never raw HTML.
- **Always** `cursor-pointer` on clickable elements (buttons, links, sortable headers, selects)
- **Always** use a utility for conditional classes (e.g., `cn()`, `clsx()`)
- **Never** barrel imports
- **Never** inline `style={}` — utility classes only
- **Icons:** Use a consistent icon library at default size. `h-4 w-4` in buttons/badges, `h-6 w-6` in stat card circles

### 10. Responsive Behavior

Internal tools are primarily desktop. But don't break on tablet.

- Stats grids: `grid gap-4 sm:grid-cols-2 lg:grid-cols-3` (or `lg:grid-cols-4`)
- Search bars: `min-w-[280px]` with `flex-1`
- Tables: horizontal scroll on mobile (wrap in `overflow-x-auto`)
- Sidebar: collapsible with persisted state in localStorage

---

## Anti-Patterns (Forbidden in Internal Tools)

| Pattern | Why It's Banned | Use Instead |
|---------|----------------|-------------|
| Framer Motion | Adds bundle size + complexity for zero ops value | CSS `transition-colors` |
| Staggered reveals | Slows down scanning — ops needs instant render | Immediate mount |
| Glassmorphism/blur | Reduces readability, expensive GPU paint | Solid `bg-card` surfaces |
| Gradient text | Illegible on data-dense pages | Solid `text-foreground` |
| Hero sections | No one browses an admin dashboard | Jump straight to data |
| Magnetic buttons | Ops clicks 100 buttons/day, magnets slow them down | Standard click targets |
| Oversized H1 | Admin pages aren't landing pages | `text-3xl` max |
| Decorative illustrations | Wastes space where data should be | Use the space for metrics |
| Skeleton shimmer animation | Distracting on 20+ skeleton elements | Static `bg-muted` skeleton |
| Center-aligned layouts | Wastes horizontal space on wide monitors | Left-aligned content |

---

## Quick Audit Checklist

Run through this for every internal tool page before shipping:

- [ ] Page follows the 4-section anatomy (header -> stats -> filters -> data)
- [ ] All numbers use `font-mono`
- [ ] All colors have `dark:` variants
- [ ] All buttons have `cursor-pointer`
- [ ] Loading skeleton matches page layout
- [ ] Empty state has icon + title + subtitle
- [ ] Error boundary captures to error tracking service
- [ ] Tables have sortable headers with sort icons
- [ ] Search input has `pl-10` with Search icon
- [ ] Interactive elements have `transition-colors` or `transition-all`
- [ ] No hardcoded gray/slate/green/red without dark variant
- [ ] No Framer Motion or animation libraries imported
- [ ] No raw HTML elements (`<button>`, `<input>`, `<select>`)
- [ ] Timestamps show relative with absolute in tooltip
