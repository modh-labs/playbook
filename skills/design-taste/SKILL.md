---
name: design-taste
description: Premium UI/UX design engineering skill. Overrides default LLM design biases with tunable dials for variance, motion, and density. Enforces anti-AI-tell patterns, strict typography rules, color calibration, layout diversification, performance guardrails, and comprehensive design audit checklists. Framework-agnostic.
tier: universal
icon: palette
title: "Premium UI Design Engineering"
seo_title: "Design Taste Skill — Premium UI Patterns That Override AI Defaults"
seo_description: "Override default AI design biases with tunable dials for variance, motion, density, and color. Detect and eliminate generic AI aesthetic patterns."
keywords: ["UI design", "design engineering", "AI design patterns", "premium UI"]
difficulty: advanced
related_chapters:
  - "07-frontend-craft/design-standards"
  - "07-frontend-craft/component-architecture"
related_tools:
  - "engineering-health-check"
---

# Design Taste

A consolidated design engineering skill that combines tunable generation controls, bias-correcting directives, forbidden AI patterns, performance guardrails, and a structured audit checklist. Works with any frontend stack.

---

## 1. Tunable Dials

Three global parameters control all generation. Defaults below. Adapt dynamically when the user requests a different feel -- never ask the user to edit this file.

| Dial | Default | Scale |
|------|---------|-------|
| **DESIGN_VARIANCE** | 8 | 1 = Perfect Symmetry ... 10 = Artsy Chaos |
| **MOTION_INTENSITY** | 6 | 1 = Static / No movement ... 10 = Cinematic / Magic Physics |
| **VISUAL_DENSITY** | 4 | 1 = Art Gallery / Airy ... 10 = Pilot Cockpit / Packed Data |

### DESIGN_VARIANCE Breakdown

| Range | Behavior |
|-------|----------|
| 1-3 (Predictable) | Flexbox `justify-center`, strict 12-column symmetrical grids, equal paddings. |
| 4-7 (Offset) | Overlapping with negative margins, varied image aspect ratios (4:3 next to 16:9), left-aligned headers over centered data. |
| 8-10 (Asymmetric) | Masonry layouts, CSS Grid with fractional units (`grid-template-columns: 2fr 1fr 1fr`), massive empty zones (`padding-left: 20vw`). |

**Mobile override:** For levels 4-10, any asymmetric layout above `md:` MUST fall back to a strict single-column layout (`w-full`, `px-4`, `py-8`) on viewports < 768px.

### MOTION_INTENSITY Breakdown

| Range | Behavior |
|-------|----------|
| 1-3 (Static) | No automatic animations. CSS `:hover` and `:active` states only. |
| 4-7 (Fluid CSS) | `transition: all 0.3s cubic-bezier(0.16, 1, 0.3, 1)`. `animation-delay` cascades for load-ins. Strictly `transform` and `opacity`. |
| 8-10 (Advanced Choreography) | Scroll-triggered reveals, parallax, physics-based animation libraries. NEVER use `window.addEventListener('scroll')`. |

### VISUAL_DENSITY Breakdown

| Range | Behavior |
|-------|----------|
| 1-3 (Art Gallery) | Lots of white space. Huge section gaps. Feels expensive and clean. |
| 4-7 (Daily App) | Normal spacing for standard web apps. |
| 8-10 (Cockpit) | Tiny paddings. 1px lines to separate data. No card boxes. Monospace (`font-mono`) for all numbers. |

---

## 2. Architecture and Convention Constraints

Unless the user specifies a different stack, enforce these structural rules:

- **Dependency verification [mandatory].** Before importing ANY third-party library, check the project's dependency file (`package.json`, `Cargo.toml`, `pyproject.toml`, etc.). If missing, output the install command before providing code. Never assume a library exists.
- **Framework and interactivity.** Default to server-rendered components where the framework supports it (e.g., RSC in Next.js, `.astro` in Astro). Interactive components must be explicitly isolated as client-side leaf components.
- **State management.** Use local component state for isolated UI. Use global state strictly for deep prop-drilling avoidance.
- **Styling.** Use the project's existing CSS approach (Tailwind, vanilla CSS, styled-components, etc.). If Tailwind, check the version (v3 vs v4) before writing config or utility classes. For v4, do NOT use the `tailwindcss` plugin in `postcss.config.js` -- use `@tailwindcss/postcss` or the Vite plugin.
- **Anti-emoji policy [critical].** NEVER use emojis in code, markup, text content, or alt text. Replace with high-quality icons (Phosphor, Radix, Heroicons) or clean SVG primitives.
- **Responsiveness.** Standardize breakpoints. Contain page layouts with a max-width (1200-1440px) and auto margins. Use `min-h-[100dvh]` instead of `h-screen` for full-height sections (iOS Safari viewport bug). Use CSS Grid over complex flexbox percentage math.
- **Icons.** Standardize `strokeWidth` globally (e.g., exclusively 1.5 or 2.0). Use a single icon library across the project.

