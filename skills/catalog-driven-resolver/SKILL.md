---
name: catalog-driven-resolver
description: >
  Turn a declared policy table into the only code path that produces its output. Use when a
  catalog, registry or config map declares a per-type rule (who a message is from, who may call
  a tool, which posture or limit applies) but each call site computes the result itself; when a
  rule in the table is not what production does; or before adding a new input dimension to that
  rule (a tenant setting, a status, a region) that would otherwise mean editing every call site.
---

# Catalog-Driven Resolver

A policy table that no code reads is a comment. It feels like a control, it reviews like a
control, and production does whatever each call site happened to write.

The fix has five parts, and they only work together:

1. **One resolver** reads the catalog and produces the output for every type.
2. **A branded output type** that only the resolver can create, so a hand-built value does not compile.
3. **A lint ban** on building the output anywhere else.
4. **A characterization grid** captured on the old code before anything moves.
5. **A matrix test generated from the catalog**: every type x every state x every case, failing when a catalog entry has no rows.

Once those exist, a new dimension (a per-tenant setting, a verification status) is one new input
to one function, and the matrix grows a column instead of N files growing a branch.

## When This Skill Activates

- A catalog or registry lists a rule per type, and a grep shows call sites building the output themselves.
- A reviewer asks "does the table actually say what production does?" and nobody can answer by reading one file.
- A planned feature changes the rule for every type ("send from the tenant's domain", "scope every tool by role").
- A bug report shows one type ignoring a rule the table states.

The diagnostic question: **if I change one row of this catalog, does behavior change, and if I add a new input, how many files do I edit?** If the answers are "no" and "N", this pattern applies.

## Decision Tree

```
Does a table declare the rule per type?
├─ No → write the table first; this pattern needs a single source of truth
└─ Yes → Does exactly one function read it to produce the output?
    ├─ Yes → Can a caller still build the output by hand?
    │   ├─ Yes → add the branded type + lint ban (Rules 2, 3)
    │   └─ No  → is there a matrix test generated from the table?
    │       ├─ No  → add it (Rule 5); the pattern is unproven without it
    │       └─ Yes → done; new dimensions go into the resolver's input
    └─ No (call sites compute it) →
        1. Characterization grid on the old code (Rule 4), green before any move
        2. Resolver + branded type
        3. Move callers to pass facts, not outputs
        4. Lint ban on, shown failing on a planted violation
        5. Matrix test from the catalog
        6. Only then add the new dimension
```

## Core Rules

### 1. Callers pass facts, the resolver decides

WRONG: each call site assembles the result from shared helpers. The table is consulted by nobody.

```ts
// notification-a.ts
const from = buildSender(branding, hostName);
const replyTo = buildReplyTo(branding, hostEmail);
await send({ from, ...(replyTo && { replyTo }), type: "reminder" });
```

CORRECT: the caller states what is true about this message; the resolver applies the catalog.

```ts
const identity = resolveMessageIdentity({
  type: "reminder",
  branding,
  facts: { host, closer, guest },
});
await send({ identity, type: "reminder" });
```

### 2. Only the resolver can create the output

Brand the type so a literal or a hand-assembled object fails typecheck.

```ts
declare const brand: unique symbol;
export type MessageIdentity = { from: string; replyTo: string; subject: string } & {
  readonly [brand]: true;
};

export function resolveMessageIdentity(input: IdentityInput): MessageIdentity {
  const policy = CATALOG[input.type];
  // ...apply policy...
  return result as MessageIdentity; // the one sanctioned cast, inside the resolver
}
```

`send()` accepts `MessageIdentity`, never `{ from: string }`.

### 3. A lint rule makes the bypass visible

Ban the raw client and the output's key outside the resolver's module. Show the rule failing on a
planted violation before trusting it. A guard that has never gone red is a hypothesis.

### 4. Characterize before you move

Before touching any call site, record today's output for every type and a representative set of
inputs. The grid must be green on the old code. Every later step re-runs it. Each cell that changes
is either a named, deliberate change listed with the PR, or a defect. "It was inconsistent anyway"
is not a third category.

### 5. The matrix is generated from the catalog

```ts
const TYPES = Object.keys(CATALOG) as MessageType[];
const STATES = ["none", "pending", "verified", "failed"] as const;
const CASES = [noSettings, nameOnly, replyToSet] as const;

describe.each(TYPES)("%s", (type) => {
  it.each(cartesian(STATES, CASES))("%s / %s", (state, kase) => {
    expect(resolveMessageIdentity(build(type, state, kase))).toEqual(EXPECTED[type][state][kase.name]);
  });
});

it("every catalog type has expected rows", () => {
  for (const type of TYPES) expect(EXPECTED[type]).toBeDefined();
});
```

A new catalog entry without expected rows fails the build. That is the point: the table and the
test cannot drift apart.

### 6. New dimensions enter as resolver input

Adding "tenant sending domain status" means one new input field, one new matrix axis, and one
change in the resolver. If the plan touches the call sites, it has missed the job.

## Anti-Patterns

- **The comment catalog.** A table with a `replyPolicy` per type that the code never reads. It passes review because it looks like policy.
- **Helpers mistaken for a resolver.** Shared `buildX()` helpers that every caller combines differently. N combinations of correct helpers still produce N behaviors.
- **The string type key.** `type: string` on the send path. Any typo is a new, untested type.
- **The silent optional.** `...(value && { value })` at every call site, so a missing value drops the field instead of failing. Required outputs are required in the branded type.
- **Refactor and behavior change in one breath.** Moving callers and changing rules without a characterization grid makes every diff unreviewable.
- **A matrix written by hand.** It covers the types someone remembered. Generate the type axis from the catalog.

## Audit Checklist

- [ ] Every value in the policy table is read by exactly one function.
- [ ] `grep` for the output's key (e.g. `from:`) outside the resolver returns nothing, and a lint rule enforces it.
- [ ] The send path accepts only the branded type and a typed key, not a string.
- [ ] A characterization grid exists, was green on the pre-refactor code, and lists every deliberate change by name.
- [ ] The matrix test derives its type axis from the catalog and fails on a type with no expected rows.
- [ ] Each guard (brand, lint, matrix) has been shown failing on a planted violation.
- [ ] The next planned dimension is described as a resolver input, not as call-site edits.
