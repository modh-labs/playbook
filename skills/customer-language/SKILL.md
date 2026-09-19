---
name: customer-language
description: Write or review customer-facing UI copy, help text, errors, onboarding, and product docs in plain language. Use whenever product language is added or changed.
---

# Customer language

Make the product understandable on the first read. Preserve the behavior and
the distinctions customers need, then remove the vocabulary of the
implementation.

## Write from the customer's task

Before editing copy, identify what the person is trying to do, what choice they
must make, and what happens next. Labels name that choice. Help text explains
the consequence. Buttons name the action.

Translate internal nouns into the customer's model. Keep schema fields,
versions, formulas, worker names, and architecture terms in code and technical
documentation. Customer copy names the visible thing or result.

Examples of the translation, not fixed replacements:

| Internal term | Customer language |
|---|---|
| relative influence | importance |
| scoring recipe | scoring settings |
| recalculate saved leads | update existing lead scores |
| pre-enrichment score | estimated score |
| contact metadata | email and phone details |

Use a technical term when the customer must recognize it elsewhere. Define it
in plain words the first time.

## Keep the interface direct

- Prefer common words and concrete verbs.
- Put the important distinction in the label, not only in a tooltip.
- Give one concept one name across the UI, docs, stories, and accessibility
  labels.
- Explain calculations with a small example before showing a formula.
- State errors as what happened, what stayed safe, and what the person can do.
- Preserve legal, financial, security, and operational precision.

If the project has a copy guide (for example `docs/standards/copy-guide.md`),
its canonical labels and templates win over anything here.

## Match tone to the moment

Voice stays fixed. Tone follows what the person is feeling at that moment.

| Moment | Likely state | Tone |
|---|---|---|
| Error, blocked, failed payment | frustrated, anxious | Plain and practical. No humor, no apology unless we failed. |
| Destructive action | cautious | Exact consequence and count. Name what can't be undone. |
| Billing, trial, plan limits | wary about money | Exact amounts and dates. No urgency theater. |
| Empty state, onboarding | uncertain | Benefit plus the one next step. |
| Success | relieved | Short past tense naming the object. Light warmth is fine. |

## Controls and feedback

- Buttons are a verb plus an object and say what happens: `Delete 3 leads` /
  `Keep leads`, never `Yes` / `No`, `OK`, or `Submit`.
- Confirm only destructive, irreversible actions. Offer Undo for everything
  else. The dialog title asks the specific question and the body states the
  consequence; never "Are you sure?".
- Errors sit next to their cause, keep the user's input, and never blame the
  person. Empty field: an instruction (`Enter an email`). Broken rule: a
  description (`End date must be after start date`).
- Empty states say why it's empty and offer one action that fills it. Never
  show "empty" while data is still loading.
- Loading copy names the step and, when known, the time or count.
- Notifications carry enough context for someone who was doing something else.
- Link text names the destination. No "click here", no bare "Learn more", no
  directions that depend on layout ("in the right sidebar").

## AI features

- Say what the feature does for the person, not the technology.
- State limits before first use, and name the data source ("Based on this
  call's transcript").
- Label generated output as a draft or suggestion and give edit, regenerate,
  and turn-off controls. Nothing customer-visible sends without approval
  unless the person chose that.
- Show confidence as High / Medium / Low with the reasons, not a bare
  percentage.
- Never "magic", "knows", "understands", "perfect", or any claim of certainty.

## Words to cut

"Oops", "Uh-oh", or jokes in errors. "Something went wrong" with no next
step. "Please" in instructions. "Invalid", "illegal", "forbidden", "you
forgot", "you failed to". "Are you sure?". "Click here". "Simply", "just",
"easy", "quick". "Successfully". "Unlock", "supercharge", "seamless",
"powerful", "revolutionary". Stacked exclamation marks. Raw error codes,
HTTP statuses, and internal service names.

Progressive disclosure is for details, not for the meaning of a control. A
person should understand the primary action without opening a tooltip or help
article.

## Audit the changed experience

Read each changed screen as a customer who has not seen the code. Flag any
word that requires knowledge of the database, scoring model, architecture, or
team shorthand. Check headings, labels, descriptions, empty states, errors,
toasts, tooltips, dialogs, accessibility names, Storybook names, and customer
documentation.

Search the changed product area for every term you replaced. Update all
customer-facing occurrences and the tests that pin them. Leave internal symbol
names alone unless the task also includes a code-model change.

The work is complete when the UI can be read out of context and a customer can
state what the control does, what the values mean, and what will happen after
the action. Verify the rendered layout when copy length or hierarchy changed.
