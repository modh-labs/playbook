---
name: build-time-reads
description: >
  Make the build see the same inputs as runtime, and read files in a shape the bundler can trace.
  Activates when a Next.js root layout, static or partially prerendered page reads process.env;
  when adding an env var to a Turborepo monorepo (turbo.json env, passThroughEnv, strict mode);
  when a build log warns that variables are "missing from turbo.json" or that dynamic filesystem
  access "causes tracing of the whole project"; or when prebuilt pages and per-request pages
  disagree about a config value.
---

# Build-Time Reads

**Principle:** every read the build performs is decided once, with the build's inputs, and shipped
as-is. A prerendered page **freezes** the env the build saw. A file read the bundler cannot follow
is **opaque**, so it ships everything. Both only warn, and both pass every test that runs the code
at request time.

**The one question:** *when this line runs during `next build`, does it see what production sees,
and can the bundler tell which file it touches?*

## When This Skill Activates

- A root layout, a static page, or the static shell of a partially prerendered page reads
  `process.env`
- A new env var lands in a Turborepo monorepo whose `turbo.json` runs in strict env mode (the
  default)
- The build log lists project variables "missing from turbo.json"
- Turbopack warns "Dynamic filesystem access causes tracing of the whole project"
- A server route reads fonts, templates, or data files from disk with `fs.readFile`
- Prebuilt pages and live pages disagree about the same setting

## Decision Tree

```
Line runs during next build?  (root layout, ○ static page, ◐ shell, generateStaticParams, metadata)
├── NO (only inside a request: route handler, dynamic page, behind await connection())
│     → env reads are request-time; still declare the var (passThroughEnv) so the log stays clean
└── YES
    ├── Reads process.env.X?
    │   ├── X declared for this build task in turbo.json (env / passThroughEnv / global)?
    │   │     NO → X is stripped; the page freezes the fallback. Declare it.
    │   │          Changes rendered output? → `env` (hashed). Otherwise → `passThroughEnv`.
    │   └── Will this build be promoted to another environment without rebuilding?
    │         YES → the frozen value is the SOURCE env's. Move the read behind a request boundary.
    └── Reads a file (fs.readFile, fs.createReadStream, sharp(path), ...)?
        └── Argument is a module-level const = new URL("literal", import.meta.url)?
              YES → traced: only that file ships
              NO  (obj.url in a .map, template string, computed path) → opaque: whole project ships
```

## Core Rules

1. **Strict env mode strips undeclared variables from the build process.** A var set on the host
   but missing from the task's `env`/`passThroughEnv` is `undefined` inside `next build`. Runtime
   functions still get it, which is why only prerendered output is wrong.
2. **Prerendering freezes.** The root layout wraps every prerendered page, so a `process.env` read
   there, or in a helper it calls, is baked into static HTML. The same deploy then serves two
   answers: prebuilt pages say the fallback, per-request pages say the real value.
3. **Declare by effect.** A var that changes what the build emits goes in `env`, so it enters the
   cache hash. A var only read per request goes in `passThroughEnv`.
4. **Guard what the build executes, including app code.** A test that scans only `next.config.ts`
   and build scripts misses the layout. Scan the root layout and its direct imports too.
5. **Hand the bundler a literal.** Turbopack follows `readFile(CONST)` when `CONST` is a top-level
   `new URL("literal", import.meta.url)`. A property read through `.map()` is opaque, and it traces
   the project root.

```ts
// WRONG: opaque. Turbopack traces the whole project into this route.
const FACES = [{ url: new URL("./fonts/Regular.ttf", import.meta.url), weight: 400 }];
await Promise.all(FACES.map((face) => readFile(face.url)));

// CORRECT: traced. Only the three font files ship.
const FONT_REGULAR_URL = new URL("./fonts/Regular.ttf", import.meta.url);
const FONT_BOLD_URL = new URL("./fonts/Bold.ttf", import.meta.url);
const [regular, bold] = await Promise.all([
  readFile(FONT_REGULAR_URL),
  readFile(FONT_BOLD_URL),
]);
```

## Implementation Pattern

**Env guard test.** Parse `turbo.json` (strip JSONC comments), collect the build task's declared
patterns, then fail on any `process.env.X` read in build-time sources that is not declared.

```ts
const BUILD_TIME_SOURCES = ["next.config.ts", "scripts/upload-sourcemaps.ts"];
const PRERENDER_ENTRY = "app/layout.tsx";
const LOCAL_ONLY = new Set(["ANALYZE", "PORT"]); // dev-only reads

function derivePrerenderSources(): string[] {
  const entry = readFileSync(join(WEB_ROOT, PRERENDER_ENTRY), "utf8");
  const sources = [PRERENDER_ENTRY];
  for (const [, base] of entry.matchAll(/from "@\/([^"]+)"/g)) {
    const file = [".ts", ".tsx"].map((ext) => base + ext)
      .find((candidate) => existsSync(join(WEB_ROOT, candidate)));
    if (file) sources.push(file);
  }
  return sources;
}
// undeclared = names read in [...BUILD_TIME_SOURCES, ...derivePrerenderSources()]
//              that are neither LOCAL_ONLY nor matched by a declared pattern → expect([])
```

**Trace guard test.** Read the module's source; every `readFile(` argument must be a name bound by
`^const NAME = new URL("…", import.meta.url)`. Pair it with a behavioural test that the files
still load, so a fix that drops one from the trace cannot pass.

**Measure the trace.** After `next build`, each route has `.next/server/app/<route>/route.js.nft.json`.
Count its `files` and compare with a sibling route. In the incident behind this skill, an export
route went from 11,315 files (465 MB) to 439 files (29.9 MB); its sibling held 319.

## Anti-Patterns

- **Fixing the value by hardcoding it.** Matching the fallback to production hides the bug in
  production and leaves every other environment wrong.
- **`/*turbopackIgnore: true*/` on a read the route needs.** The warning goes away and the file
  leaves the trace with it. Restructure the read instead.
- **Trusting a green build.** Both failures are warnings. Read the log, or gate on it.
- **Checking a dynamic page to prove the fix.** Dynamic pages were always right. Check a static
  one (`○` in the build's route table).

## Audit Checklist

- [ ] Every `process.env` read in the root layout and its helpers is declared for the build task
- [ ] Each declared var sits in `env` if it changes output, `passThroughEnv` if request-only
- [ ] The build log's "missing from turbo.json" list for the app's build task is empty
- [ ] An env guard test scans the root layout's imports, not only config files
- [ ] No "tracing of the whole project" warning in the build log
- [ ] Every server-side `readFile` takes a module-level `new URL(literal, import.meta.url)` const
- [ ] Routes that read files trace a count close to their siblings (`*.nft.json`)
- [ ] After deploy, a static page and a dynamic page report the same config values
