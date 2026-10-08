---
name: type-the-parse-input
description: >
  A runtime validator takes `unknown`, so an object your own typed code builds and then hands to
  `schema.parse()` is never typechecked against that schema; a field widened at its producer passes
  typecheck and fails in production. Type the hand-off as `z.input<typeof schema>`. Use when typed
  code builds a payload that a repository, service or job re-validates with Zod (or Valibot, Yup,
  ArkType); when a widened type (`string | null`, a new enum member) reaches a schema; or when
  production throws a validation error on data no user typed.
---

# Type the Parse Input

## When This Skill Activates

- A builder or mapper produces an object, and the next line is `SomeSchema.parse(thatObject)`
- A repository or service re-validates params that only ever come from your own typed code
- You widen a field's type at its producer (`string` to `string | null`, a new union member, an optional field)
- Production raises a ZodError on internal data, and typecheck, lint and unit tests were green

## The One Question

> **If the producer's type changed tomorrow, would typecheck fail before the parse does?**

If not, the schema is the only check that object ever gets, and it runs on a customer's request.

## How It Fails

A booking service builds the params for its repository and validates them there:

```ts
function buildRecordParams(input: FinalizeInput) {        // return type inferred
  return { ...input.booking, visitorId: input.visitorId }; // visitorId: string | null
}

const params = RecordParamsSchema.parse(buildRecordParams(input)); // parse(data: unknown)
```

`RecordParamsSchema` declares `visitorId: z.string().optional()`. A privacy change made the visitor
ID `null` for anyone who had not consented, which was correct where it was made. Typecheck stayed
green because `parse` accepts `unknown`: the object's type is never compared with the schema. The
first comparison happened at runtime, after the calendar event was created, and every booking from
a guest without the cookie failed with `Invalid input: expected string, received null`.

The schema did its job. The type system was never asked.

## Decision Tree

```
Is the value passed to parse() built by your own typed code?
├── NO  → it is untrusted input: parse from unknown at the boundary (that is the validator's job)
└── YES → Does the parse still earn its place (normalizing, defaults, a second trust boundary)?
     ├── NO  → delete the parse; pass the typed value (Rule 4)
     └── YES → Is the hand-off typed as z.input<typeof Schema>?
          ├── YES → done; drift now fails typecheck
          └── NO  → add it (Rule 1), then fix every error it raises one by one (Rule 3)
```

## Core Rules

### 1. Type the builder as the schema's input

```ts
// WRONG: inferred return type, checked only at runtime
export function buildRecordParams(input: FinalizeInput) { ... }

// CORRECT: the producer is held to the schema's contract at compile time
export type RecordParams = z.input<typeof RecordParamsSchema>;
export function buildRecordParams(input: FinalizeInput): RecordParams { ... }
```

When there is no named builder, check the literal at the call site:

```ts
const params = RecordParamsSchema.parse({ ...fields } satisfies z.input<typeof RecordParamsSchema>);
```

### 2. Use `z.input`, not `z.infer`

`z.infer` is the parsed output: defaults filled, transforms applied. The builder feeds the parse, so
it must match what the schema accepts. A `.default()` field is optional in `z.input` and required in
`z.infer`; typing the builder with `z.infer` demands values the schema would have supplied.

### 3. Decide each error the annotation raises

Adding the type usually surfaces more than the bug you came for. Each error is a contract mismatch
that already exists in production; decide it on purpose:

- **Absence spelled two ways.** `.optional()` accepts `undefined`, not `null`. Map at the hand-off
  (`visitorId: input.visitorId ?? undefined`) or widen the schema to `.nullish()` when null means
  something downstream.
- **Producer looser than the contract** (`string | undefined` where the schema requires a string).
  Tighten the producer's type if it can never be missing, or handle the missing case explicitly.
  Never coerce it to satisfy the compiler (`?? ""` swaps one runtime error for a vaguer one).

### 4. Do not re-validate what is already typed

An internal call between typed functions needs no runtime schema unless the schema normalizes,
applies defaults, or the value crossed a process, queue or persistence boundary on the way. A parse
with no job left is a second, weaker copy of the type, and it is the copy that fails in production.

## Anti-Patterns

- **Inferred builder return types** feeding a parse two lines later
- **`as SchemaInput` on the builder's result**: silences the exact check this skill adds
- **Widening a type at the producer** without searching for every schema that value reaches
- **Catching the ZodError and passing the raw object through** to keep the request alive
- **Testing the builder alone**: assert the builder's output parses, the pair is the unit

## Regression Test Shape

Run the builder through the real schema, the two steps production takes, with the widened value:

```ts
it("records a booking from a visitor with no stored visitor id", () => {
  const parsed = RecordParamsSchema.safeParse(buildRecordParams(inputWith({ visitorId: null })));
  expect(parsed.error?.issues).toBeUndefined();
});
```

## Audit Checklist

- [ ] `rg -U '\.(safeP|p)arse\(\s*(build|map|to)[A-Z]'` finds builders feeding a parse (`-U`: the
      call usually wraps onto a second line). `rg -U '\.(safeP|p)arse\(\s*\{'` lists inline literals;
      most parse untrusted input, so review it rather than count it
- [ ] Every builder feeding a parse declares `z.input<typeof Schema>` (or the literal uses `satisfies`)
- [ ] No builder result is cast to the schema type
- [ ] Every parse of internal data has a stated job (normalizing, defaults, a crossed boundary)
- [ ] Each widened field (`| null`, new union member) was traced to every schema it reaches
- [ ] A test runs builder plus schema together with the widened value
