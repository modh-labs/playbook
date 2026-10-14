---
name: ai-engineering-storytelling
description: >
  Use whenever you finish a non-trivial fix, refactor, audit, or decomposition.
  Watches the live session for moments where AI-skill discipline produced an
  outcome that humans would have missed (catching a real bug during an
  unrelated audit, decomposing a 1300-line file via a documented pattern,
  composing skills to avoid a band-aid). Captures those moments as
  ready-to-publish content artifacts: a blog post, a lead magnet outline,
  social copy, and a video concept.
---

# AI Engineering Storytelling

Most AI-coding content is "look at this autocomplete." It does not move
buyers. The content that moves buyers is **specific stories where AI
discipline caught a real problem a senior human would also have missed**.

Those stories happen all the time. They almost never get written down,
because the engineer is heads-down fixing the problem and never zooms out
to ask "wait, what just happened here was actually unusual."

This skill is the zoom-out. Run it whenever you finish a non-trivial piece
of work. It captures the story while the context is still in your head and
emits ready-to-publish artifacts.

## When to invoke

Trigger this skill at the **end** of any of these:

- A bug fix where you uncovered a deeper systemic issue mid-investigation
- An audit + remediation pass on a route or component
- A SOLID decomposition of an oversized file
- A refactor where a sub-agent (code-reviewer, explore, plan) caught
  something you missed
- A multi-skill composition (e.g. brainstorming → writing-plans →
  test-driven-development → code-review) on a single task
- Any moment where you thought "oh, that's actually pretty cool"

If none of these triggered, do not run the skill. The point is signal,
not volume.

## The five-question filter

Before drafting content, gate the story through these five questions. If
the answer to any is "yes," it is publishable. If all answers are "no,"
move on.

1. **Counterintuitive insight** — does the story contradict an "obvious"
   approach a senior engineer would default to? (e.g. "we wanted to
   centralize at the repository, but the right answer was composing at
   the read site")
2. **Hidden bug surfaced** — did skill discipline (audit, review, plan)
   surface a bug that the original task description would never have
   asked about? (e.g. "user reported missing border, audit caught a
   reveal-gate logic error in the same component")
3. **Forced rigor** — did a skill make us write tests / observability /
   docs we would have otherwise punted? (e.g. "the o11y rule said add a
   structured log on the legacy-synthesis branch — now we can quantify
   how many legacy rows are still in the wild")
4. **Composed leverage** — did multiple skills compound? (e.g. "the
   debugging skill told us where to look, the audit skill found the
   gate bug, the decomposition skill split the renderer, the storytelling
   skill made it shareable")
5. **Pattern worth codifying** — is there a reusable pattern we just
   demonstrated that other teams would copy? (e.g. "expand-then-normalize
   composition for unified data shapes")

## Outputs

When the filter passes, generate **all four** of the following artifacts
and place them under `content/content-library/lead-magnets/<slug>/`. The
slug should be descriptive and short (e.g. `ai-skill-stack-case-study`,
`legacy-row-repair-pattern`, `decomposition-without-bugs`).

### 1. `case-study.md` — the core narrative (1500-2500 words)

Structure:

- **Hook** (one short paragraph, the surprising outcome — not the setup)
- **Setup** (one paragraph, what the user actually asked for)
- **The first turn** (what AI normally would have done — autocomplete the
  fix, ship it, move on)
- **What we did instead** (the skill stack, the decision points, the
  surprising find)
- **Code receipts** (real diff snippets, real file paths, real commit
  messages — this is where credibility lives)
- **The stack** (named list of skills that fired and what each one did)
- **Lessons** (3-5 transferable lessons, each with a one-line punchline)
- **CTA** (link to the playbook chapter / strategy session / whichever is
  most adjacent)

### 2. `social/twitter.md` — a 5-7 tweet thread

The first tweet is the hook from the case study. Each subsequent tweet is
one transferable lesson with a code/diff visual. Final tweet: link + CTA.

### 3. `social/linkedin.md` — a single 200-400 word LinkedIn post

Same hook. More narrative. One concrete code snippet. CTA at the end.
Targets engineering leaders, not engineers.

### 4. `video-concept.md` — a 5-10 minute video concept

Following the existing modh video-concept format (see
`content/content-library/videos/done/*/concept.md`):

- Title options (3)
- Hook (one sentence, a contrarian claim)
- Main theme
- Key message (3-5 bullets)
- The story arc (a 4-5 stage transformation)
- Key reframe (false belief vs truth)
- CTA

## Writing rules (style, not just format)

- **Lead with the surprise, not the setup.** "We caught a production bug
  during an unrelated audit" beats "Last Thursday we got a bug report
  about..."
- **Show real artifacts.** Real file paths, real diffs, real Linear
  ticket numbers. Vague "we did X" is fiction in this format.
- **Name the skills.** This is a skills-marketing exercise. Write
  "the `audit` skill found..." not "we audited and found..."
- **One protagonist per story: the discipline.** Not "Claude is
  amazing." Not "I spent four hours". The hero is the SKILL — the
  process. The takeaway is "if you set up these skills, this happens
  to you too."
- **Counterintuitive > comprehensive.** A single sharp lesson lands
  harder than a survey of everything you did.
- **No emojis. No emdashes.** Per the modh content style.
- **Cite the user's words.** When the user said something quotable
  ("fuck filing the tracker, DO IT"), use it. It is the most authentic
  proof that this is a real session, not a hypothetical.

## Anti-patterns to reject

- **Writing the case study from a hypothetical.** If the work was
  trivial, do not invent stakes. Skip publishing — there is plenty of
  real material every week.
- **Writing it as "10 things I learned today."** That format reads as
  AI sludge. Use a single transformation arc instead.
- **Tool worship.** "Claude is so smart" is not a story. The story is
  what the discipline produced, not what the model is capable of.
- **Burying the diff.** The code receipts are the proof. Put at least
  one real diff snippet above the fold of the case study.

## How to use this skill mid-session

You do not have to wait until the end. If you notice mid-session that
something interesting is happening, drop a one-line note in scratch
memory:

> "Cool moment: code-reviewer agent found a logic bug in the same
> file we were touching for an unrelated audit. Capture this."

Keep working. When you wrap, the storytelling skill assembles those
notes plus the diff into the four artifacts.

## Reference implementation

The first published case study using this skill:
`content/content-library/lead-magnets/ai-skill-stack-case-study/`

That story walks through how:

1. A user reported "form fields render in the wrong stage on the public
   booking page"
2. The plan-mode workflow (Explore agents in parallel) identified the
   root cause as a read-helper composition gap
3. The audit skill, run on the resulting fix, found a separate
   pre-existing logic bug in the same file (the reveal-gate ignored
   phone-when-in-preview)
4. The decomposition skill broke the 1300-line renderer into orchestrator
   + leaves + hook + utilities — without introducing a bug, because each
   step had its own test green-light

The session shipped: 22 new tests, 3 documentation surfaces updated,
1 production bug fixed, 1 latent bug caught, 1 oversized component
decomposed, all under one continuous skill-driven workflow.

## CTA placement

Every artifact links back to the modh playbook (the chapter that the
story illustrates) and to the modh-labs/playbook GitHub repo (so a
reader can install the skill stack and run it themselves).

For lead-magnet artifacts, link to the relevant gated PDF:
`https://modh.ca/playbook` for the master entry point.