---

## 3. Design Engineering Directives (Bias Correction)

LLMs have statistical biases toward specific UI cliches. These engineered rules proactively override them.

### Rule 1: Deterministic Typography

- **Display/Headlines:** Large, tight tracking, minimal line-height (e.g., `text-4xl md:text-6xl tracking-tighter leading-none`).
- **Anti-slop:** Discourage `Inter` for premium or creative contexts. Force unique character using `Geist`, `Outfit`, `Cabinet Grotesk`, or `Satoshi`.
- **Technical UI rule:** Serif fonts are BANNED for dashboard/software UIs. Use high-end sans-serif pairings (`Geist` + `Geist Mono`, `Satoshi` + `JetBrains Mono`).
- **Body/Paragraphs:** Readable defaults -- `text-base`, muted color, `leading-relaxed`, max-width ~65 characters.
- **Weight spectrum.** Go beyond Regular (400) and Bold (700). Introduce Medium (500) and SemiBold (600) for subtle hierarchy.
- **Tabular numbers.** Use monospace or `font-variant-numeric: tabular-nums` for data-heavy interfaces.
- **Orphans.** Fix with `text-wrap: balance` or `text-wrap: pretty`.

### Rule 2: Color Calibration

- **Constraint:** Max 1 accent color. Saturation < 80%.
- **The Lila Ban:** The "AI Purple/Blue" gradient aesthetic is BANNED. No purple button glows, no neon gradients. Use neutral bases (Zinc/Slate) with a singular high-contrast accent (Emerald, Electric Blue, Deep Rose).
- **Consistency:** One palette for the entire output. Do not fluctuate between warm and cool grays.
- **Shadows:** Tint shadows to match the background hue. Use colored shadows, not generic black at low opacity.
- **No pure black.** Never use `#000000`. Use off-black, Zinc-950, or tinted charcoal (`#0a0a0a`, `#121212`).

### Rule 3: Layout Diversification

- **Anti-center bias:** Centered Hero/H1 sections are BANNED when `DESIGN_VARIANCE > 4`. Force split-screen (50/50), left-aligned content with right-aligned asset, or asymmetric whitespace.
- **Anti-symmetry:** Break uniformity with offset margins, mixed aspect ratios, or left-aligned headers over centered content.
- **Depth.** Use negative margins and overlap to create layering. Flat side-by-side elements feel generic.

### Rule 4: Materiality and Anti-Card Overuse

- **Dashboard hardening:** For `VISUAL_DENSITY > 7`, generic card containers are BANNED. Use `border-t`, `divide-y`, or negative space. Data metrics breathe without being boxed.
- **Execution:** Use cards ONLY when elevation communicates hierarchy. When using a shadow, tint it to the background hue.
- **Surfaces:** Go beyond `backdrop-blur` for glassmorphism. Add a 1px inner border and subtle inner shadow for physical edge refraction.

### Rule 5: Interactive UI States

LLMs naturally generate static "success" states. You MUST implement full interaction cycles:

| State | Requirement |
|-------|-------------|
| Loading | Skeleton loaders matching layout shape. No generic circular spinners. |
| Empty | Composed "getting started" view. Never a blank page. |
| Error | Clear, inline error messages. No `window.alert()`. |
| Hover | Background shift, slight scale, or translate. Never bare. |
| Active/Pressed | `scale(0.98)` or `translateY(1px)` for tactile physical-push feedback. |
| Focus | Visible focus ring for keyboard navigation. Accessibility requirement. |
| Disabled | Visually distinct. Dead links (`href="#"`) must be disabled or removed. |

### Rule 6: Data and Form Patterns

- Labels MUST sit above inputs. Helper text optional. Error text below. Standard `gap-2` for input blocks.
- Add client-side validation for emails, required fields, and format checks.

### Rule 7: Creative Proactivity (Anti-Slop)

When `MOTION_INTENSITY > 5`:

