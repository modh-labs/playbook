---
name: stream-behind-first-step
description: Don't suspend a whole multi-step component on data only a later step needs. When a wizard / booking form / checkout consumes a slow server-prefetched promise via React `use()` at the top of the component, the entire tree suspends — blocking the first interactive step behind data it doesn't use yet. Use when a server-passed promise is consumed with top-level `use()`, when the first step shows a full-screen skeleton while a slow upstream (availability, search, recommendations) resolves, or when a "loading" bug and an unrelated-looking post-load "snap"/re-render appear together.
---

# Stream Behind the First Step

## When This Skill Activates

- A multi-step client flow (wizard, booking form, checkout, onboarding) is fed a slow server-prefetched promise and consumes it with `use(promise)` at the **top** of the component
- The first interactive step (a form, a contact-details panel, an intro screen) shows a full-screen skeleton while a slow upstream resolves — even though that step doesn't use the data
- The data is only needed at step 2+ (a calendar grid, a results list, a recommendation panel)
- Someone reports a "double load" / "it flashes" / "the times jump after it loads" right after the page finally appears
- You're about to wrap the whole page in `<Suspense>` because one slow fetch is somewhere inside it

## The One Question

> **Is the first interactive step blocked on data that only a later step needs?**

If yes, you have a priority inversion. Resolve the data in the background and let the first step paint now; gate only the step that actually consumes it.

## Why This Matters

Server Components let you start a slow fetch at request time and hand the in-flight promise to a client component. The idiomatic consumer is `use(promise)`. But `use()` **suspends the component that calls it** up to the nearest `<Suspense>` boundary. Put it at the top of a multi-step orchestrator and you suspend *everything* — including the steps that don't need the data.

That's a priority inversion. In a form-first flow the user spends 10–60 seconds on step 1 (typing name, email, answers). The slow data (availability, search results, recommendations) is needed only when they reach step 2. The fetch is *already running in the background*. The only thing you control is **when you block on it** — and blocking up-front trades the one window where the latency would be invisible (the user is busy) for a dead-looking skeleton.

There's a second, sneakier cost. **`use()` suspends a component's effects too.** A suspended component never commits, so its mount effects don't run until the promise resolves. Effects you assumed run "on load" — timezone/locale detection, analytics init, autofocus — actually fire only *after* the slow data lands. The result: the page paints with default state, then immediately re-renders when the deferred effects finally run. That reads as a "double load" or a "the times snapped to my timezone after it loaded" bug — which looks unrelated to the loading problem but has the *same* root cause. Move the wait out and both symptoms disappear together.

## Decision Tree

```
Is a slow server-prefetched promise consumed via use() at the top of the component?
  NO  → fine.
  YES → Continue.

Does the FIRST interactive step actually need that data to render?
  YES → keep it; the wait is unavoidable. (Consider a skeleton that matches the step.)
  NO  → priority inversion. Continue.

Pick how to defer the block:
  A. Resolve in the background (effect → state). Component renders now;
     data streams into state; later step reads it. Simplest; keeps one fetch.
  B. Push the use()/<Suspense> boundary DOWN to wrap only the subtree that
     needs the data, with a localized stencil. Use when the later step is a
     clean, separable subtree.

At the step → step transition, where do you read the data?
  From the closed-over memo → BUG in the tail (user advances before fetch
      settles → memo is still empty → "no results").
  From a freshly AWAITED snapshot → correct. Derive the transition from the
      awaited value, via a pure helper shared with the steady-state render.
```

## Core Rules

### Rule 1: Don't `use()` a slow promise at the top of a multi-step component

```tsx
// ✗ WRONG — suspends the whole wizard (including step 1) on step-2 data
function BookingWizard({ slotsPromise }: Props) {
  const slots = use(slotsPromise);   // 🔴 entire component waits 2–15s
  // ...form, calendar, confirm all live below this line
}
```

Top-level `use()` is correct only when the *first thing the user sees* genuinely needs the data.

### Rule 2: Resolve in the background so step 1 paints immediately

```tsx
// ✓ Option A — background effect → state; component never suspends
function BookingWizard({ slotsPromise }: Props) {
  const [slots, setSlots] = useState<Slots | null>(null);
  useEffect(() => {
    let active = true;
    // Promise.resolve() + two-arg then — NOT `.then().catch()`. See the
    // RSC-thenable trap below: a server-passed promise is a minimal thenable
    // whose `.then()` returns undefined, so chaining `.catch` throws in prod.
    Promise.resolve(slotsPromise).then(
      (r) => { if (active) setSlots(r); },
      () => { if (active) setSlots(null); }, // defensive; treat as empty
    );
    return () => { active = false; };
  }, [slotsPromise]);

  // Step 1 (form) renders NOW with slots === null. Step 2 reads `slots`
  // once it arrives, behind a localized stencil.
}
```

