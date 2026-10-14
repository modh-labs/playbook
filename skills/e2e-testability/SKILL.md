---
name: e2e-testability
description: >
  Write resilient Playwright e2e tests and testable React UIs. Use when writing
  e2e specs, reviewing flaky tests, building UI components, or adding
  accessibility attributes. Enforces semantic locators, accessible names,
  web-first assertions, and Page Object fixtures.
---

# E2E Testability & Accessible UI

## When This Skill Activates

- Writing or reviewing Playwright e2e test files (`*.spec.ts`)
- Building React UI components (buttons, dialogs, forms, tables)
- Debugging flaky e2e tests
- Adding `data-testid` attributes (usually a sign to reconsider)
- Discussing accessibility or ARIA roles

## The One Question

> "Can every interactive element in this UI be found by its role and accessible name?"

If yes, your tests will be resilient. If no, you'll end up with brittle CSS selectors and `data-testid` everywhere.

---

## Decision Tree: Choosing a Locator

```
Can you find the element by ARIA role + name?
  YES → getByRole('button', { name: 'Save' })         ← BEST
  NO  → Does the element have a visible label?
          YES → getByLabel('Email address')             ← GOOD
          NO  → Does it have placeholder text?
                  YES → getByPlaceholder('Search...')   ← OK
                  NO  → Does it have unique visible text?
                          YES → getByText('No results') ← OK
                          NO  → Add data-testid          ← LAST RESORT
```

### Locator Priority (Official Playwright Ranking)

| Priority | Locator | When to Use |
|----------|---------|-------------|
| 1st | `getByRole()` | Buttons, links, headings, dialogs, tables, comboboxes |
| 2nd | `getByLabel()` | Form inputs with visible `<label>` elements |
| 3rd | `getByPlaceholder()` | Inputs without visible labels |
| 4th | `getByText()` | Non-interactive elements with unique text |
| 5th | `getByTestId()` | Page landmarks, complex composites with no semantic role |

---

## Core Rules

### Rule 1: Every Interactive Element Gets an Accessible Name

This is the highest-leverage rule. An accessible name enables `getByRole` and makes the app accessible to screen readers simultaneously.

```tsx
// ❌ WRONG — icon button with no accessible name
<button onClick={onDelete}><TrashIcon /></button>
// Test forced to use: page.locator('button').nth(3) — brittle

// ✅ CORRECT — aria-label provides the accessible name
<button onClick={onDelete} aria-label="Delete yarn"><TrashIcon /></button>
// Test uses: page.getByRole('button', { name: 'Delete yarn' })

// ✅ EVEN BETTER — visible text (accessible by default)
<button onClick={onDelete}><TrashIcon /> Delete</button>
// Test uses: page.getByRole('button', { name: /Delete/ })
```

### Rule 2: Dialogs Must Have a Title

Every `<dialog>`, sheet, or modal must have `aria-labelledby` pointing to its heading. This enables `getByRole('dialog', { name: '...' })` and disambiguates when multiple dialogs exist.

```tsx
// ❌ WRONG — unnamed dialog
<Sheet>
  <SheetContent>
    <h2>Select Fabric</h2>
  </SheetContent>
</Sheet>

// ✅ CORRECT — dialog has accessible name via aria-labelledby
<Sheet>
  <SheetContent aria-labelledby="select-fabric-title">
    <h2 id="select-fabric-title">Select Fabric</h2>
  </SheetContent>
</Sheet>
// Test uses: page.getByRole('dialog', { name: 'Select Fabric' })
```

### Rule 3: Use Semantic HTML, Not `data-slot` or Custom Attributes

```tsx
// ❌ WRONG — custom attribute forces CSS selector in tests
<div data-slot="select-trigger" onClick={open}>
  {selectedValue}
</div>
// Test: page.locator("[data-slot='select-trigger']").filter({ hasText: /brand/ })

// ✅ CORRECT — semantic role, test uses getByRole
<button role="combobox" aria-label="Machine brand" onClick={open}>
  {selectedValue}
</button>
// Test: page.getByRole('combobox', { name: 'Machine brand' })
```

### Rule 4: Forms Use `<label>` with `htmlFor`

```tsx
// ❌ WRONG — input without label association
<span>Gauge</span>
<input type="number" value={gauge} />
// Test forced to use: page.locator('input').nth(5)

// ✅ CORRECT — label enables getByLabel
<label htmlFor="gauge">Gauge</label>
<input id="gauge" type="number" value={gauge} />
// Test uses: page.getByLabel('Gauge')
```

### Rule 5: `data-testid` Is for Page Landmarks Only

```tsx
// ✅ GOOD — page-level landmark for route verification
<main data-testid="fabric-create-page">

// ✅ GOOD — complex composite where no single role fits
<div data-testid="production-timeline">

// ❌ BAD — button already has role + name
<button data-testid="save-btn">Save Fabric</button>
```

---

## Eliminating Flaky Tests

### Anti-Pattern 1: Waiting for Absence Instead of Presence

The #1 cause of flaky e2e tests. Skeletons disappearing does NOT mean data loaded — it could mean the fetch errored or returned empty.

