---
name: provision-live-to-learn-contract
description: When an external API's exact request schema is uncertain and a dry-run skips the network, stop guessing from docs — make ONE real call and let the error response teach you the precise contract, then fix and retry. Activates when scripting create/update against an API (dashboards, webhooks, resources) whose field/enum shape you're inferring, especially when a dry-run can't validate it.
---

# Provision Live to Learn the Contract

Docs drift, enums get deprecated, and a `--dry-run` that skips the network can
only validate *your* code, not the *server's* acceptance. When you're unsure of
an API's exact shape, a single live call is the fastest, most reliable spec —
well-built APIs reject with the exact remedy in the error body.

## The One Question

> **"Has anything actually validated this payload against the server, or only against my own code?"**

A passing dry-run, a green typecheck, and matching docs all answer "only my code."
Only a real request answers "the server."

## Core Rules

1. **Prefer a live POST/PUT over more doc-reading** once you've made a reasonable
   first attempt — the round-trip is faster than another docs pass and is ground truth.
2. **Read the error body, don't just check the status.** Good APIs name the bad
   field + the fix (e.g. *"the transactions dataset is deprecated; use the spans
   dataset with `is_transaction:true`"*). That one 400 replaced an hour of guessing.
3. **Make the first live call cheap + reversible** — one resource, idempotent
   (upsert-by-name), easy to delete. Then iterate on the error.
4. **A dry-run that skips the network is for payload assembly, not acceptance.**
   Use it to catch shape/typos, but never trust it as "this will work."
5. **Codify what the error taught you** in the script + a comment so the next
   person doesn't re-learn it (and the deprecation is recorded).

## Anti-Patterns

- Shipping an un-exercised payload for someone else to debug in prod.
- Treating "dry-run passed" as "it works".
- Re-reading docs in a loop when one live call would settle it.
- Bulk-creating N resources before validating the shape on one.

## Audit Checklist

- [ ] The payload was validated by a real server call, not just a dry-run/typecheck.
- [ ] First live attempt was a single, reversible resource.
- [ ] Error responses were read for the exact contract, not just status-checked.
- [ ] The learned contract (and any deprecation) is captured in code + comment.
