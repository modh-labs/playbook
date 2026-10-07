---
name: session-token-claim-budget
description: >
  Session tokens stored in a cookie have a size budget, and every custom claim
  spends it. Use when adding or reviewing claims in an auth provider's session
  token template (Clerk, Auth0, NextAuth JWT, Supabase custom-claims hook); when
  a template copies a whole metadata object; when a provider warns about cookie
  size; when users loop back to sign-in after a successful login; or before
  editing a production token template.
---

# Session Token Claim Budget

A session token that lives in a cookie has a hard ceiling: browsers drop a
cookie over about 4 KB, and the provider's own default claims and signature
already use most of it. Clerk, for example, leaves about 1.2 KB for custom
claims. Past the ceiling the cookie is never set. Sign-in "succeeds" and the
user lands back on the sign-in page, every time, with no error anywhere.

Treat the template as a **budget**. Every claim names its **reader**, copies a
**field** rather than an object, and changes through a **proven rollout**.

## When This Skill Activates

- A token template contains a whole-object shortcode: `{{user.public_metadata}}`, `{{org.public_metadata}}`, `{{user.organizations}}`, an unbounded array
- Code writes a new key to user or org metadata that a template copies whole
- The provider dashboard warns about cookie or token size
- A user reports a sign-in loop that you cannot reproduce on your own account
- Anyone is about to edit a production token template

## The One Question

> For each claim in the token, who reads it, and what bounds its size?

A claim with no reader is dead weight. A claim whose size grows with the user's
data (memberships, a list of IDs, a whole metadata object) has no bound, and
the heaviest user will hit the ceiling first.

## Decision Tree

```
For each claim in the template:
├─ Does anything read it? (middleware, RLS / DB policies, API auth, mobile, server code)
│   └─ NO → drop it
├─ Is it a whole object (metadata, organizations, membership list)?
│   └─ YES → replace with field-level paths for exactly the fields readers use
├─ Is it a list that grows with the user (IDs, roles per workspace)?
│   └─ YES → cap it in the code that writes it (most-recent N), or move the fact
│            to a per-active-context claim that is one value, not a list
├─ Does the provider already emit it as a default claim (sub, active org)?
│   └─ YES → drop the duplicate unless a reader needs that exact name
└─ Otherwise keep it, unchanged
```

## Steps

### 1. Read the live template, not the docs or memory

The template drifts: dashboard edits leave no commit, and staging and production
silently diverge. Read both from the source of truth.

- Config API or CLI where the provider has one (Clerk: `clerk config pull --instance <dev|prod> --keys session`, under `session.claims`).
- The rendered result: have the provider mint a token for **your own** session (Clerk: `POST /v1/sessions/{id}/tokens`), decode the payload, and print only claim names and byte sizes. A token is a credential: never print it, never mint one for another user's session.
- Note any claim that appears in the token but not the template. Integrations inject claims (Clerk's Supabase integration adds `role: "authenticated"`).

Done when both environments' templates are saved to files and one real token's claim list is recorded.

### 2. Size every user, not just yourself

Your account is small. The heavy users are admins in many workspaces.

- Reconstruct each user's custom-claims payload from stored data (metadata, memberships) via the admin API, read-only.
- Calibrate the estimate against the one real token from step 1 (the offset from defaults, header and signature).
- Report median, p95, max and the top users, with what makes each one heavy.

Done when you have a size for every user and know which claim drives the largest ones.

### 3. Map every claim to its readers

Search every consumer, not just the web app: database policies (`auth.jwt() ->> 'org_id'`), API middleware, the mobile client, server code reading session claims. Build a table: claim, readers, keep/drop/narrow.

Done when every claim in the template has a row and every "drop" row cites the search that found no reader.

### 4. Write the smallest template that keeps every reader working

- Narrow whole objects to field paths. Providers that support dot paths keep the field's type: an array stays an array, a boolean stays a boolean, a missing field becomes `null`.
- Keep claim **names** stable so no code deploy is needed. Short-key renames save a few bytes and cost a coordinated deploy; rarely worth it.
- Confirm each reader treats `null` the same as "missing" (falls back safely).

Done when the proposed template has an upper bound you can state in bytes.

### 5. Roll out with proof at each step

1. **Backup**: save the full config of the target environment.
2. **Dry-run**: preview the patch. Check whether the provider merges or replaces the claims object (Clerk's config patch replaces it whole, so omitted claims are removed).
3. **Staging**: apply, read back, mint a token, confirm the claim shapes (arrays still arrays, dropped claims gone).
4. **Production**: re-read the live config and compare it to the backup *immediately before* applying. A whole-object replace erases any edit made since your backup.
5. **Apply, read back, mint a token from your own session, compare sizes.** Tokens are short-lived (Clerk: 60 s), so everyone has the new shape within a minute.
6. **Watch**: errors, auth fallbacks to the database, and the provider's warning.

Rollback is a patch back to the backup's claims.

Done when production's read-back matches the patch and a freshly minted token shows the intended claims.

## Anti-Patterns

| Pattern | Why it fails |
|---|---|
| `"metadata": "{{user.public_metadata}}"` | Every feature that saves anything to user metadata grows every token. Nobody notices until someone is locked out. |
| An ID list appended on every visit | Grows with the user's history. The admin of dozens of workspaces breaks first. |
| Editing the production template in the dashboard by hand | No backup, no diff, no record of what it was. |
| Verifying on your own small account only | Your token is far from the ceiling; the failing users are not you. |
| Trusting the docs for the current template | Integrations inject claims, and environments drift. Read the live config. |
| Raising the cap instead of narrowing the template | Moves the cliff; the next metadata key finds it again. |

## Audit Checklist

- [ ] Both environments' templates read from config, saved to files
- [ ] One real token decoded (names and sizes only) per environment
- [ ] Every user sized; median, p95, max and heaviest users known
- [ ] Every claim has a reader or is dropped
- [ ] No whole-object or unbounded-list shortcodes remain
- [ ] Every growing list is capped where it is written
- [ ] Readers treat `null` like missing
- [ ] Staging applied and proven with a minted token
- [ ] Production compared to backup immediately before applying
- [ ] Production read back and proven with a minted token
- [ ] A size check exists so the provider's warning is not the first signal

## Related

- `middleware-cookie-fast-path`: a different cookie, with the same rule that a cookie value must stay tiny.
- `prove-your-telemetry`: read a real emitted artifact (here, a minted token) rather than trusting the configuration.
- `blast-radius`: the claim-to-reader map is the blast radius of a template edit.