```typescript
// ❌ FLAKY — skeleton gone ≠ data loaded
await expect(dialog.locator("[data-slot='skeleton']")).toHaveCount(0, { timeout: 60000 });
const row = dialog.getByRole('row').filter({ hasText: /F-\d+/ });
await expect(row).toBeVisible({ timeout: 10000 }); // Fails — data never loaded

// ✅ STABLE — wait for the actual content you need
const row = dialog.getByRole('row').filter({ hasText: /F-\d+/ });
await expect(row).toBeVisible({ timeout: 60000 });
```

### Anti-Pattern 2: Arbitrary Sleeps

```typescript
// ❌ FLAKY — arbitrary wait
await page.waitForTimeout(2000);
const text = await page.locator('.result').textContent();

// ✅ STABLE — web-first assertion auto-retries
await expect(page.getByText('Fabric created successfully')).toBeVisible({ timeout: 60000 });
```

### Anti-Pattern 3: Manual waitForSelector + Check

```typescript
// ❌ VERBOSE — two steps when one will do
await page.waitForSelector('.loaded');
const text = await page.$eval('.result', el => el.textContent);
expect(text).toBe('Done');

// ✅ CONCISE — single web-first assertion
await expect(page.getByText('Done')).toBeVisible();
```

### Timeout Strategy

| Action | Timeout | Rationale |
|--------|---------|-----------|
| Element visible (no network) | 10s (default) | DOM rendering only |
| Data load from server | 30s | Network + query + render |
| Mutation + toast confirmation | 60s | Server action + revalidation + UI update |
| Navigation after mutation | 30s | Redirect + page load |

---

## Page Object Model

Extract repeated setup into fixtures to keep tests focused on behavior:

```typescript
// e2e/fixtures/library-actions.ts
import { type Page, expect } from '@playwright/test';

export class LibraryActions {
  constructor(private page: Page) {}

  async createYarn(opts: { spinColor: string; count: string }) {
    await this.page.goto('/library/yarn/create');
    await expect(this.page.getByRole('heading', { name: 'Create Yarn' })).toBeVisible();

    await this.page.getByRole('combobox', { name: /Spin Processes/ }).click();
    await this.page.getByRole('option', { name: 'Ring Spun' }).click();
    await this.page.keyboard.press('Escape');
    // ... remaining fields
    await this.page.getByRole('button', { name: 'Create Yarn' }).click();
    await expect(this.page.getByText('Yarn created successfully')).toBeVisible({ timeout: 60000 });
  }

  async createFabric(opts: { name: string; brand: string }) {
    await this.page.goto('/library/fabric/create');
    await this.page.getByLabel('Fabric Name').fill(opts.name);
    // ... remaining fields
    await this.page.getByRole('button', { name: 'Create' }).click();
    await expect(this.page.getByText('Fabric created successfully')).toBeVisible({ timeout: 60000 });
  }
}
```

Register as a fixture:

```typescript
// e2e/fixtures/authenticated-page.ts
import { test as base } from '@playwright/test';
import { LibraryActions } from './library-actions';

export const test = base.extend<{ library: LibraryActions }>({
  library: async ({ page }, use) => {
    await use(new LibraryActions(page));
  },
});
```

Use in tests:

```typescript
test('uploads booking and maps fabrics', async ({ page, library }) => {
  await library.createYarn({ spinColor: 'Raw', count: '30' });
  await library.createFabric({ name: 'Test', brand: 'Mayer & Cie' });
  // ... actual test logic — clean, focused on the journey being tested
});
```

---

## Component Accessibility Checklist

Use this when building or reviewing React components:

- [ ] Every `<button>` has visible text OR `aria-label`
- [ ] Every `<input>` has a `<label htmlFor>` OR `aria-label`
- [ ] Every dialog/sheet has `aria-labelledby` pointing to its title
- [ ] Comboboxes/selects have `role="combobox"` and an accessible name
- [ ] Tables use semantic `<table>`, `<th>`, `<td>` (not divs with grid CSS)
- [ ] Headings use `<h1>`–`<h6>` with meaningful text
- [ ] No icon-only buttons without `aria-label`
- [ ] No custom `data-slot` attributes used as test selectors

## Test Resilience Checklist

Use this when writing or reviewing e2e specs:

- [ ] All locators use `getByRole` or `getByLabel` (not CSS selectors)
- [ ] No `page.waitForTimeout()` calls
- [ ] Waits are for **presence of data**, not absence of loading states
- [ ] Timeouts match the action: 10s for DOM, 30s for network, 60s for mutations
- [ ] Each test creates its own data (no shared state between tests)
- [ ] Repeated setup is in Page Object fixtures, not inline
- [ ] `data-testid` only used for page landmarks

---

## Anti-Patterns Summary

| Anti-Pattern | Why It's Bad | Fix |
|-------------|-------------|-----|
| `locator("[data-slot='...']").filter(...)` | Tied to implementation details | `getByRole('combobox', { name: ... })` |
| `expect(skeleton).toHaveCount(0)` | Empty/error state also has 0 skeletons | `expect(dataRow).toBeVisible()` |
| `page.waitForTimeout(2000)` | Arbitrary — too slow or too fast | Web-first assertion with auto-retry |
| 50-line inline test setup | Duplicated across tests, obscures intent | Page Object fixture |
| `<button><Icon /></button>` | No accessible name, no semantic locator | Add `aria-label` |
| `page.locator('button').nth(3)` | Positional — breaks when UI reorders | `getByRole('button', { name: '...' })` |
