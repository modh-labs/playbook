---
name: form-builder-rhf-isolation
description: 'Use when building a dynamic form-builder (admin-facing field editor, question builder, dynamic row list) in Next.js + React Hook Form + shadcn. Prevents the cascade-rerender trap where typing in one row rerenders all rows, and the focus-loss trap where regenerating a programmatic key on keystroke remounts the input. Triggers on: `useFieldArray`, `useWatch`, dynamic field lists, question builders, form builders, row editors.'
---

# Form-Builder RHF Isolation

## The One Question

**When the user types in one row's label, do any other rows re-render?**

If the answer is anything other than "no," the form-builder has a
cascade problem that will make the whole list feel sluggish the moment
it has more than ~10 rows. The three rules below close the gap.

## When This Skill Activates

- Building a dynamic list of editable rows (question builder, column
  editor, scheduler field builder, quiz builder, survey designer)
- Using `react-hook-form` with `useFieldArray` for the list
- Using shadcn's `<FormField>` / `<FormProvider>` / `zodResolver` stack
- Admin UIs where the editor might render 10–100+ rows
- Migrating away from imperative `useState`-based row editors

## The Three Rules

### Rule 1 — `useFieldArray` is a READ source, not a mutation primitive

RHF's docs suggest `useFieldArray.replace/update/remove/append` as the
canonical way to mutate a dynamic list. That works for simple forms,
but **regenerates the auto-generated row id on every call**. For a
form-builder with per-keystroke writes, this destroys re-render
isolation — every keystroke looks like a full array swap to React.

```ts
// ✅ CORRECT — useFieldArray for the fields array; setValue for writes
const { fields } = useFieldArray({
  control: form.control,
  name: "rows",
  keyName: "_fieldId",  // stable id, survives property edits
});

// Per-keystroke leaf-path write — does NOT touch the array's id ledger
form.setValue(`rows.${index}.label`, value, { shouldDirty: true });

// Full-array rewrite for structural changes only (reorder, duplicate)
form.setValue("rows", reordered, { shouldValidate: true, shouldDirty: true });
```

```ts
// ❌ WRONG — mechanical setValue → useFieldArray.update swap
const { fields, update } = useFieldArray({ control, name: "rows" });

onChange(e) {
  update(index, { ...fields[index], label: e.target.value });
  // Every keystroke:
  //  - regenerates the row's internal id
  //  - breaks React.memo on the row wrapper
  //  - remounts the input, drops focus
}
```

### Rule 2 — Isolate re-renders with `useWatch` by index

A memoized row that takes the full field as a prop still rerenders
every time the array changes, because `fields` is a new reference after
every form state mutation. Invert the flow: the parent iterates
*positions* (index + stable React key), and the row subscribes to its
own slice.

```tsx
// ✅ CORRECT — parent iterates positions; row subscribes by index
function FieldList() {
  const { fields } = useFieldArray({ control, name: "rows", keyName: "_fieldId" });
  const positions = useMemo(
    () => fields.map((f, i) => ({ index: i, key: f._fieldId })),
    [fields],
  );
  return positions.map((p) => <Row key={p.key} index={p.index} />);
}

const Row = memo(function Row({ index }: { index: number }) {
  const { control } = useFormContext();
  const row = useWatch({ control, name: `rows.${index}` });
  if (!row) return null;  // defensive: removed mid-render
  return <>{/* render using row.label, row.type, etc. */}</>;
});
```

```tsx
// ❌ WRONG — field as prop defeats React.memo when array reference changes
const Row = memo(function Row({ field, index }: { field: Row; index: number }) {
  // Typing in row 5's label updates rows[5] → fields[] is a new reference →
  // Row 3's `field` prop is a new reference (even though its data is identical) →
  // React.memo bails out of memoization → every row rerenders.
});
```

### Rule 3 — Regenerate programmatic keys on BLUR, not on keystroke

Form-builders often have two concepts on each row: a user-facing
`label` (editable) and a programmatic `key` (used as the JSON payload
key or DB column). The `key` must stay in sync with the label, but
regenerating it on every keystroke remounts the input and drops focus.
Do it on blur.

```tsx
// ✅ CORRECT — blur-time regen, inside shadcn FormField
<FormField
  control={control}
  name={`rows.${index}.label`}
  render={({ field }) => (
    <FormItem>
      <FormControl>
        <Input
          {...field}
          onBlur={(e) => {
            field.onBlur();
            const next = e.target.value.trim();
            if (next && next !== previousLabel) {
              const newKey = slugifyUnique(next, existingKeys);
              setValue(`rows.${index}.key`, newKey, { shouldDirty: true });
            }
          }}
        />
      </FormControl>
      <FormMessage />  {/* role="alert" — Zod errors for free */}
    </FormItem>
  )}
/>
```