> **⚠️ RSC-thenable trap (the way this bites in production).** A promise passed
> from a Server Component to a Client Component does **not** arrive as a normal
> `Promise`. It's React's minimal "usable" thenable: it implements
> `then(onFulfilled, onRejected)` but `.then()` returns `undefined`, so
> `slotsPromise.then(...).catch(...)` reads `.catch` on `undefined` and throws
> **`Cannot read properties of undefined (reading 'catch')`** — crashing the page
> into its error boundary. It passes every unit test and Storybook story, because
> those inject a real `Promise` (whose `.then()` *does* return a chainable
> promise). Two safe forms: **`Promise.resolve(promise).then(onF, onR)`** (no
> `.catch` chain), or just **`use(promise)`** inside a pushed-down `<Suspense>`
> (Option B), which consumes the thenable natively. `await promise` is also safe
> (it calls the two-arg `then` internally). **Verify on a running dev server, not
> just the test suite** — the dev server serializes the real RSC thenable; jsdom
> tests do not, so this class of bug is invisible to green CI.

```tsx
// ✓ Option B — push the boundary down to only the subtree that needs it
<FormStep ... />                              {/* renders immediately */}
{phase === "results" && (
  <Suspense fallback={<ResultsStencil />}>
    <ResultsStep slotsPromise={slotsPromise} /> {/* this subtree calls use() */}
  </Suspense>
)}
```

### Rule 3: At the transition, derive from the AWAITED snapshot — not the closed-over memo

The dangerous tail case: the user finishes step 1 *before* the fetch settles. The steady-state memo (`derivedFromState`) is still empty, so a transition that reads it routes the user into a false "nothing available" state.

```tsx
// ✓ The transition awaits the freshest value and derives from THAT
async function handleStepOneComplete(data: FormData) {
  await saveStep(data);
  const fresh = await resolveSlots();          // awaits the same in-flight promise
  const dates = deriveAvailableDates(fresh);   // pure helper, see Rule 4
  setSelectedDate(dates[0] ?? null);
  setPhase(dates.length ? "results" : "empty");
}
```

Awaiting an already-in-flight promise is instant once it has settled (the common case, because step 1 took longer than the fetch). It only truly waits in the rare tail — exactly when you need it to.

### Rule 4: One source of truth for the derivation (memo == transition)

Extract the "raw data → view shape" step into a pure function and call it from *both* the steady-state memo and the transition. Otherwise the two drift and the transition preselects a date the grid then can't show.

```tsx
// pure, unit-testable, zero React
export function deriveAvailableDates(slots: Slot[], tz: string): string[] { /* ... */ }

const availableDates = useMemo(            // steady-state render
  () => deriveAvailableDates(slots ?? [], tz), [slots, tz]);
// handleStepOneComplete (above) calls the SAME helper on the awaited snapshot
```

### Rule 5: Keep it a single upstream call

The background resolver (Rule 2) and the transition resolver (Rule 3) **await the same promise**. Do not add a client-side refetch — that reintroduces a second call to the slow upstream (and the classic empty-then-refetch double-call bug). One server-created promise, many awaiters.

### Rule 6: Know that `use()` defers effects — and that moving the wait fixes the "snap"

If the suspended component owned a mount effect (timezone/locale detection, analytics, autofocus), that effect was firing *after* the data landed, causing a visible re-render. Once the component renders immediately (Rule 2), the effect runs during step 1 — before any data-dependent UI is shown — so the "snap" is gone for free. When you see a "double load" near a top-level `use()`, suspect deferred effects, not a second fetch.

## Implementation Pattern

```
WizardOrchestrator (client)
├── useState(prefetched → null)         # background resolve, no suspend
├── useEffect(promise.then(setState))   # Rule 2
├── resolveFresh = () => promise        # Rule 3 (awaited at transition)
├── deriveViewShape(raw)                # Rule 4 (pure, shared)
└── <Step1 .../>  → <Step2 reads state, localized stencil />
```

Server side is unchanged: keep firing the prefetch at request time so the fetch gets its earliest possible head start and runs during the user's dwell on step 1.

## Anti-Patterns

### ✗ Top-level `use()` "because that's the idiomatic way to read a server promise"

Idiomatic ≠ correctly placed. `use()` belongs at the boundary of the subtree that needs the value, not at the root of a multi-step orchestrator.

