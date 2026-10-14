---
name: print-report-pagination
description: >
  Paginate multi-page PDFs generated from HTML or markdown (Puppeteer,
  Playwright, wkhtmltopdf, weasyprint, react-pdf print CSS) by what you FORBID
  from breaking, not where you force breaks. Let long unboxed prose flow across
  pages; never split a boxed element, orphan a heading, or cut a single bullet.
  Use when building any report/invoice/statement/export PDF, when a generated
  PDF has half-cards or stranded headings at page edges, or when reviewing
  print/paged-media CSS.
---

# Print Report Pagination

Generating a multi-page PDF from HTML or markdown (Puppeteer/Playwright `page.pdf()`, wkhtmltopdf, weasyprint, react-pdf, or any print-CSS pipeline) is a **paged-media** problem, not a screen-layout problem. The browser engine flows content into fixed-height pages and breaks wherever it runs out of room. Your job is to constrain *where it is allowed to break*, not to manually place breaks.

## When This Skill Activates

- Building any report, invoice, statement, contract, or data export that renders to PDF
- A generated PDF shows a **card/callout/panel sliced across a page edge**, a **heading stranded at the bottom of a page** with its content on the next, or a **single bullet split in two**
- Converting a markdown document to PDF (weekly reports, changelogs, summaries) where section length is unpredictable
- Reviewing or writing any `@media print` / `@page` CSS

**Do NOT use for:** screen UI layout, on-screen scroll regions, or table row pagination (page-size/next-prev over a dataset — that is data pagination, a different problem). Screen design taste lives in design-taste / internal-tools-design.

## The One Question

> **What must NEVER straddle a page boundary?**

Answer that, apply `break-inside: avoid` to exactly those elements, and let everything else flow. You are writing a *forbid list*, not a *break-placement list*.

## The Core Principle

**Good pagination is defined by what you forbid from breaking, not where you force breaks.**

Manually forcing `break-before: page` between sections is the instinctive move and it is wrong: section length is data-dependent, so hand-placed breaks leave half-empty pages on short runs and still slice content on long runs. Instead, let long **unboxed** content (prose, a long list, a wide table) flow naturally across as many pages as it needs, and surgically forbid breaks only inside atomic visual units that look *broken* when split.

A half-card across a page edge reads as a rendering bug to the recipient. A paragraph that flows across a page edge reads as normal. That asymmetry is the whole skill.

## Decision Tree

```
For each element, ask: does it look BROKEN if a page edge cuts through it?

Is it a BOXED unit (card, callout, panel, alert, stat tile, signature block)?
  -> YES: break-inside: avoid   (never slice a box)

Is it a HEADING (h1-h6, section title)?
  -> YES: break-after: avoid    (never orphan it from its first content)
          + small break-inside: avoid on the heading+intro wrapper if needed

Is it a SINGLE list item / table row that is one logical unit?
  -> YES: break-inside: avoid   (never split one bullet or one row mid-cell)

Is it long UNBOXED flow content (prose, a long ul, a multi-screen table body)?
  -> NO forbid: let it flow across pages. Forcing a break here wastes paper
     and creates half-empty pages.
```

## Core Rules

### Rule 1 — Forbid, don't force

```css
/* WRONG: hand-placed breaks. Short sections leave half-empty pages;
   long sections still get sliced because the break is in the wrong spot. */
.section { break-before: page; }

/* RIGHT: let sections flow; forbid only what looks broken when split. */
.card, .callout, .panel, .stat-tile { break-inside: avoid; }
h1, h2, h3, h4 { break-after: avoid; }
li, tr { break-inside: avoid; }
```

`break-before: page` is legitimate for exactly one thing: a true new-chapter / cover-page boundary the document semantics demand (e.g. each invoice in a batch starts a fresh page). It is never a layout-tuning tool.

### Rule 2 — Never split a boxed element