```tsx
// ❌ WRONG — keystroke-time key regen
<Input
  value={label}
  onChange={(e) => {
    setValue(`rows.${index}.label`, e.target.value);
    setValue(`rows.${index}.key`, slugify(e.target.value));
    // Every keystroke replaces the row's identity → input unmounts & remounts
    // → cursor jumps to end / focus lost.
  }}
/>
```

## Supporting Lemma — shadcn FormField around hot fields

shadcn's `<FormField>` is a thin wrapper over RHF's `<Controller>` that
also internally uses `useController`. That gives you two wins for free
on the hottest keystroke field in your row:

1. **Zod errors via `<FormMessage />`** render with `role="alert"`, so
   tests can target them via `getByRole("alert", { name: /label is required/i })`
   and screen readers announce them.
2. **Per-field re-render isolation** — `useController` subscribes only
   to the field's path, so even if the row's other state updates, the
   label input's subtree doesn't rerender.

Wire at least the `label` input (the one being typed into most often)
through `<FormField>`. Other controls (switches, selects for type,
checkboxes for options) can stay as plain controlled inputs that call
`setValue` directly — they're click-once, not keystroke-heavy.

## Stability Checklist for Callbacks

For Rule 2's `React.memo` to actually save re-renders, the callback
props you pass to the row must be stable references. Common traps:

```ts
// ❌ WRONG — `fields` closure invalidates moveField every render
const moveField = useCallback(
  (from, to) => { /* reads fields */ },
  [fields, form],
);

// ✅ CORRECT — read from form state inside; dep on stable [form]
const moveField = useCallback(
  (from, to) => {
    const rows = form.getValues("rows") || [];
    // ...
  },
  [form],
);
```

If any of your `handleUpdateField` / `handleMove` / `handleRemove`
callbacks list `fields` in their deps, they're churning every edit —
rewire them to `form.getValues()` internally.

## Decision Tree

```
Are rows editable with per-keystroke writes (e.g. a label Input)?
  NO  → Simple form. useFieldArray.update is fine. Skip this skill.
  YES ↓

Can rows be reordered / duplicated / removed by the user?
  NO  → Use form.setValue with leaf paths. You don't need useFieldArray at all.
  YES ↓

Will the list render 10+ rows in real use?
  NO  → React.memo + field prop is probably fine.
  YES ↓

Apply all 3 rules:
  - useFieldArray for READ (fields + _fieldId), setValue(leaf) for WRITE
  - Row subscribes via useWatch({ name: `rows.${index}` })
  - Blur-time key regeneration for programmatic keys
```

## Audit Checklist

Use when reviewing a form-builder for this pattern.

- [ ] `useFieldArray` is called; `keyName` is set to a distinct value
      (e.g. `_fieldId`) that won't collide with the row's own fields
- [ ] Row component does NOT receive `field` / `row` as a prop; it
      subscribes via `useWatch({ name: \`...\${index}\` })`
- [ ] Parent's `.map()` iterates a positions array (index + key), not
      the full `fields`
- [ ] Row is wrapped in `React.memo` (default shallow compare — no
      custom comparator needed)
- [ ] All move / update / remove callbacks read from
      `form.getValues(...)` internally; their `useCallback` deps are
      `[form]` (stable), not `[fields, form]`
- [ ] The hot keystroke field (label, name, etc.) is wrapped in a
      shadcn `<FormField>` with `<FormMessage />`
- [ ] Programmatic keys (slug, payload keys) are regenerated on
      `onBlur`, not `onChange`
- [ ] Label change on blur is guarded by
      `trimmed && trimmed !== previousLabel` so no-op blurs don't
      trigger needless re-renders or validation churn

## Anti-Patterns

### "I'll just use useFieldArray.update for everything"

`update(index, value)` internally unregisters + re-registers the row.
For whole-field rebuilds (type change) that's acceptable. For
per-keystroke label edits, it's catastrophic — remounts the input on
every character.

### "React.memo will save us"

`React.memo` compares props shallowly. If the row takes `field` as a
prop, every parent rerender passes a new `field` reference (even when
the data is unchanged) and `React.memo` bails out. The solution is
not a deeper comparator — it's to stop passing `field` as a prop.

### "I'll regenerate the key on every change for consistency"

Cursor jumps. Focus loss. Undo history becomes unusable. Regenerate on
blur. The label and key can be out of sync for the 200ms the user is
actively typing — nothing external reads them until submit anyway.

### "I should make ALL fields go through FormField for consistency"

Only the keystroke-heavy fields benefit from `FormField`'s
`useController` subscription. Switches, dropdowns, and options editors
are click-once; putting them all through `FormField` just adds
component depth without render savings. Judgment call, not dogma.

## Further Reading

- React Hook Form docs on `useFieldArray` (v7.60+): `id` regeneration
  semantics on `update` / `replace`
- shadcn/ui `form` primitive — it's `Controller` under the hood
- Radix UI accessibility notes on `role="alert"` (emitted by
  `<FormMessage />` when a Zod error is present)
