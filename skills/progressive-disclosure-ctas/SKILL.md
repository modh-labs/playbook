---
name: progressive-disclosure-ctas
description: >
  Hide optional configuration fields behind subtle "+ Add X" CTAs that reveal
  inline editors when clicked, with a LivePreview strip as the always-visible
  narrator of current behavior. Use when a form has more optional fields than
  mandatory ones, or when rarely-touched settings are cluttering a form the
  admin visits often.
---

# Progressive Disclosure CTAs

## When This Skill Activates

- Designing settings panels where **most fields are optional and rarely changed**
- Admin-facing forms with 4+ configuration fields that add vertical noise
- Pages where the "what this does" story gets lost because the inputs for "how to customize" dominate the screen
- Any surface where defaults are safe/sensible and customization is opt-in

**Do NOT use when:**
- Fields are required (no point hiding something the user must fill)
- The form is one-shot and the user will see it once (e.g., signup) — disclosure cost isn't worth it
- Admins will visit specifically to configure multiple fields in one sitting (disclosure adds clicks)

## The Core Principle

> **Show what the system does today. Hide how to change it until asked.**

Most settings screens get this backward: they show every input field always-visible, forcing the user to scan inputs to figure out what the system currently does. Progressive disclosure flips it: a single preview sentence tells you the current behavior, and CTAs invite changes without forcing you to see the input until you want to.

## The One Question

> "If a user never touches this field, should they still have to scroll past it?"

If no → hide behind a CTA. If yes → it's probably not optional.

## Decision Tree

```
Is the field required?
  YES → always visible
  NO  → continue

Does the field have a sensible default or fallback behavior?
  NO  → probably belongs required; re-examine
  YES → continue

Will the admin visit this page frequently?
  NO  → always-visible is fine (one-shot config)
  YES → use progressive disclosure

Does the current configured state need to be visible at a glance?
  YES → add a LivePreview strip above the CTA
  NO  → CTA alone is enough
```

## Core Rules

### 1. LivePreview is the always-visible narrator

A compact strip (icon + sentence) that describes what the current configuration DOES, in the language the end user experiences:

```tsx
// ✅ CORRECT — describes the outcome
"Leads will see your written message below."
"Leads will be redirected to https://example.com."
"Leads will see a neutral 'no available slots' screen."

// ❌ WRONG — describes the field
"Custom message: Thanks for your interest"
"Redirect URL: https://example.com"
"Mode: stealth"
```

The preview updates as the user edits the inputs. It's the single source of truth for "what's configured right now."

### 2. CTAs use additive language

```tsx
// ✅ CORRECT — invitational, verb-first
"+ Write a custom message"
"+ Send to a URL instead"
"+ Redirect after booking"

// ❌ WRONG — configuration-speak, jargon
"Edit disqualification settings"
"Configure redirect URL"
"Set up custom message"
```

The CTA should read like a suggestion of what you CAN do, not a label describing a feature.

### 3. CTA state adapts to value presence

- **Empty** → "+ Write a custom message"
- **Set, editor closed** → "Edit message" (no `+`)
- **Set, editor open** → editor visible, with inline `[Remove]` to revert

### 4. Remove action is symmetric to Add

If a CTA reveals the editor, a `[Remove]` button inside the editor collapses it AND clears the value:

```tsx
const removeMessage = () => {
  setMessageOpen(false);       // close the editor
  commit({ customMessage: "" }); // clear the value
};
```

Don't let editors stay open with empty values — that's a stuck state.

### 5. Local disclosure state is UI-only, derived from values on mount

```tsx
// ✅ CORRECT — initial state derived from whether value exists
const [messageOpen, setMessageOpen] = useState(Boolean(message));

// Legacy links with saved copy → editor opens
// New/empty links → CTA shows, editor stays closed
```

Never persist the disclosure state. It's ephemeral UI — on every mount, derive from the current data.

## Implementation Pattern

