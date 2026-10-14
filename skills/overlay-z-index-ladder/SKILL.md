---
name: overlay-z-index-ladder
description: 'Maintain one documented z-index ladder for overlay tiers (base → sheet → dialog → floating content → toast → blocking alert). Every floating primitive (dropdown, menu, popover, select, tooltip, hover-card) must sit in the right tier, and an actionable overlay must outrank a passive one. Use when two overlays can be open at once, when a menu/submenu renders under something, when a dropdown inside a dialog appears beneath it, when adding a portal/popover component, or auditing a design system''s layering.

'
---

# Overlay Z-Index Ladder

## When This Skill Activates
- Two overlays can be open at once (a hover-card + a menu, a tooltip + a popover).
- A menu, submenu, or dropdown renders UNDER another floating element or a dialog.
- Adding a new portal/popover component to a design system.
- Auditing a component library's layering or chasing a "why is this behind that?" bug.

## The One Question
> "When these two overlays are open at once, which is ACTIONABLE and which is PASSIVE — and does the ladder guarantee the actionable one paints on top?"

## Why It Breaks
Overlays portaled to `document.body` all become siblings in the SAME stacking
context. When siblings overlap, the higher `z-index` wins **regardless of DOM
order**. So a passive hover-card or tooltip in a higher tier paints over the
interactive menu the user is trying to click. The usual root cause: one floating
primitive was never promoted into the tier all its siblings share — so it loses
every overlap and also renders under modals.

## The Ladder
Document it once, and make every floating primitive cite the same tier inline:

```
base content      z-0 .. z-40
sheet / drawer     z-50
dialog / modal     z-[60]
floating content   z-[70]   ← dropdown, menu, popover, select, tooltip, hover-card
toast / command    z-[100]
blocking alert     z-[200]+
```

```tsx
// ✅ Every floating primitive shares the floating tier, with the reason inline:
// z-[70] keeps menus above Dialog (z-[60]) and Sheet (z-50), matching
// Popover / Select / Tooltip — so a menu opened inside a dialog still works.
<DropdownMenuContent className={cn("z-[70] …", className)} />

// ❌ The odd-one-out: a single primitive left a tier below its siblings —
// it hides under dialogs AND loses to z-[70] popovers/hover-cards.
<DropdownMenuContent className="z-50 …" />
```

## Core Rules

### 1. All floating primitives share one tier
A `<select>` opened inside a dialog must render above the dialog. So dropdowns,
menus, popovers, selects, tooltips, and hover-cards all sit in the SAME floating
tier — above modals. If one is a tier lower, it both hides under dialogs and
loses to its sibling popovers.

### 2. Actionable beats passive
When an interactive menu and a passive preview (hover-card, tooltip) can be open
together, the menu must win — the user is driving it. Achieve this by either
(a) making the actionable tier strictly higher than the passive one, or
(b) dismissing the passive overlay while the menu is open. Don't rely on DOM or
open order to decide it for you.

### 3. Watch for trapped stacking contexts
A `transform`, `filter`, `perspective`, `will-change`, or `overflow` on an
ancestor creates a NEW stacking context that can trap a portaled child. If an
overlay won't escape its parent despite a high z-index, an ancestor is the cause
— portal to `body` and confirm no ancestor transform is in play.

## Anti-Patterns
- **Ad-hoc z numbers.** `z-50` here, `z-[999]` there, `z-[9999]` to "win" — a z-index arms race with no contract. Use named tier tokens.
- **Fixing the symptom card.** Bumping one component's z-index to dodge a single overlap, leaving the primitive's tier wrong everywhere else.
- **Passive over active.** A tooltip or hover preview allowed to cover an actionable menu — informational UI must never block interactive UI.

## Audit Checklist
- [ ] Every overlay's z-index is a documented tier token, not an ad-hoc number.
- [ ] All floating primitives share one tier (none stuck a tier below its siblings).
- [ ] Actionable > passive whenever two overlays can co-exist.
- [ ] A dropdown opened inside a dialog renders above the dialog.
- [ ] No ancestor `transform`/`overflow` traps a portaled overlay in a child stacking context.