- Embed continuous micro-animations (Pulse, Typewriter, Float, Shimmer) in standard components. Apply spring physics (`type: "spring", stiffness: 100, damping: 20`) -- no linear easing.
- Implement magnetic buttons that pull toward the cursor. CRITICAL: Never use `useState` for continuous animations. Use motion values outside the render cycle.
- Use `layout` and `layoutId` props for smooth re-ordering and shared element transitions.
- Stagger list/grid entry with cascading delays. Never mount everything at once.

---

## 4. AI Tells -- Forbidden Patterns

These are the most common fingerprints of AI-generated design. Avoid them strictly unless the user explicitly requests one.

### Visual and CSS

| Banned Pattern | Replacement |
|----------------|-------------|
| Neon / outer glows | Inner borders or subtle tinted shadows |
| Pure `#000000` | Off-black, Zinc-950, tinted charcoal |
| Oversaturated accents | Desaturate to blend with neutrals |
| Gradient text on large headers | Solid color with weight/tracking for emphasis |
| Custom mouse cursors | Remove. They ruin performance and accessibility. |
| Purple/blue "AI gradient" | Neutral base + single considered accent |
| Flat sections with zero texture | Subtle noise, grain, micro-patterns, or ambient gradients |
| Perfectly even linear gradients | Radial gradients, noise overlays, or mesh gradients |
| Inconsistent lighting direction | Audit all shadows for a single light source |
| Random dark section in a light page | Consistent tone throughout; use a darker shade, not a jump to `#111` |

### Typography

| Banned Pattern | Replacement |
|----------------|-------------|
| Inter font everywhere | `Geist`, `Outfit`, `Cabinet Grotesk`, or `Satoshi` |
| Oversized screaming H1s | Control hierarchy with weight and color, not just scale |
| Serif on dashboards | Sans-serif only for software/data UIs |
| Only 400/700 weights | Add 500 and 600 for subtle hierarchy |
| All-caps subheaders everywhere | Lowercase italics, sentence case, or small-caps |
| Missing letter-spacing | Negative tracking on large headers, positive on labels |

### Layout and Spacing

| Banned Pattern | Replacement |
|----------------|-------------|
| 3 equal card columns as feature row | 2-column zig-zag, asymmetric grid, horizontal scroll, or masonry |
| Everything centered and symmetrical | Offset margins, mixed aspect ratios, left-aligned headers |
| `h-screen` for full-height sections | `min-h-[100dvh]` |
| Complex flexbox percentage math | CSS Grid |
| Cards of equal forced height | Variable heights or masonry when content varies |
| Uniform border-radius everywhere | Tighter on inner elements, softer on containers |
| Dashboard always has left sidebar | Try top nav, command menu, or collapsible panel |
| Buttons misaligned in card groups | Pin buttons to card bottom for consistent horizontal line |

### Content and Data ("Jane Doe" Effect)

| Banned Pattern | Replacement |
|----------------|-------------|
| "John Doe", "Jane Smith" | Creative, diverse, realistic-sounding names |
| Generic SVG egg avatars | Photo placeholders or styled initials |
| Round numbers (`99.99%`, `50%`) | Organic data (`47.2%`, `$1,247.83`) |
| "Acme Corp", "SmartFlow" | Contextual, believable brand names |
| "Elevate", "Seamless", "Unleash" | Concrete verbs and specific language |
| Lorem Ipsum | Real draft copy |
| Same avatar for multiple users | Unique asset per person |
| Identical blog post dates | Randomized realistic dates |
| Title Case On Every Header | Sentence case |
| "Oops!" error messages | Direct: "Connection failed. Please try again." |
| Exclamation marks in success messages | Confident, not loud |

### Components

| Banned Pattern | Replacement |
|----------------|-------------|
| Generic card (border + shadow + white bg) | Use spacing, background color only, or remove border |
| Always one filled + one ghost button | Add text links or tertiary styles |
| Pill "New"/"Beta" badges | Square badges, flags, or plain text |
| Accordion FAQ | Side-by-side list, searchable help, or inline disclosure |
| 3-card carousel testimonials with dots | Masonry wall, embedded posts, or single rotating quote |
| Modals for everything | Inline editing, slide-over panels, or expandable sections |
| Avatar circles exclusively | Squircles or rounded squares |
| Pricing table with 3 identical towers | Highlight recommended tier with color/emphasis |
| Footer link farm with 4 columns | Simplified, focused on main paths and legal links |

### Icons and Assets

