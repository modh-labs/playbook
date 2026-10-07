---
name: header-yields-to-task-surface
description: 'A header that hides on scroll down and comes back on scroll up must stay hidden while the page''s main task surface (an embedded scheduler, checkout, form or player) sits under it. It measures where it would rest, ignoring its own hide transform, and checks for overlap with marked elements on each scroll. Also: how to test "stays hidden" against a scroll handler throttled to animation frames. Use when building or fixing a hide-on-scroll or auto-hide header, when a sticky or floating header covers a form, iframe or embed after scrolling up, when an anchor jump lands content under the header, or when writing a Playwright test that asserts something does NOT appear after a scroll.'
---

# Header Yields to the Task Surface

## When This Skill Activates
- Building or changing a hide-on-scroll, auto-hide, headroom or "smart" sticky header.
- A floating header slides back over a form, embedded iframe, checkout or video when the user scrolls up a little.
- A landing page's whole job is one embedded surface (booking scheduler, payment form, application form) and something else on the page competes with it for the top of the viewport.
- Writing a browser test that asserts an element stays hidden, or did not appear, after a scroll.

## The One Question
> "When this header comes back, what does it land on, and does the user need the header more than that?"

On a page built around one task, the answer is almost always no. The header's only button usually scrolls to the very surface it is covering.

## Why It Breaks
The usual hide-on-scroll rule has one input: scroll direction. Down hides, up reveals, near the top always shows. Direction says nothing about what is under the header.

Users filling in a long embedded form scroll up a few lines to re-read a field. Each small upward scroll reveals the header, which sits over the top of the form: its step indicator, its first field, its heading. A layout shift can do the same with no user scroll at all: an embed that reports a smaller height clamps the page's scroll position upward, and the handler reads that as "scrolled up".

Adding `scroll-margin-top` to the target does not help. It changes where an anchor jump lands, not what the header does on the next scroll.

## Decision Tree
```
Header about to reveal (user scrolled up past the threshold)?
├── Near the top of the page (scrollY <= reveal offset)?
│     └── SHOW. Nothing important is under it yet.
├── Does any marked task surface overlap the header's RESTING band?
│     └── STAY HIDDEN. Record the scroll position so the next
│         movement is measured from here.
└── Otherwise
      └── Normal direction rule: up shows, down hides.

Keyboard focus inside the header?
└── SHOW, always. Focus beats every scroll rule.
```

## Core Rules

### 1. Measure the resting band, not the current box
The header is usually hidden with a transform (`translateY(-100%)`). `getBoundingClientRect()` returns the transformed box, so a hidden header reports a band above the viewport and never overlaps anything. Use the layout values, which ignore transforms:

```ts
// CORRECT: where the header sits when shown, whatever it is doing now
const bandBottom = header.offsetTop + header.offsetHeight;

// WRONG: a hidden header's rect is off-screen, so the check never fires
const bandBottom = header.getBoundingClientRect().bottom;
```

For a `position: fixed` header, `offsetParent` is null and `offsetTop` is measured from the viewport, which is what you want.

### 2. Mark task surfaces declaratively
The header should not know which pages have a scheduler. Select by an attribute the surface already carries, or add one:

```ts
// CORRECT: any page that renders the embed gets the behaviour
const YIELD_TO_SELECTOR = "[data-booking-embed]";

// WRONG: a per-page prop the next page will forget
<Header hideOverBooking={pathname === "/book"} />
```

If an embed script already requires an attribute on its iframe, reuse that attribute. It cannot drift, because the embed breaks without it.

### 3. Check on every scroll frame, before the direction rule
```ts
function coversTaskSurface(header: HTMLElement | null) {
  if (!header) return false;
  const bandBottom = header.offsetTop + header.offsetHeight;
  for (const el of document.querySelectorAll(YIELD_TO_SELECTOR)) {
    const r = el.getBoundingClientRect();
    if (r.top < bandBottom && r.bottom > 0) return true;
  }
  return false;
}
```

`getBoundingClientRect()` on the target is correct here: the target is not transformed, and you want where it is on screen now.

### 4. Leave the other rules alone
The near-top reveal, the movement threshold, reduced-motion handling and "show while focused" all stay. The yield is one more condition, not a rewrite.

## Implementation Pattern (React)

