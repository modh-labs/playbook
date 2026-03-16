---
name: shadcn-components
description: Build UI components following shadcn/ui patterns. Use when creating components, styling, theming, building detail views, sheets, dialogs, or forms. Enforces shadcn components, CSS variables, variant usage, detail view architecture, and component colocation.
allowed-tools: Read, Grep, Glob, Edit, Write
tier: react
icon: square
title: "shadcn/ui Component Patterns"
seo_title: "shadcn/ui Component Patterns — Modh Engineering Skill"
seo_description: "Build UI components following shadcn/ui patterns. Enforces shadcn components, CSS variables, variant usage, detail view architecture, and component colocation."
keywords: ["shadcn", "ui components", "tailwind", "theming", "design system"]
difficulty: intermediate
related_chapters: []
related_tools: []
---

# shadcn Components Skill

## When This Skill Activates

This skill automatically activates when you:
- Create or modify React components
- Add styling or theming
- Build entity detail views (sheets, drawers, pages)
- Work with forms, tables, or data display
- Discuss UI patterns, component architecture, or design tokens

---

## Section 1: Core Rules

### Never use raw HTML elements

Always use shadcn/ui components from `@/components/ui/`:

```typescript
// Wrong -- raw HTML
<button className="px-3 py-2 bg-blue-500 text-white rounded">Click</button>
<input type="text" className="border rounded px-3 py-2" />
<textarea className="w-full border rounded" />

// Correct -- shadcn/ui
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Textarea } from "@/components/ui/textarea";

<Button>Click</Button>
<Input />
<Textarea />
```

### Use CSS variables, never hardcoded colors

```typescript
// Wrong -- hardcoded Tailwind colors
<div className="bg-blue-500 text-white">
<div className="bg-gray-100 text-gray-900">
<div className="bg-red-500">Error</div>

// Correct -- semantic CSS variable tokens
<div className="bg-primary text-primary-foreground">
<div className="bg-muted text-muted-foreground">
<div className="bg-destructive text-destructive-foreground">Error</div>
```

**Available semantic tokens:**

| Token | Usage |
|-------|-------|
| `background` / `foreground` | Page background and text |
| `card` / `card-foreground` | Card surfaces |
| `primary` / `primary-foreground` | Primary actions, links |
| `secondary` / `secondary-foreground` | Secondary actions |
| `muted` / `muted-foreground` | Subdued backgrounds, helper text |
| `accent` / `accent-foreground` | Hover states, highlights |
| `destructive` / `destructive-foreground` | Errors, delete actions |
| `border` | Borders and dividers |
| `input` | Form input borders |
| `ring` | Focus rings |

### Never override shadcn component defaults

Use variant props for visual changes. Only add spacing and layout classes.

```typescript
// Wrong -- overriding shadcn styling
<Button className="bg-blue-500 hover:bg-blue-600 rounded-lg px-6">

// Correct -- use variants, add only spacing/layout
<Button variant="default">Primary</Button>
<Button variant="destructive">Delete</Button>
<Button variant="outline">Cancel</Button>
<Button variant="ghost">Menu Item</Button>
<Button className="w-full mt-4">Full Width</Button>
```

**Allowed Tailwind on shadcn components:**
- Spacing: `m-*`, `p-*`, `gap-*`, `space-*`
- Layout: `flex`, `grid`, `w-*`, `h-*`
- Display: `hidden`, `block`, `inline-flex`

**Never add:**
- Colors: `bg-*`, `text-*`, `border-*` (use variants)
- Borders: `rounded-*`, `border-*` (use defaults)
- Shadows: `shadow-*` (use defaults)

---

## Section 2: Variant Usage

### Button

```typescript
<Button variant="default">Primary Action</Button>
<Button variant="secondary">Secondary</Button>
<Button variant="destructive">Delete</Button>
<Button variant="outline">Cancel</Button>
<Button variant="ghost">Subtle Action</Button>
<Button variant="link">Link Style</Button>
<Button size="sm">Small</Button>
<Button size="lg">Large</Button>
<Button size="icon"><Icon /></Button>
```

### Input & Textarea

```typescript
<Input placeholder="Enter value..." />
<Input type="email" disabled />
<Textarea placeholder="Write a description..." />
```

### Select

```typescript
import {
  Select, SelectContent, SelectItem,
  SelectTrigger, SelectValue,
} from "@/components/ui/select";

<Select>
  <SelectTrigger>
    <SelectValue placeholder="Choose..." />
  </SelectTrigger>
  <SelectContent>
    <SelectItem value="active">Active</SelectItem>
    <SelectItem value="archived">Archived</SelectItem>
  </SelectContent>
</Select>
```

