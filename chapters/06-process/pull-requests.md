---
title: "Pull Requests"
subtitle: "CI passes first, then a rich description with test plan"
chapter: 19
section: "Process"
seo_title: "Pull Request Standards — CI First, Rich Descriptions, Test Plans 2026"
seo_description: "CI must pass before review. Every PR has a summary and test plan. No empty descriptions, no draft PRs that linger, no force-pushes that erase history."
keywords: ["pull requests", "code review", "CI pipeline", "test plan", "PR description", "engineering process"]
reading_time: "7 min"
difficulty: "beginner"
tech_stack: ["Next.js", "Supabase", "TypeScript"]
business_case: "Well-structured PRs reduce review time by 50% and eliminate the 'what does this PR do?' round-trip that adds a day to every merge cycle."
---

# Pull Requests

> "A PR without a description is asking your reviewer to do your thinking for you."

## The Problem

A notification appears: "Review requested on #347." The reviewer opens the PR. The title is "fix stuff." The description is empty. There are 14 changed files across 6 directories. No summary. No test plan. No context for why these changes exist.

The reviewer starts reading code. They see a database query change and wonder: is this a performance fix or a behavior change? They see a new component and wonder: is this replacing an old one, or is it additional? They see a deleted file and wonder: was this dead code, or will something break?

They leave three comments asking for context. The author responds the next day. Two of the answers generate follow-up questions. The review takes four days for a change that should have taken four hours.

This is what happens when PRs lack description. The reviewer reverse-engineers intent from implementation. Every ambiguity becomes a comment. Every comment becomes a round-trip. The merge cycle stretches from hours to days.

The other failure mode is reviewing a PR where CI hasn't passed. The reviewer spends 45 minutes understanding the code, leaves thoughtful comments, and then discovers the tests are failing. The author fixes the tests, which requires changing the implementation, which invalidates half the review comments. The reviewer starts over.

Both failures have the same root cause: the PR was opened before it was ready for review.

## The Principle

A pull request is ready for review when two conditions are met: CI is green, and the description tells the reviewer everything they need to evaluate the change without reading a single line of code.

CI passes first. Then you write the description. Then you request review. This order is non-negotiable.

## The Pattern

### CI passes first

Before opening a PR, the full CI pipeline must pass locally or in the CI environment:

```bash
# Run the full check before opening a PR
bun ci   # Runs lint + typecheck + test
```

This catches the obvious issues — type errors, lint violations, failing tests — before a human spends time reviewing. If CI fails after the PR is opened, fix it before requesting review.

The CI pipeline runs cheapest checks first: linting, then type checking, then tests. This means most failures surface within 30 seconds, not after a 10-minute test suite.

### The PR description

Every PR description has two required sections: a summary and a test plan.

```markdown
## Summary

- Add CSV export for filtered orders (resolves AUR-234)
- Export respects all active table filters (date, status, assignee)
- Maximum 10,000 rows with user-facing toast when limit exceeded

## Test plan

- [ ] Export with no filters produces full order list
- [ ] Export with date filter produces correct subset
- [ ] Export with >10K matching orders shows truncation toast
- [ ] Export with no matching orders shows informational toast (no file)
- [ ] CSV correctly escapes customer names containing commas
- [ ] Loading spinner shows during generation
- [ ] File name includes current date
```

The summary tells the reviewer what changed and why. Three bullet points. The "why" is more important than the "what" — the diff shows the what.

The test plan tells the reviewer how the author verified the change works. This serves two purposes: it demonstrates the author tested their own code, and it gives the reviewer a checklist to validate against.

### PR titles

Keep titles under 70 characters. Use the conventional commit format:

```
feat(orders): add CSV export with filter support
fix(payments): prevent duplicate refund processing
refactor(auth): extract Clerk webhook handler to service layer
test(orders): add integration tests for bulk actions
docs(api): document partner webhook authentication
```

The prefix (`feat`, `fix`, `refactor`, `test`, `docs`) categorizes the change. The scope in parentheses identifies the domain. The description completes the sentence "This PR will..."

### Linking to tickets

Every PR references the ticket it implements. This creates bidirectional traceability — from the ticket you can find the code, from the code you can find the business context.

```markdown
## Summary

- Implement order export feature

Resolves AUR-234
```

If a PR addresses part of a ticket, use "Part of" instead of "Resolves":

```markdown
Part of AUR-234 (milestone 2 of 3)
```

### What belongs in one PR

A PR should do one thing. If the description requires "and" to explain, it's probably two PRs.

**Good PR scope:**
- "Add CSV export for orders" (one feature)
- "Fix duplicate payment webhook processing" (one bug)
- "Refactor order repository to use generated types" (one refactor)

**Too broad:**
- "Add export, fix payment bug, and refactor types" (three unrelated changes)
- "Update orders page" (what about it?)

When a feature requires both an enabler (schema change, new repository) and the user-facing implementation, ship them as separate PRs. The enabler merges first. The feature builds on it. This keeps each PR reviewable in under 30 minutes.

### Review expectations

For the author:
- CI must be green before requesting review
- Description must include summary and test plan
- Self-review the diff before requesting others — catch the obvious issues yourself
- Respond to review comments within 24 hours

For the reviewer:
- Review within 24 hours of request
- Focus on correctness, not style (linters handle style)
- Approve if the code is correct and the approach is sound, even if you would have written it differently
- Block only for: bugs, security issues, missing error handling, or architectural concerns

### What to do when CI fails after push

Fix the issue, commit the fix, push again. Do not amend the previous commit — create a new one. The fix commit documents what broke and how it was resolved.

```bash
# Fix the lint error
# Stage the fix
git add src/orders/actions/export-orders.ts

# New commit, not an amend
git commit -m "fix(orders): resolve lint error in export action"
git push
```

### Draft PRs: use sparingly

Draft PRs exist for one purpose: getting early feedback on an approach before completing the implementation. They are not a holding area for work-in-progress. If a draft PR sits for more than two days without requesting feedback, it should be closed.

When you do use a draft, be explicit about what feedback you want:

```markdown
## Draft — Feedback Requested

Looking for feedback on the approach before finishing implementation:

1. Is filter serialization via URL params the right approach, or should
   we pass filter objects directly to the server action?
2. Should the CSV generation happen in the action or in a utility function?

Not ready for line-by-line review — the implementation is incomplete.
```

### The anti-patterns

**Empty descriptions.** A PR with no description is asking the reviewer to reverse-engineer intent from code. This is disrespectful of their time and produces worse review outcomes.

**Requesting review on red CI.** The reviewer's time is wasted if the code doesn't compile. Fix CI first. Always.

**Force-pushing reviewed PRs.** Force-push erases the diff between review rounds. The reviewer can't see what changed since their last review. Use new commits instead.

**Mega PRs.** A PR with 40 changed files takes exponentially longer to review and has exponentially more bugs. If you can't review it in 30 minutes, it's too big. Break it up.

## The Business Case

- **Review time cut in half.** PRs with clear descriptions and passing CI are reviewed in 15-30 minutes. PRs without descriptions take 2-4 round-trips of clarification that stretch over days.
- **Fewer bugs reaching production.** The test plan forces the author to verify their own work before requesting review. The reviewer validates against the plan instead of guessing what to test.
- **Traceability.** Every feature links from ticket to PR to commit to deploy. When a customer reports an issue, you trace backward from the behavior to the PR to the ticket to the original request in minutes.

## Try It

Install the Modh Playbook skills to enforce this pattern automatically:
```bash
# Add to your project
git submodule add https://github.com/modh-labs/playbook .agents/modh-playbook
./.agents/modh-playbook/install.sh
```
