---
name: headless-form-engine
description: 'A form/wizard that needs (or will soon need) more than one presentation — all-at-once vs. one-question-per-screen, a modal vs. a full page, a mobile flow vs. desktop — should have exactly ONE headless controller owning state, validation, and submit, exposed through an explicit typed interface, with every presentation a pure consumer. Use when you''re about to fork a form''s validation/submit logic to support a second layout, when a designer asks for a "Typeform-style" version of an existing form, or when you''re reviewing a form component and find business logic duplicated across two render paths.

'
---

# Headless Form Engine

## When This Skill Activates
- A form needs a second layout: all-at-once → stepped/Typeform, modal → full page, desktop → mobile.
- A designer or PM asks "can we make this feel like Typeform?" for a form that already exists and works.
- You're about to copy a `handleSubmit`, a Zod schema, or a validity-gate function into a second component so a new layout can use it.
- Reviewing a PR that adds a second form component and it reimplements (even slightly differently) the same validation rules as the first.

## The One Question
> "If I add a third presentation next quarter, does it touch the controller — or does it only consume it?"

If the answer is "it touches the controller," the interface isn't the real boundary yet — some presentation-specific logic has leaked in, or the controller's surface is missing something a new presentation needs.

## Decision Tree
```
Form needs a second presentation?
  │
  ├─ Does business logic (validation, submit shape, gating) actually differ
  │  between presentations?
  │    YES → this isn't a presentation split, it's two different features.
  │           Stop — don't force one controller onto genuinely different rules.
  │    NO  → continue.
  │
  ├─ Extract ONE headless controller (hook/function) that owns:
  │     the form-state instance, validation schema, gate/validity logic,
  │     submit-payload construction, and per-field render dispatchers.
  │
  ├─ Name the return type EXPLICITLY (an interface), don't rely on inference.
  │     This is the real contract — new presentations depend on the interface,
  │     never on the controller's internals.
  │
  ├─ Build the new presentation as a pure consumer of that interface.
  │     Zero edits to the controller. If an edit feels necessary, the
  │     interface is incomplete — add a member, don't special-case a caller.
  │
  └─ Prove parity: render BOTH presentations with identical inputs, walk
     both to submission, assert byte-identical submit payload + exactly
     one submit call. This test is load-bearing — it's the only thing that
     turns "presentation is decoupled" from a belief into a fact.
```

## Core Rules

### 1. One controller, one form-state instance
Every presentation must render into the SAME underlying form-library instance (e.g. one `useForm()` call), not one per presentation. Two instances is two sources of truth — they will drift the moment someone edits one and forgets the other.

```tsx
// ❌ WRONG — each presentation owns its own form instance
function AllAtOnceForm() {
  const form = useForm({ resolver: zodResolver(schema) }); // instance #1
  // ...
}
function SteppedForm() {
  const form = useForm({ resolver: zodResolver(schema) }); // instance #2 — drifts
  // ...
}

// ✅ CORRECT — one controller, one instance, both presentations consume it
function useFormEngine(params): FormEngine {
  const form = useForm({ resolver: zodResolver(schema) }); // the ONLY instance
  // ...validity gate, submit builder, render dispatchers...
  return { form, canSubmit, handleSubmit, renderField, /* ... */ };
}
function AllAtOnceForm(props) {
  const engine = useFormEngine(props);
  return <form onSubmit={engine.form.handleSubmit(engine.handleSubmit)}>...</form>;
}
function SteppedForm(props) {
  const engine = useFormEngine(props); // SAME controller, different render tree
  return <form onSubmit={engine.form.handleSubmit(engine.handleSubmit)}>...</form>;
}
```

### 2. Name the interface — don't lean on inference
An inferred return type is a moving target: any presentation can accidentally depend on an internal that later gets renamed or removed, and the compiler won't stop them. An explicit interface is the actual Dependency-Inversion seam — the presentations depend on it, the controller depends on nothing.

```ts
// ❌ Inferred — the "contract" is whatever the function currently happens to return
function useFormEngine(params) {
  return { form, canSubmit, handleSubmit /* ... whatever's here today */ };
}

// ✅ Explicit — the compiler enforces this exact surface at BOTH ends
interface FormEngine {
  form: UseFormReturn<FormData>;
  canSubmit: boolean;
  handleSubmit: (values: FormData) => void;
  renderField: (field: Field) => ReactElement;
  // a new presentation needs a step model? add it here — one place, one time.
}
function useFormEngine(params): FormEngine { /* ... */ }
```

