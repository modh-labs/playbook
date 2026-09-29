---
name: portable-component-bundle
description: >
  Portable bundle: ship a React component library to a page outside its app's build (a
  design-system site, docs page, embed, artifact viewer, CMS preview) as classic scripts plus one
  stylesheet. Activates when bundling components as an IIFE, UMD or window global; when a React 19
  library needs a browser build React no longer publishes; when a bundled library carries its own
  React ("Invalid hook call", hooks returning null); or when Tailwind classes in a shipped bundle
  render unstyled.
---

# Portable Component Bundle

**Principle:** a page that did not build your app gets exactly three things from you: React once,
as page globals; your library as one script that reads those globals; and a stylesheet compiled
from exactly the files you ship, resolving to the host's tokens by name. Then you render every
preview in every theme and read the DOM back, because a bundle that builds is not a bundle that
runs.

**The one question:** *Will these components render somewhere my app's bundler never touches?*
If yes, every import of `react` and every utility class is now your problem to resolve.

## When This Skill Activates

- Publishing live components to a design-system page, docs site, Storybook-free showcase or
  artifact viewer
- Shipping an embeddable widget built from the app's own component library
- "Invalid hook call" or null hook state after loading a bundled library next to React
- "Function components cannot be given refs" after loading a React 19 library on React 18
- A shipped stylesheet that is enormous, or that misses classes the components use

## Decision Tree

```
Does the host page run your app's bundler?
├── YES → import the components normally; stop here
└── NO
    ├── React: does the host already load the exact major your library targets?
    │   ├── YES → map react, react-dom and the jsx runtime to the host's globals
    │   └── NO  → ship React yourself as globals (React 19 has no UMD: bundle it as an IIFE)
    ├── Library: one IIFE assigning window.<Namespace>, React mapped to globals, never bundled
    │   └── Gate: bundle contains React's internals key?      YES → a second React got in; fail
    ├── Styles: utility CSS (Tailwind)?
    │   ├── YES → compile from exactly the shipped files; map colors to the host's token names
    │   └── NO  → ship the library's own stylesheet
    ├── Inline safety: output contains </script, <!-- or </style?   YES → escape or fail
    └── Verify: every preview × every theme rendered, root non-empty, no runtime error?
        └── NO → the bundle is not done
```

## Core Rules

1. **React exists once, as globals.** Ship `react` and `react-dom` (merged with
   `react-dom/client`) as classic scripts that set `window.React` and `window.ReactDOM`. React 19
   publishes no UMD build. A React 18 UMD under a React 19 library drops `ref` passed as a prop to
   a plain function component, so anything that forwards a ref through `asChild` (Radix triggers,
   popover anchors) loses its element. Pin react and react-dom to one version and put it in the
   file name.
2. **Map every React entry point to the globals, dependencies included.** A bundler plugin
   resolves `react`, `react-dom`, `react-dom/client`, `react/jsx-runtime` and
   `react/jsx-dev-runtime` to tiny modules that read `window`. Radix and friends import these too;
   the plugin catches them because it matches on the specifier, not the importer.
3. **Shim the JSX runtime over `createElement`.** `createElement(type, props)` keeps
   `props.children` when no child arguments follow, so the whole runtime is one function:
   `jsx(type, props, key) = createElement(type, key === undefined ? props : {...props, key})`,
   exported as `jsx`, `jsxs` and `jsxDEV`, with `Fragment`.
4. **Prove the single copy.** React's internals key
   (`__CLIENT_INTERNALS_DO_NOT_USE_OR_WARN_USERS_THEY_CANNOT_UPGRADE` in React 19,
   `__SECRET_INTERNALS_DO_NOT_USE_OR_YOU_WILL_BE_FIRED` in 18) appears in `react` and `react-dom`
   and nowhere else. Fail the build when the library bundle contains it. The element tag
   (`react.transitional.element`) is the tempting marker and the wrong one: `react-is`, which
   charting and prop-type libraries bundle, contains it too.
5. **One namespace, one list.** The library assigns one global. A single typed list drives the
   header, the stylesheet sources, the previews and the docs, so a missing preview is a type
   error and a missing doc fails the build.
6. **Compile the stylesheet from exactly what ships.** Tailwind v4 scans from the working
   directory by default, which in a monorepo means everything. Use
   `@import "tailwindcss" source(none);` and one `@source` per shipped component file, plus the
   previews. Include files the components render through (a label, a select's scroll buttons).
7. **Resolve utilities to the host's tokens by name.** `@theme inline { --color-primary:
   var(--primary); }` makes `bg-primary` compile to `var(--primary)`, so the host's theme, dark
   mode and brand overrides apply with no remapping. Tailwind's own defaults (`--radius-md`,
   `--font-sans`) land in `@layer theme`; the host's unlayered token declarations beat them, so
   name the host's tokens to match.
8. **Match the host's theme switch.** `@custom-variant dark (&:is([data-theme="dark"] *, .dark *));`
   covers both an attribute-driven host and the app's class-driven one.
9. **Make output safe to inline.** Hosts and consumers paste these files into `<script>` and
   `<style>` elements. Replace `</script` with `<\/script` (identical inside a JS string), and fail
   on `<!--` in scripts and `</style` in CSS.
10. **Verify by rendering, then read the DOM.** Headless Chrome `--dump-dom` per preview per
    theme, asserting the root has children and no error was recorded. A build that succeeds says
    nothing about a preview that throws on mount.

## Implementation Pattern

Bun shown; esbuild's `format: "iife"` and an `onResolve`/`onLoad` plugin take the same shape.

```ts
const JSX = `var R = window.React;
function jsx(t, p, k) { return R.createElement(t, k === undefined ? p : Object.assign({}, p, { key: k })); }
module.exports = { jsx: jsx, jsxs: jsx, jsxDEV: jsx, Fragment: R.Fragment };`;
const GLOBALS: Record<string, string> = {
  react: "module.exports = window.React;",
  "react-dom": "module.exports = window.ReactDOM;",
  "react-dom/client": "module.exports = window.ReactDOM;",
  "react/jsx-runtime": JSX,
  "react/jsx-dev-runtime": JSX,
};