```ts
interface Options {
  revealOffset?: number;
  delta?: number;
  headerRef?: RefObject<HTMLElement | null>;
}

export function useHideOnScroll({ revealOffset = 80, delta = 8, headerRef }: Options = {}) {
  const [visible, setVisible] = useState(true);
  const lastY = useRef(0);
  const frame = useRef<number | null>(null);

  useEffect(() => {
    lastY.current = window.scrollY;
    setVisible(lastY.current <= revealOffset);

    function update() {
      frame.current = null;
      const y = window.scrollY;
      const moved = y - lastY.current;

      if (y <= revealOffset) { lastY.current = y; setVisible(true); return; }

      if (coversTaskSurface(headerRef?.current ?? null)) {
        lastY.current = y;
        setVisible(false);
        return;
      }

      if (Math.abs(moved) < delta) return;
      lastY.current = y;
      setVisible(moved < 0);
    }

    function onScroll() {
      if (frame.current === null) frame.current = requestAnimationFrame(update);
    }

    window.addEventListener("scroll", onScroll, { passive: true });
    return () => {
      window.removeEventListener("scroll", onScroll);
      if (frame.current !== null) cancelAnimationFrame(frame.current);
    };
  }, [revealOffset, delta, headerRef]);

  return visible;
}

export function StickyHeader({ children }: { children: ReactNode }) {
  const ref = useRef<HTMLElement>(null);
  const scrolledVisible = useHideOnScroll({ headerRef: ref });
  const [focused, setFocused] = useState(false);
  const visible = scrolledVisible || focused;
  return (
    <header
      ref={ref}
      className={visible ? "translate-y-0" : "-translate-y-[calc(100%+2rem)]"}
      onFocusCapture={() => setFocused(true)}
      onBlurCapture={() => setFocused(false)}
    >
      {children}
    </header>
  );
}
```

## Testing It: A Negative Assertion That Can Fail

The scroll handler runs on the next animation frame, and the framework commits after that. A test that scrolls and immediately checks "header is hidden" reads the state from BEFORE the handler ran. It passes whether or not the fix exists.

```ts
// WRONG: passes on the broken code. The read beats the handler.
await page.evaluate((y) => window.scrollTo(0, y), schedulerTop + 200);
await expect(header).toHaveClass(/-translate-y-/);

// ALSO WRONG: a retrying assertion on a negative state passes on its first
// try, before the bad state arrives. waitForTimeout only guesses.
```

Wait for the real scroll event, then the frame the handler runs in, then one more frame and a task for the commit. Read the state once, without retrying:

```ts
const scrollAndSettle = (y: number) =>
  page.evaluate((target) => new Promise<void>((resolve) => {
    window.addEventListener("scroll", () =>
      requestAnimationFrame(() => requestAnimationFrame(() => setTimeout(resolve, 0))),
      { once: true });
    window.scrollTo(0, target);
  }), y);

const isHidden = () => header.evaluate((el) => el.className.includes("-translate-y-"));

await scrollAndSettle(schedulerTop + 300);
expect(await isHidden()).toBe(true);
await scrollAndSettle(schedulerTop + 200);   // scroll UP, still over the scheduler
expect(await isHidden()).toBe(true);
await scrollAndSettle(schedulerTop - 300);   // above the scheduler
expect(await isHidden()).toBe(false);
```

The listener is added after the app's listener, so its frame callback queues after the handler's. The positive check at the end proves the harness can see a reveal at all.

Run the test against the unfixed code first and watch it fail. A negative test that has never failed has not shown it can.

If the embed builds its address after hydration, wait for the frame to exist (`locator.waitFor({ state: "attached" })`) before deciding to skip. Counting it right after `goto` skips the test silently.

## Anti-Patterns
- **Hiding the header for the whole page** because one section has a form. Navigation still matters elsewhere.
- **A fixed pixel band** (`top < 90`). The header's height changes with breakpoints and content. Measure it.
- **`getBoundingClientRect()` on the header.** It reads the hidden position. See rule 1.
- **Per-route flags** for which pages yield. The next page with an embed will not have one.
- **Raising the embed's z-index over the header.** The header still hides the iframe's top, now with a gap, and focus order breaks.
- **`scroll-margin-top` as the fix.** It only changes where anchor jumps land.
- **Testing with `waitForTimeout` or a retrying `toHaveClass`** for a state that must NOT appear.

## Audit Checklist
- [ ] Does the hide-on-scroll logic consult anything besides scroll direction?
- [ ] Is every embedded task surface (scheduler, checkout, application form, player) selectable by one stable attribute?
- [ ] Does the overlap check use the header's layout box (`offsetTop + offsetHeight`), not its transformed rect?
- [ ] Does keyboard focus inside the header still force it visible?
- [ ] Is there a browser test that scrolls up inside the surface and asserts the header stays hidden, and was it seen failing before the fix?
- [ ] Does that test wait for the scroll event and the following frames, and read state once?
- [ ] Does a second assertion prove the header still reveals above the surface?