### 3. Project state into presentation-specific shape at ONE typed boundary
If the second presentation needs a different SHAPE of the same state (e.g. "steps" instead of "one screen of fields"), build a pure projector function that turns the controller's state into that shape, and validate its OUTPUT at exactly one point — not on every read, not scattered across render call sites. A discriminated union (Zod, or your type system's equivalent) makes illegal shapes unrepresentable instead of merely "usually correct."

```ts
type StepKind = "contact" | "detail" | "consent"; // no "generic" catch-all
// consent steps can never auto-advance, contact steps always carry exactly
// one field — encode these as union-variant invariants, not runtime checks
// scattered through the render tree.
function buildStepModel(orderedFields: Field[]): StepDescriptor[] {
  const steps = orderedFields.map(toStepDescriptor);
  if (process.env.NODE_ENV !== "production") stepModelSchema.parse(steps); // one boundary
  return steps;
}
```

### 4. The parity test is the deliverable, not an afterthought
Everything above is a design INTENTION until this test exists. Write it before you consider the second presentation done:

```tsx
it("both presentations submit a byte-identical payload, exactly once", async () => {
  const onCompleteA = vi.fn();
  render(<AllAtOnce onComplete={onCompleteA} {...sharedProps} />);
  fillAllFields();
  await submit();
  const payloadA = onCompleteA.mock.calls[0][0];

  const onCompleteB = vi.fn();
  render(<Stepped onComplete={onCompleteB} {...sharedProps} />);
  fillAllFields(); // same values
  await walkAllStepsAndSubmit();
  const payloadB = onCompleteB.mock.calls[0][0];

  expect(payloadB).toEqual(payloadA);
  expect(onCompleteA).toHaveBeenCalledTimes(1);
  expect(onCompleteB).toHaveBeenCalledTimes(1);
});
```
Cover the RISKY branches too, not just the happy path: the presentation that has to gate on a consent step, an optional-vs-required field, and any legacy/back-compat data shape the controller has to normalize. That's where the two presentations are most likely to silently diverge.

### 5. Mount everything the underlying form library needs to keep registered
If the second presentation only shows one field/step at a time, the OTHER fields must stay mounted (hidden, not unmounted) if the form library deregisters on unmount — otherwise the submit payload silently drops fields that live on a different screen. Hide with CSS/`inert`, not conditional rendering, unless you've verified the library preserves values across unmount.

### 6. Extract shared sub-widgets once
Anything both presentations render identically (a consent block, a summary card, an error banner) should be ONE component both import — not two components that happen to look the same today. This is especially load-bearing for anything compliance- or legal-sensitive (consent text, pricing, terms) where the two presentations silently drifting is a real liability, not just a visual inconsistency.

## Anti-Patterns

- **Two `useForm()` calls "for now, we'll dedupe later."** They won't get deduped later. The first edit to one and not the other is the bug, and it ships silently because both compile and both look right in isolation.
- **A presentation-specific `if (isStepped) { ... }` branch inside the controller.** The moment the controller knows which presentation is calling it, the DIP seam is gone — a third presentation now has to teach the controller about itself too.
- **Testing only the happy path for parity.** The happy path is the path most likely to already agree; the divergence lives in the edge cases (optional fields, gated steps, legacy data shapes) — that's specifically where fork-and-copy logic errors love to hide.
- **An inferred return type "because it's simpler."** It's simpler to write, and it's the reason the second presentation quietly depends on something that gets renamed six months later with no compiler warning.

## Audit Checklist

- [ ] Exactly one form-state instance (one `useForm()`/equivalent) shared by every presentation.
- [ ] The controller's return type is an explicit, named interface — not inferred.
- [ ] No presentation-awareness inside the controller (no `if (presentation === ...)`).
- [ ] Any state-shape projection (e.g. a step model) is validated at exactly one boundary, with illegal states made unrepresentable by the type (discriminated union), not just runtime-checked.
- [ ] A parity test exists: identical inputs → both presentations → byte-identical submit payload, exactly one submit call.
- [ ] The parity test covers the riskiest branch (a gated/consent step, an optional field, a legacy data shape) — not only the happy path.
- [ ] Off-screen fields in a stepped/paginated presentation stay mounted (not unmounted) if the form library needs them registered to submit correctly.
- [ ] Compliance-sensitive sub-widgets (consent, pricing, terms) are one shared component, not duplicated per presentation.
