---
name: provider-neutral-sync-policy
description: >
  Put the rule that decides what an integration does to an external record (reuse it, start a
  new one, leave it alone, which local record owns it) in one pure module that every provider
  adapter calls. Use when two or more CRMs, payment providers or ticketing tools each carry
  their own copy of "should this event update the existing record or create another"; when one
  provider creates duplicate records the others do not; or before merging two providers' rules
  into one, which must start by proving they are the same rule.
---

# Provider-Neutral Sync Policy

Every integration that writes to an outside system answers the same question on every event:
does this update a record that already exists there, start a new one, or leave it alone? When
each provider answers it in its own adapter, the answers drift. One CRM collects a deal per
booking while another keeps one per customer, and nobody decided that on purpose.

The fix is to split the question in two. **Policy** (what should happen) lives in one pure
module with no I/O. **Translation** (how this provider stores it) stays in each adapter, which
reads provider records into the module's shapes and writes its answers back.

The trap is the merge itself. Two adapters that look like copies of one rule often encode two
different rules on purpose. Merge them blind and one provider's behaviour silently changes.

## When This Skill Activates

- A second or third provider adapter is about to grow its own "find the existing record" logic.
- One provider creates duplicate external records (a deal, an invoice, a ticket per event) and
  the others do not.
- A refactor plans to move several providers onto shared logic "with no behaviour change".
- Inbound events (won, paid, closed) must map back to one local record, and several local
  records can point at the same external one.

## The Diagnostic Question

> If the business changed this rule tomorrow, how many integration files would you edit, and
> would you be sure every provider changed the same way?

More than one file, or "not sure", means the policy is living in the adapters.

## Decision Tree

```
Does more than one adapter decide reuse vs create for external records?
├─ No  → keep it in the adapter; revisit when a second provider arrives
└─ Yes → Do the adapters encode the SAME rule?
         Check each adapter's tests, not its code: tests are the behaviour contract.
         ├─ Same rule → extract one pure module; adapters translate only
         ├─ Different rules, both deliberate → keep them apart; write down WHY in the
         │    decision record and in both module headers, so the next reader stops trying
         └─ Different by accident → a product decision first (which rule wins?), then a
              behaviour-change ticket with the losing provider's tests rewritten
```

## Core Rules

### 1. The policy module is pure

No database, no HTTP, no clock. Every export takes plain inputs and returns a decision. That
makes the rule unit-testable in milliseconds and impossible to call with half-loaded state.

```ts
// CORRECT: pure decision, provider-shaped inputs mapped by the adapter
export type Status = "open" | "won" | "lost" | "unknown";

export function deriveAdoption(input: {
  madeByUs: boolean;
  status: Status;
  ownerFinishedLocally: boolean;
}): "reuse" | "start_new" | "leave_alone" {
  if (!input.madeByUs) return "leave_alone";
  if (input.status !== "open") return "start_new";
  if (input.ownerFinishedLocally) return "start_new";
  return "reuse";
}

// WRONG: the "policy" fetches, so the rule is untestable without mocks and drifts per caller
export async function shouldReuse(dealId: string) {
  const deal = await crm.getDeal(dealId); // I/O inside policy
  return deal.status === "active";
}
```

### 2. Never adopt a record a person made by hand

Only records your integration created or stamped are candidates. A rep's own deal, a
customer's own ticket, stays theirs. Make "made by us" an explicit input, not an inference
buried in a field comparison.

### 3. Never reopen finished business, and fail closed on unknowns

A record that is won, lost, paid or closed is history. Writing a new stage to it can silently
reopen it, because many providers derive status from stage. Treat a status the provider did not
report as finished: the cost of an extra record is small, the cost of reopening a closed deal is
a corrupted pipeline.

Also trust your own outcome. If stage sync is optional, the provider may still show a deal open
that your system already marked won. Pass that local fact in.

### 4. Inbound mapping must be deterministic

Once several local records can point at one external record, "find the local record for this
external id" with `LIMIT 1` and no ordering returns an arbitrary row. Record which local record
drives the external one (a claim), and fall back to a stable order (newest, then id) when the
claim is missing or stale. A stale claim then needs no cleanup.

```ts
export function deriveDriver(args: {
  claimedId: string | null;
  linked: Array<{ id: string; createdAt: Date }>;
}): string | null {
  if (args.claimedId && args.linked.some((r) => r.id === args.claimedId)) return args.claimedId;
  const newest = [...args.linked].sort(
    (a, b) => b.createdAt.getTime() - a.createdAt.getTime() || b.id.localeCompare(a.id),
  )[0];
  return newest?.id ?? null;
}
```

### 5. Write the claim with the pointer, in one statement

If the parent's pointer to the external record and the claim naming its driver are written
separately, a crash between them leaves them disagreeing. Write both in one update.

### 6. Only the writer that takes a record over moves the claim

A later write by an older local record (a reschedule of the first booking) must not steal the
claim from the newer one that took the record over. Decide "takes over" explicitly at the call
site.

### 7. Prove the merge before you make it

Before moving a provider onto the shared module, read that provider's tests for the four
decisions: reuse of finished records, link overwrite vs set-once, inbound fallback, ownership
check. Any test that pins a different answer is a product decision, not a refactor detail. Stop
and ask which rule should win.

## Implementation Pattern

```
policy/opportunity-reuse.ts      pure: adoption, preferred candidate, driver, link writes
providers/crm-a/resolution.ts    reads A's records → policy inputs → decision
providers/crm-a/sync.ts          writes A's record, records links per policy
providers/crm-b/...              same shape; B's own field names and status vocabulary
repository/driver-lookup.ts      the one query that gathers linked local records + claim
```

Each adapter owns exactly one mapping function from its status vocabulary to the policy's
(`active` → `open`, etc.). Unknown values map to `unknown`, which the policy treats as finished.

## Anti-Patterns

- **The third copy.** A new provider gets its own reuse logic "for now". Two copies drift in a
  quarter; three copies drift in a sprint.
- **Merge by resemblance.** Two adapters with similar helper names are assumed to share a rule.
  One keeps a won record and moves its stage; the other starts a new one. The merge changes one
  provider's behaviour and its tests are "fixed" to match.
- **`LIMIT 1` with no order** on an external-id lookup once records can be shared.
- **Status inferred as open when absent.** A missing field reopens history.
- **Policy that reads.** A "pure" helper that awaits a provider call cannot be tested without
  mocks and gets called in loops.

## Audit Checklist

- [ ] One module decides reuse / start new / leave alone for every provider that follows the rule.
- [ ] The module has no I/O; every export is unit-tested with provider-free inputs.
- [ ] Hand-made external records are never adopted, by an explicit `madeByUs` input.
- [ ] Finished and unknown statuses start a new record; local finished outcomes count too.
- [ ] Inbound events map to one local record deterministically, with a claim and a stable fallback.
- [ ] Pointer and claim are written in one statement; only a take-over moves the claim.
- [ ] Providers that deliberately follow a different rule say so, with the reason, in the
      decision record and both module headers.
- [ ] Every provider's tests were read before any merge, and differing tests produced a decision.

## Related

- `catalog-driven-resolver`: when the rule is a per-type table that call sites bypass.
- `superseding-a-record`: when the local records themselves are merged or replaced.
- `dedup-key-completeness`: when a second legitimate record vanishes into the first.