### Badge

```typescript
import { Badge } from "@/components/ui/badge";

<Badge>Default</Badge>
<Badge variant="secondary">Info</Badge>
<Badge variant="destructive">Error</Badge>
<Badge variant="outline">Neutral</Badge>
```

---

## Section 3: Sheet / Dialog Toggle Pattern

Always use a single `onToggleExpand` callback. Never separate open/close handlers.

```typescript
// Wrong -- separate handlers
interface Props {
  isExpanded: boolean;
  onOpen: () => void;
  onClose: () => void;
}

// Correct -- single toggle
interface Props {
  item: Item;
  isExpanded: boolean;
  onToggleExpand: () => void;
}

export function ItemCard({ item, isExpanded, onToggleExpand }: Props) {
  return (
    <>
      <div onClick={onToggleExpand}>{/* row content */}</div>
      <Sheet open={isExpanded} onOpenChange={onToggleExpand}>
        <SheetContent>
          <SheetHeader>
            <SheetTitle>{item.name}</SheetTitle>
          </SheetHeader>
          {/* detail content */}
        </SheetContent>
      </Sheet>
    </>
  );
}
```

**Parent manages expanded state:**

```typescript
export function ItemsList({ items }: { items: Item[] }) {
  const [expandedId, setExpandedId] = useState<string | null>(null);

  return (
    <div>
      {items.map((item) => (
        <ItemCard
          key={item.id}
          item={item}
          isExpanded={expandedId === item.id}
          onToggleExpand={() =>
            setExpandedId(expandedId === item.id ? null : item.id)
          }
        />
      ))}
    </div>
  );
}
```

Why: Works with URL sync, browser back/forward, and all close methods (Esc, overlay click, X button).

---

## Section 4: Detail View Architecture

All entity detail views follow a three-layer pattern: Container, Detail, Sections.

### Architecture

```
Container (Sheet / Drawer / Page)
  - State management (open/close)
  - Data mutations
  - Permission checks

Detail (Main content layout)
  - Section composition
  - Conditional rendering
  - Flat layout assembly

Sections (Display components)
  - Single responsibility
  - Read-only display
  - Reusable across entities
```

### File Structure

```
components/
  ItemDetailSheet.tsx       # Container
  ItemDetail.tsx            # Main content
  sections/
    InfoSection.tsx         # Domain-specific
    NotesSection.tsx        # Reusable
    ActionsSection.tsx      # CTA buttons
  ItemDetailSkeleton.tsx    # Loading state
```

### Container Pattern

```typescript
export function ItemDetailSheet({
  open,
  onOpenChange,
  itemId,
}: ItemDetailSheetProps) {
  return (
    <Sheet open={open} onOpenChange={onOpenChange}>
      <SheetContent className="w-full sm:max-w-xl">
        <ItemDetail itemId={itemId} />
      </SheetContent>
    </Sheet>
  );
}
```

### Detail Pattern

```typescript
export function ItemDetail({ itemId }: { itemId: string }) {
  const item = await fetchItem(itemId);
  return (
    <div className="space-y-0 divide-y">
      <InfoSection item={item} />
      <NotesSection notes={item.notes} />
      <ActionsSection item={item} />
    </div>
  );
}
```

### Section Pattern

```typescript
export function InfoSection({ item }: { item: Item }) {
  return (
    <SectionLayout title="DETAILS">
      <InfoGrid cols={2}>
        <InfoItem label="Name">{item.name}</InfoItem>
        <InfoItem label="Status">{item.status}</InfoItem>
      </InfoGrid>
    </SectionLayout>
  );
}
```

### Styling Standards

**Section headers:** uppercase, tracking-wide

```typescript
<h3 className="text-sm font-semibold uppercase tracking-wide text-muted-foreground">
  DETAILS
</h3>
```

**Layout flow:** flat sections with dividers, no rounded corners

```typescript
<div className="space-y-0 divide-y">
  {/* Sections render as flat, divided blocks */}
</div>
```

**Label-value pairs:**

Vertical layout (InfoGrid):
```typescript
<InfoGrid cols={2}>
  <InfoItem label="Name">{item.name}</InfoItem>
  <InfoItem label="Email">{item.email}</InfoItem>
</InfoGrid>
```

Horizontal layout (RowItem):
```typescript
<RowItem label="Created">{formatDate(item.createdAt)}</RowItem>
```