### ✗ Wrapping the whole page in one `<Suspense>` with a full-screen skeleton

That just relocates the same block. The skeleton now covers the form the user could be filling. Gate the *step*, not the *page*.

### ✗ Transition reads the closed-over memo

```tsx
async function onStepComplete() {
  await save();
  const dates = availableDatesMemo;   // 🔴 empty in the tail → "no availability"
  setPhase(dates.length ? "results" : "empty");
}
```

### ✗ `.then(...).catch(...)` on the server-passed promise

```tsx
useEffect(() => {
  slotsPromise.then(setSlots).catch(() => setSlots(null)); // 🔴 ".then()" returns
  // undefined on React's RSC thenable → ".catch" of undefined → throws in prod,
  // passes every test (tests pass a real Promise). Use Promise.resolve(...).then(onF, onR).
}, [slotsPromise]);
```

### ✗ "Fix" the latency with a client-side refetch

```tsx
useEffect(() => { fetchSlots().then(setSlots); }, []);  // 🔴 second upstream call
```

You already have the in-flight server promise. Await it; don't re-request.

### ✗ Assuming mount effects ran while the component was suspended

```tsx
const data = use(slowPromise);   // suspends
useEffect(() => detectTimezone(), []);  // 🔴 doesn't run until `data` resolves
```

## Audit Checklist

Reviewing a multi-step client flow fed by a server-prefetched promise:

- [ ] No `use(slowPromise)` at the top of a multi-step orchestrator
- [ ] The first interactive step renders without waiting on later-step data
- [ ] Later step reads the data from state (background-resolved) or behind a pushed-down `<Suspense>` with a *localized* stencil
- [ ] The step→step transition derives from a freshly **awaited** snapshot, not a closed-over memo
- [ ] A single pure helper computes the view shape for both the steady-state memo and the transition
- [ ] Exactly one upstream call — no client-side refetch
- [ ] The server-passed promise is consumed via `use()` or `Promise.resolve(p).then(onF, onR)` / `await` — never `p.then(...).catch(...)` (RSC thenable has no chainable `.then`)
- [ ] Mount effects (timezone/locale/analytics/focus) verified to run during step 1, not after the data lands
- [ ] **Verified on a running dev server, not just unit tests** — the dev server serializes the real RSC thenable; jsdom tests inject a plain `Promise` and miss thenable-shape bugs
- [ ] Tail case covered by a test: step 1 completed before the fetch settles → still routes correctly

## Generalizes To

| Multi-step flow | Step 1 (paint now) | Later step (gate on data) | Slow upstream |
|---|---|---|---|
| Booking / scheduling | Prequalification form | Calendar + time slots | Availability API |
| Checkout | Shipping / contact | Rate quotes, tax, ETA | Carrier / tax API |
| Search wizard | Query + filters builder | Results grid | Search backend |
| Onboarding | Profile form | Personalized recommendations | Recsys |
| Config wizard | Field inputs | Live preview / validation | Render / validate service |

Whenever step 1 is interactive and step N needs the slow data, the user's dwell on step 1 *is* the latency-hiding window. Don't spend it on a skeleton.

## Related Patterns

- **Server Component first** — fire the prefetch at request time; pass the in-flight promise down. The point of this skill is *where* you consume it, not whether you prefetch.
- **`key`-based remount** — if a later step needs local state reset when its identity prop changes, remount via `key=` rather than syncing prop→state in an effect.
- **Localized skeletons** — the stencil should match the *step* it replaces, not the whole page.

## Origin

Extracted from a slow-embedded-booking-widget incident. A customer reported the widget "took forever to load." The trace showed a ~6.5s document load and an even longer tail. The widget was a form-first wizard, but the client orchestrator called `use(availabilityPromise)` at the top — suspending the entire scheduler (branding, header, and the form) behind a scheduling-availability fetch that fans out free/busy queries per participant (seconds, not milliseconds). The slot grid was *disabled during the form phase anyway*, so users were forced to wait up-front for data they couldn't use until after the step they hadn't started.

The same top-level `use()` also explained a separate "the times jump after it loads" report: the timezone-detection effect couldn't run until the component un-suspended, so the calendar first painted in the link's default timezone and then snapped to the visitor's — a "double load" with the *same* root cause. Resolving availability in the background (effect → state) made the form interactive in under a second, hid the upstream latency behind the form-fill window, and removed the timezone snap for free. The lesson beyond the API: **you usually can't make the upstream faster — but you can move *when* the user waits to a moment they're already busy.**