```tsx
function OptionalConfigPanel() {
  const form = useFormContext();
  const value = useWatch({ control: form.control, name: "fieldName" }) ?? "";
  const [open, setOpen] = useState(Boolean(value));

  const remove = () => {
    setOpen(false);
    form.setValue("fieldName", "");
  };

  return (
    <div className="space-y-4">
      <LivePreview value={value} />

      {open ? (
        <div className="space-y-1.5">
          <div className="flex items-center justify-between">
            <Label>Field name</Label>
            <Button variant="ghost" size="sm" onClick={remove}>
              <X /> Remove
            </Button>
          </div>
          <Input
            value={value}
            onChange={(e) => form.setValue("fieldName", e.target.value)}
          />
        </div>
      ) : (
        <Button variant="outline" size="sm" onClick={() => setOpen(true)}>
          <Plus /> {value ? "Edit" : "Add"} field name
        </Button>
      )}
    </div>
  );
}

function LivePreview({ value }: { value: string }) {
  const sentence = value
    ? `Current value: ${value}`
    : "Using the default behavior.";
  return (
    <div className="rounded-md border bg-muted/30 px-3 py-2">
      <p className="text-xs text-muted-foreground">{sentence}</p>
    </div>
  );
}
```

## Anti-Patterns

### 1. Hiding the LivePreview behind the CTA too

```tsx
// ❌ WRONG — user has no way to see current state without clicking
{open ? <Editor /> : <Button>+ Add field</Button>}

// ✅ CORRECT — preview always shows, CTA toggles input only
<LivePreview />
{open ? <Editor /> : <Button>+ Add field</Button>}
```

Without a preview, the CTA becomes opaque: the user clicks to see what's there, realizes nothing's there, and now has to click Remove to collapse. The preview answers "what's the state?" before the user has to click anything.

### 2. Summary text INSIDE the CTA

```tsx
// ❌ WRONG — CTA trying to do two jobs
<Button>+ Add message (currently: "Thanks for your interest")</Button>

// ✅ CORRECT — preview for state, CTA for action
<LivePreview /> // "Leads will see your written message"
<Button>Edit message</Button>
```

CTAs are for actions. Preview text is for state. Don't mix.

### 3. "Save" button after the CTA is clicked

```tsx
// ❌ WRONG — the act of opening/editing/closing shouldn't be a transaction
<Button onClick={() => setOpen(true)}>+ Add message</Button>
{open && (
  <>
    <Input />
    <Button>Save</Button> {/* what does this do? */}
  </>
)}

// ✅ CORRECT — values commit as the user types, Remove reverts
<Button onClick={() => setOpen(true)}>+ Add message</Button>
{open && (
  <>
    <Input onChange={(e) => form.setValue(name, e.target.value)} />
    <Button onClick={remove}>Remove</Button>
  </>
)}
```

Commits happen on-type (via form.setValue). The user interacts with the editor; the form state follows.

### 4. Numbered badges carried over from a stepper design

If you're migrating away from a stepper/timeline, drop the numbers. `01`, `02`, `03` only make sense in a sequence. In a list of cards, they're disorienting dead weight — swap for semantic state icons (`✓`, `✗`, `!`) that earn their visual weight.

## Audit Checklist

Given a settings surface, walk through:

- [ ] How many fields are OPTIONAL vs REQUIRED? If >60% optional, candidate for disclosure.
- [ ] Is there a sentence you could write that tells the user what the current config DOES (not what the fields ARE)? That's the LivePreview.
- [ ] Are all inputs always visible? If yes, count how many the typical admin actually touches on repeat visits. That's your hiding candidates.
- [ ] When a field IS set, can you show its effect in the preview instead of making the user scroll to find the input? Yes → disclosure wins.
- [ ] After migrating, is there a clear way to revert an optional field back to default? If Remove is missing, users get stuck with customizations they can't undo without knowing the schema.
- [ ] If you came from a stepper/timeline layout, did you drop the numbered badges and replace with semantic icons?

## Reference Implementation

The Aura scheduler's Outcomes step is the canonical implementation:

- `apps/web/app/(protected)/scheduler/create/components/OutcomesConfig/OutcomesConfig.tsx` — the card layout with footer for informational states
- `apps/web/app/(protected)/scheduler/create/components/OutcomesConfig/DisqualifiedOutcomePanel.tsx` — two independent CTAs (message + redirect) sharing a single LivePreview
- `apps/web/app/(protected)/scheduler/create/components/OutcomesConfig/BookedOutcomePanel.tsx` — single CTA variant

Before the redesign: a 4-node vertical stepper with all inputs always visible, ~520px of vertical space. After: 2 cards + preview + footer, ~280px by default, expanding only when admin opts in. Same schema, same backend contract, half the visual weight for the common-case admin who never touches these settings.