Any element with a visible border, background, or shadow is *atomic*. Half of it on page 1 and half on page 2 looks like a crash. Apply `break-inside: avoid` to every boxed component class.

```css
/* RIGHT */
.metric-card, .info-box, .quote-block, .code-block, blockquote {
  break-inside: avoid;
}
```

Caveat: a box taller than the printable page height **cannot** be kept whole — the engine must break it. If a box can legitimately exceed one page (a long table inside a bordered panel), either let that inner content be unboxed, or accept the break. `break-inside: avoid` is a request the engine honors only when the box fits.

### Rule 3 — Never orphan a heading

A heading at the very bottom of a page with its body on the next page is the most common print defect. `break-after: avoid` glues a heading to whatever follows.

```css
/* RIGHT */
h1, h2, h3, h4, h5, h6 { break-after: avoid; }
```

For engines with weak `break-after` support, wrap heading + first paragraph in a `break-inside: avoid` container as a fallback.

### Rule 4 — Never split a single bullet or row

One bullet point or one table row is a single thought. Splitting it across pages is jarring. `break-inside: avoid` on `li` and `tr` (also repeat `thead` with `display: table-header-group` so headers reappear on each page).

```css
/* RIGHT */
li, tr { break-inside: avoid; }
thead { display: table-header-group; }
```

### Rule 5 — STRESS-TEST against a deliberately long render (the load-bearing method)

This is the rule everyone skips and the one that actually matters. A 2-page report with content ending halfway down page 2 **never exercises a single boundary** — every break landed in whitespace, so the PDF looks perfect and you ship broken pagination that detonates on the first real 4-page customer report.

**Force a 3–4+ page render where boxes, headings, and lists land *near* page edges, then inspect EVERY page boundary.**

How to force it:
- Duplicate the content blocks (or feed synthetic data) until the document is 3–4 pages.
- Or insert padding/`min-height` spacers before key elements so a card is pushed to ~95% down a page — exactly where a missing `break-inside: avoid` would slice it.
- Render the PDF and open it. Walk each page break: is any box halved? any heading stranded? any bullet cut? Fix, re-render, re-inspect until every boundary is clean.

Treat "renders fine on the short sample" as **untested**, not passing.

## Anti-Patterns

- **Hand-placing `break-before: page` between every section.** Data-dependent length makes this leave half-empty pages and still slice long content. Forbid bad breaks instead.
- **Testing only the happy-path short document.** The short render proves nothing; boundaries were never stressed. Always force a long render.
- **`break-inside: avoid` on a giant container** (the whole report body, a section that exceeds page height). The engine can't honor it, silently ignores it, and you get arbitrary slices. Scope `avoid` to small atomic units only.
- **Relying on legacy `page-break-*` alone.** Modern engines use `break-inside/before/after`; emit the modern properties (keep `page-break-*` as a fallback for old engines if you must, but lead with `break-*`).
- **Forgetting `thead { display: table-header-group }`** so a multi-page table loses its column headers after page 1.
- **Assuming `break-inside: avoid` is a guarantee.** It is a *preference* honored only when the element fits on a page; elements taller than the page still break.

## Audit Checklist

- [ ] No `break-before: page` except at genuine document/chapter/per-record boundaries.
- [ ] Every boxed class (border/background/shadow) has `break-inside: avoid`.
- [ ] All headings have `break-after: avoid` (or are wrapped with their intro in an `avoid` container).
- [ ] `li` and `tr` have `break-inside: avoid`; `thead` repeats via `table-header-group`.
- [ ] Long unboxed prose/lists/tables are allowed to flow (no `avoid` on giant containers).
- [ ] You generated a **3–4+ page** render (real or synthetic) and visually inspected **every** page boundary — not just the short sample.
- [ ] No atomic unit (card, heading, bullet, row) is sliced or orphaned at any boundary.
- [ ] Any box that can exceed page height is handled deliberately (unboxed inner content or accepted break), not silently relying on an ignored `avoid`.