| Banned Pattern | Replacement |
|----------------|-------------|
| Lucide/Feather exclusively | Phosphor, Heroicons, or custom set |
| Rocketship for "Launch", shield for "Security" | Less obvious metaphors (bolt, fingerprint, spark, vault) |
| Inconsistent stroke widths | Audit and standardize to one weight |
| Missing favicon | Always include a branded favicon |
| Stock "diverse team" photos | Real photos, candids, or consistent illustration style |
| Unsplash links (often broken) | `https://picsum.photos/seed/{name}/800/600` or SVG avatars |

---

## 5. Performance Guardrails

| Rule | Detail |
|------|--------|
| DOM cost | Grain/noise filters go on fixed, `pointer-events-none` pseudo-elements. Never on scrolling containers. |
| Hardware acceleration | Never animate `top`, `left`, `width`, or `height`. Use `transform` and `opacity` exclusively. |
| Z-index restraint | Use z-index only for systemic layers (sticky navbars, modals, overlays). Never spam arbitrary values. |
| Animation isolation | Perpetual/infinite animations MUST be memoized and isolated in their own microscopic client component. Never trigger parent re-renders. |
| Animation cleanup | All `useEffect` animations must contain strict cleanup functions. |
| Scroll listeners | Use Intersection Observer or animation library hooks. Never raw `window.addEventListener('scroll')`. |
| `will-change` | Use sparingly and only on elements actively animating. |

---

## 6. Quick Audit Checklist

When reviewing an existing project, run through this fast scan. For the full deep-dive, see `references/design-audit.md`.

### Scan

1. Read the codebase. Identify the framework, styling method, and current patterns.
2. Run through the checks below. List every generic pattern, weak point, and missing state.
3. Apply targeted upgrades working with the existing stack. Do not rewrite from scratch.

### Fast Checks

- [ ] Font is NOT Inter/system default -- has real character
- [ ] Max 1 accent color, saturation < 80%, no AI purple/blue
- [ ] No pure `#000000` anywhere
- [ ] Shadows are tinted, not generic black
- [ ] No 3-column equal card layout
- [ ] Layout breaks symmetry (offset, overlap, asymmetry)
- [ ] Full-height sections use `min-h-[100dvh]`, not `h-screen`
- [ ] Every interactive element has hover + active + focus states
- [ ] Loading, empty, and error states exist
- [ ] No generic names, round numbers, or Lorem Ipsum
- [ ] No AI copywriting cliches
- [ ] Semantic HTML (`nav`, `main`, `article`, `aside`, `section`)
- [ ] All imports exist in dependency file
- [ ] Mobile layout collapses correctly (single column, no horizontal scroll)
- [ ] Custom 404 page exists
- [ ] Form validation present (client-side)
- [ ] `alt` text on all meaningful images
- [ ] Meta tags present (`title`, `description`, `og:image`)
- [ ] No commented-out dead code

---

## 7. Fix Priority

When upgrading an existing project, apply changes in this order for maximum visual impact with minimum risk:

| Priority | Change | Rationale |
|----------|--------|-----------|
| 1 | Font swap | Biggest instant improvement, lowest risk |
| 2 | Color palette cleanup | Remove clashing or oversaturated colors |
| 3 | Hover and active states | Makes the interface feel alive |
| 4 | Layout and spacing | Proper grid, max-width, consistent padding |
| 5 | Replace generic components | Swap cliche patterns for modern alternatives |
| 6 | Add loading, empty, error states | Makes it feel finished |
| 7 | Polish typography scale and spacing | The premium final touch |

### Rules for Upgrades

- Work with the existing tech stack. Do not migrate frameworks or styling libraries.
- Do not break existing functionality. Test after every change.
- Before importing any new library, check the dependency file first.
- Keep changes reviewable and focused. Small, targeted improvements over big rewrites.

---

## 8. Pre-Flight Checklist

Evaluate output against this matrix before delivering. This is the last filter.

- [ ] Is global state used only to avoid deep prop-drilling, not arbitrarily?
- [ ] Is mobile layout collapse guaranteed for high-variance designs?
- [ ] Do full-height sections use `min-h-[100dvh]`?
- [ ] Do `useEffect` animations contain cleanup functions?
- [ ] Are empty, loading, and error states provided?
- [ ] Are cards omitted in favor of spacing where possible?
- [ ] Are CPU-heavy perpetual animations isolated in their own client components?
- [ ] Does every import resolve to an actual installed package?
- [ ] Is there zero Lorem Ipsum, zero emoji, zero `#000000`?

---

## References

- **Creative Arsenal** -- advanced UI patterns, motion engine, upgrade techniques: `references/creative-arsenal.md`
- **Design Audit** -- comprehensive checklist for reviewing existing projects: `references/design-audit.md`