function globalsPlugin(ids: readonly string[]): BunPlugin {
  return {
    name: "react-globals",
    setup(build) {
      build.onResolve({ filter: /^react(-dom)?(\/[a-z-]+)?$/ }, (a) =>
        ids.includes(a.path) ? { path: a.path, namespace: "globals" } : undefined);
      build.onLoad({ filter: /.*/, namespace: "globals" }, (a) =>
        ({ contents: GLOBALS[a.path] ?? "", loader: "js" }));
    },
  };
}

async function bundle(entry: string, plugins: BunPlugin[]) {
  const r = await Bun.build({ entrypoints: [entry], format: "iife", target: "browser",
    minify: true, define: { "process.env.NODE_ENV": '"production"' }, plugins });
  const code = (await r.outputs[0].text()).replaceAll("</script", "<\\/script");
  if (code.includes("<!--")) throw new Error(`${entry}: "<!--" breaks an inline <script>`);
  return code;
}

// react.ts:     import * as React from "react"; window.React = React;
// react-dom.ts: window.ReactDOM = { ...ReactDOM, ...ReactDOMClient };
const react = await bundle("react.ts", []);
const reactDom = await bundle("react-dom.ts", [globalsPlugin(["react"])]);
const lib = await bundle("entry.ts", [globalsPlugin(Object.keys(GLOBALS))]);
const INTERNALS = "__CLIENT_INTERNALS_DO_NOT_USE_OR_WARN_USERS_THEY_CANNOT_UPGRADE";
if (lib.includes(INTERNALS)) throw new Error("library bundled its own React or ReactDOM");
```

Stylesheet input, compiled with `@tailwindcss/postcss` (`from` set to a path inside the app so
`tailwindcss` resolves):

```css
@import "tailwindcss" source(none);
@import "tw-animate-css";                               /* when components use animate-in */
@source "/abs/path/packages/ui/components/button.tsx";   /* one per shipped file */
@source "/abs/path/out/components/*/preview.html";
@custom-variant dark (&:is([data-theme="dark"] *, .dark *));
@theme inline {
  --color-background: var(--background);
  --color-primary: var(--primary);                      /* one per color token */
}
@layer base {
  * { @apply border-border; }
  body { @apply bg-background text-foreground font-sans; }
}
```

Preview document the host loads after tokens, stylesheet, React and the library:

```html
<div id="root"></div>
<script>
  var h = React.createElement, NS = window.MyLib;
  ReactDOM.createRoot(document.getElementById('root'))
    .render(h(NS.Button, { variant: 'default' }, 'Save Changes'));
</script>
```

Render check, per preview and theme:

```bash
chrome --headless=new --allow-file-access-from-files --virtual-time-budget=2500 \
  --dump-dom "file://$PWD/Button-dark.html"
# pass: <body> carries no data-err="…" attribute, and #root has a child element
```

## Verification False Negatives

Three traps from the reference build, each of which misreported a working preview:

- **The error hook matches itself.** Injecting `window.onerror = …setAttribute("data-err", m)`
  puts the text `data-err` into every dumped page. Assert on the attribute form, `data-err="`.
- **Modals hide the root.** An open Radix `Dialog` marks siblings with
  `aria-hidden="true" data-aria-hidden="true"`, so `<div id="root">` no longer matches as an
  exact string. Match the root by id and look for its first child.
- **`String.raw` re-escapes non-ASCII under Bun.** A preview source holding `⌘` inside
  `String.raw` came out as the literal text `⌘`. Keep preview sources in plain template
  literals, or write the escape on purpose.

## Anti-Patterns

- **Bundling React into the library.** Two Reacts on one page: hooks read a dispatcher the other
  copy set, and fail with "Invalid hook call" or silent nulls.
- **A React 18 UMD from a CDN under a React 19 library.** Mounts, then breaks every `ref` passed
  as a prop.
- **Letting Tailwind auto-detect in a monorepo.** Megabytes of CSS, or missing classes when the
  working directory is not the one you assumed.
- **Hard-coding a palette into the bundle.** The host's theme, dark mode and brand overrides stop
  applying. Map to token names instead.
- **Calling a build green without rendering.** A missing export or a preview typo throws at mount,
  after every build step reported success.

## Audit Checklist

- [ ] React and ReactDOM ship once, as globals, at one pinned version named in the file
- [ ] Every React entry point, including the JSX runtimes, resolves to the globals
- [ ] The build fails when the library bundle contains React's internals key
- [ ] One typed list drives the namespace header, stylesheet sources, previews and docs
- [ ] Tailwind runs with `source(none)` and an explicit `@source` per shipped file
- [ ] Color utilities compile to `var(--token)` names the host defines
- [ ] The `dark` variant matches the host's theme switch
- [ ] No `</script`, `<!--` or `</style` survives in any output the host inlines
- [ ] Every preview rendered in every theme, root non-empty, no recorded error