**Technical IDs:** monospace

```typescript
<span className="font-mono text-xs">{item.id}</span>
```

### Shared Components

| Component | Purpose |
|-----------|---------|
| `SectionLayout` | Base section wrapper with title |
| `InfoGrid` + `InfoItem` | Vertical label-value grid layout |
| `RowItem` | Horizontal 50/50 label-value row |
| `NotesSection` | Generic notes display (any entity) |
| `ActivityTimeline` | Chronological event timeline |

### Detail View Checklist

- [ ] Three-layer pattern (Container -> Detail -> Sections)
- [ ] Each section uses `SectionLayout`
- [ ] `space-y-0 divide-y` for flat section flow
- [ ] Uppercase section headers with `tracking-wide`
- [ ] `InfoGrid/InfoItem` or `RowItem` for label-value pairs
- [ ] Fixed CTA section at bottom (not inline in sections)
- [ ] Loading skeleton matches final layout
- [ ] Sections return `null` when empty (not blank space)

Full detail view pattern: `references/detail-view-pattern.md`

---

## Section 5: Component Location Rules

**Colocate components with their route.** Share only when used by 3+ routes.

```
app/(protected)/orders/
  components/
    OrderCard.tsx         # Route-specific
    OrderForm.tsx
  page.tsx

components/
  ui/
    button.tsx            # shadcn base components
    sheet.tsx
  shared/
    DateBadge.tsx         # Used by 3+ routes
    StatusBadge.tsx
```

| Scenario | Location |
|----------|----------|
| Used by 1 route | `app/route/components/` |
| Used by 2 routes | Keep in the more "owning" route, import from there |
| Used by 3+ routes | Move to shared components directory |
| shadcn base component | `components/ui/` |

---

## Section 6: "use client" Decision

Server Components are the default. Only add `"use client"` when the component needs:

- `useState`, `useEffect`, `useRef`, `useReducer`
- Event handlers (`onClick`, `onChange`, `onSubmit`)
- Browser APIs (`window`, `document`, `localStorage`)
- Third-party client-only libraries

```typescript
// No directive needed -- Server Component (default)
export function StaticCard({ title }: { title: string }) {
  return <Card><CardTitle>{title}</CardTitle></Card>;
}

// Needs "use client" -- has interactivity
"use client";
export function InteractiveCard({ title }: { title: string }) {
  const [isOpen, setIsOpen] = useState(false);
  return (
    <Card onClick={() => setIsOpen(!isOpen)}>
      {/* ... */}
    </Card>
  );
}
```

---

## Section 7: Anti-Patterns

| Anti-Pattern | Why It Is Wrong | Correct Alternative |
|-------------|-----------------|---------------------|
| Raw `<button>`, `<input>`, `<select>` | No theming, inconsistent look | shadcn `<Button>`, `<Input>`, `<Select>` |
| `bg-blue-500`, `text-gray-600` | Breaks in dark mode, no theming | `bg-primary`, `text-muted-foreground` |
| `className="bg-red-500"` on Button | Overrides shadcn defaults | `variant="destructive"` |
| `rounded-lg border p-4` on sections | Wrong detail view style | `space-y-0 divide-y` flat sections |
| Separate `onOpen` / `onClose` | Breaks URL sync, multiple sources of truth | Single `onToggleExpand` callback |
| Inline actions in detail sections | Sections should be read-only display | Actions in dedicated CTA section |
| `space-y-4` in detail views | Wrong spacing for detail sections | `space-y-0 divide-y` |
| Lowercase section headers | Inconsistent with design pattern | Uppercase + `tracking-wide` |
| `"use client"` on every component | Disables streaming, increases bundle | Server Component by default |
| Cross-route component imports | Tight coupling between routes | Share at 3+ routes, else colocate |
| Generic spinner for content | No layout info, causes CLS | Layout-matched skeleton |

### Quick Reference

| Element | Use This | Not This |
|---------|----------|----------|
| Button | `<Button variant="...">` | `<button className="...">` |
| Input | `<Input />` | `<input className="..." />` |
| Colors | `bg-primary`, `text-muted` | `bg-blue-500`, `text-gray-600` |
| Sheet toggle | `onOpenChange={toggle}` | `open ? onOpen() : onClose()` |
| Client directive | Only when interactive | On every component |
| Detail layout | `space-y-0 divide-y` | `space-y-4` or `rounded-lg` |
| Section header | `UPPERCASE tracking-wide` | `Title Case font-bold` |

Full component template: `references/component-template.tsx`
