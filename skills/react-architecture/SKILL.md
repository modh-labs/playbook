---
name: react-architecture
description: >
  React component decomposition, hook extraction, state machines, composition
  patterns, hydration safety, and React 19 APIs. Use when components grow
  beyond 300 lines, accumulate boolean props, mix unrelated concerns, or need
  multi-step flow management.
---

# React Architecture

## 1. Decomposition Signals

When a component grows beyond 500 lines, it is an architecture problem, not a formatting problem. Decompose by extracting concerns into custom hooks and JSX blocks into components. The parent becomes thin orchestration: compose hooks, wire callbacks, render.

| Signal | Threshold | Action |
|--------|-----------|--------|
| File length | >300 lines: review. >500 lines: mandatory split | Extract hooks + components |
| useState count | >15 declarations | Group related state into hooks |
| useEffect count | >4 hooks | Each effect should own one concern |
| Multi-concern useEffect | One effect touching session + timezone + metadata | Split into focused hooks |
| Dead state | Setter never called OR value never read | Delete |
| Derivable state | `showModal` when `!!modalData` works | Replace useState with const |
| Same computation 3+ times | `deriveRequired(config)` called 3x | Compute once at top |
| >5 pure pass-through props | Props forwarded without transformation | Push to context or restructure |
| Boolean prop proliferation | 3+ boolean props controlling variants | Use explicit variant components |

---

## 2. Hydration Safety Rules

**Iron rule: No browser APIs in useState initializers.**

```typescript
// BAD - hydration mismatch (SSR returns null, client returns value)
const [sessionId] = useState(() => {
  if (typeof window === "undefined") return null;
  return `client-${Date.now()}`;
});

// GOOD - deterministic init, populate on mount
const [sessionId, setSessionId] = useState<string | null>(null);
useEffect(() => {
  setSessionId(`client-${Date.now()}`);
}, []);
```

**Browser-only APIs that MUST be in useEffect, never useState:**

| Category | APIs |
|----------|------|
| Time/random | `Date.now()`, `Math.random()`, `crypto.randomUUID()` |
| Window | `window.innerWidth`, `window.location`, `window.matchMedia()` |
| Document | `document.cookie`, `document.referrer`, `document.title` |
| Navigator | `navigator.userAgent`, `navigator.language`, `navigator.onLine` |
| Storage | `localStorage`, `sessionStorage` |
| Intl | `Intl.DateTimeFormat().resolvedOptions().timeZone` |
| Media queries | `window.matchMedia("(prefers-color-scheme: dark)")` |

**Safe patterns for dynamic initialization:**

```typescript
// Pattern 1: null init + useEffect
const [timezone, setTimezone] = useState<string | null>(null);
useEffect(() => {
  setTimezone(Intl.DateTimeFormat().resolvedOptions().timeZone);
}, []);

// Pattern 2: useSyncExternalStore for subscriptions
const isOnline = useSyncExternalStore(
  (cb) => { window.addEventListener("online", cb); window.addEventListener("offline", cb); return () => { window.removeEventListener("online", cb); window.removeEventListener("offline", cb); }; },
  () => navigator.onLine,
  () => true // server snapshot
);
```

See `references/hydration-safety.md` for the complete reference.

---

## 3. Hook Extraction Pattern

```
1. Identify the concern (related state + effects + callbacks)
2. Name it: use{Concern} (useAvailability, useSelection)
3. Move ALL related state + effects + callbacks into the hook
4. Return only what the parent component needs (minimal interface)
5. Parent becomes orchestration: compose hooks, wire callbacks, render
```

**Good hook boundaries:**

| Hook | Owns | Returns |
|------|------|---------|
| `useAvailability` | raw slots, loading, error, fetch effect, filtering | `{ slots, isLoading, error }` |
| `useSessionTracking` | sessionId, visitorId, tracking effects | `{ sessionId, visitorId }` |
| `useTimezone` | selected timezone, detection logic | `{ timezone, setTimezone }` |
| `useDebouncedFormSave` | form data, refs, timer, field handler | `{ formData, handleFieldChange, flush }` |
| `useMultiStepForm` | current step, validation, navigation | `{ step, canAdvance, next, back }` |

**Bad hook boundaries (naming reveals the problem):**

| Name | Problem |
|------|---------|
| `useFormState` | Too broad -- which form? What state? |
| `useEffects` | Grouping by React concept, not business concern |
| `useMisc` | No clear concern |
| `useHelpers` | Utility bag -- split by what each helper does |
| `useData` | Every hook uses data; name the domain |

---

## 4. State Machine Pattern

Replace boolean flag soup with an explicit phase type using discriminated unions.

```typescript
// BAD - ad-hoc booleans create impossible states
const [isLoading, setIsLoading] = useState(true);
const [isSubmitting, setIsSubmitting] = useState(false);
const [isConfirming, setIsConfirming] = useState(false);
const [showSuccess, setShowSuccess] = useState(false);
const [error, setError] = useState<string | null>(null);
// Bug: isLoading && isSubmitting can both be true

// GOOD - impossible states are impossible
type Phase =
  | { type: "loading" }
  | { type: "idle" }
  | { type: "submitting" }
  | { type: "confirming" }
  | { type: "success"; resultId: string }
  | { type: "error"; message: string };

const [phase, setPhase] = useState<Phase>({ type: "loading" });
```

**When to use state machines:**

| Scenario | Use state machine? |
|----------|--------------------|
| Multi-step wizard (3+ steps) | Yes |
| Form with submit/success/error | Yes |
| Simple toggle (open/closed) | No -- boolean is fine |
| Loading a single resource | No -- `isLoading` + data is fine |
| Async flow with confirmation step | Yes |
| Component with 3+ boolean flags for phases | Yes -- consolidate |

**Transition helper pattern:**

```typescript
function transition(current: Phase, event: PhaseEvent): Phase {
  switch (current.type) {
    case "idle":
      if (event === "submit") return { type: "submitting" };
      break;
    case "submitting":
      if (event === "success") return { type: "confirming" };
      if (event === "error") return { type: "error", message: "Failed" };
      break;
    case "confirming":
      if (event === "confirm") return { type: "success", resultId: "..." };
      if (event === "cancel") return { type: "idle" };
      break;
  }
  return current; // Invalid transitions are no-ops
}
```

---

## 5. Composition Patterns

### 5.1 Compound Components

Structure complex components as a provider + subcomponents. Each subcomponent reads shared state from context. Consumers compose only the pieces they need.

```tsx
const EditorContext = createContext<EditorContextValue | null>(null);

function EditorProvider({ children, state, actions }: ProviderProps) {
  return (
    <EditorContext value={{ state, actions }}>
      {children}
    </EditorContext>
  );
}

const Editor = {
  Provider: EditorProvider,
  Frame: EditorFrame,
  Input: EditorInput,
  Toolbar: EditorToolbar,
  Submit: EditorSubmit,
};

// Usage: compose what you need
<Editor.Provider state={state} actions={actions}>
  <Editor.Frame>
    <Editor.Input />
    <Editor.Toolbar />
    <Editor.Submit />
  </Editor.Frame>
</Editor.Provider>
```

### 5.2 Avoid Boolean Prop Proliferation

Each boolean prop doubles possible states. 4 booleans = 16 combinations, most invalid.

```tsx
// BAD - exponential complexity
<Editor isThread isEditing={false} showToolbar showEmojis={false} />

// GOOD - explicit variants
<ThreadEditor channelId="abc" />
<EditMessageEditor messageId="xyz" />
<InlineEditor />
```

### 5.3 Children Over Render Props

Use `children` for composition. Use render props only when the parent needs to provide data back to the child.

```tsx
// BAD - render props for static structure
<Editor renderHeader={() => <Header />} renderFooter={() => <Footer />} />

// GOOD - children compose naturally
<Editor.Frame>
  <Header />
  <Editor.Input />
  <Footer />
</Editor.Frame>

// OK - render props when parent provides data
<List data={items} renderItem={({ item }) => <Item data={item} />} />
```

### 5.4 Context Interface Pattern (Dependency Injection)

Define a generic `{ state, actions, meta }` interface. Different providers implement it; same UI consumes it.

```typescript
interface EditorState { content: string; isSubmitting: boolean }
interface EditorActions { update: (s: EditorState) => void; submit: () => void }
interface EditorContextValue { state: EditorState; actions: EditorActions }

// Provider A: local state
function InlineProvider({ children }: { children: React.ReactNode }) {
  const [state, setState] = useState(initial);
  return <EditorContext value={{ state, actions: { update: setState, submit: inlineSubmit } }}>{children}</EditorContext>;
}

// Provider B: global synced state
function ChannelProvider({ channelId, children }: Props) {
  const { state, update, submit } = useChannelSync(channelId);
  return <EditorContext value={{ state, actions: { update, submit } }}>{children}</EditorContext>;
}

// Same UI works with both providers
<InlineProvider><Editor.Frame><Editor.Input /><Editor.Submit /></Editor.Frame></InlineProvider>
<ChannelProvider channelId="abc"><Editor.Frame><Editor.Input /><Editor.Submit /></Editor.Frame></ChannelProvider>
```

### 5.5 Lift State into Providers

Move state out of components into providers so siblings can access it without prop drilling, effect syncing, or ref hacks.

```tsx
// BAD - state trapped inside, siblings can't access it
function EditorDialog() {
  return (
    <Dialog>
      <InlineEditor />            {/* state lives here */}
      <Preview />                 {/* needs editor state - how? */}
      <SubmitButton />            {/* needs submit action - how? */}
    </Dialog>
  );
}

// GOOD - provider lifts state, siblings access via context
function EditorDialog() {
  return (
    <EditorProvider>
      <Dialog>
        <InlineEditor />
        <Preview />              {/* reads state via use(EditorContext) */}
        <SubmitButton />         {/* calls actions.submit via use(EditorContext) */}
      </Dialog>
    </EditorProvider>
  );
}
```

Key insight: components that need shared state do not have to be visually nested. They just need to be within the same provider.

See `references/composition-patterns.md` for full examples.

---

## 6. React 19 Patterns

### 6.1 No forwardRef

In React 19, `ref` is a regular prop. Drop the `forwardRef` wrapper.

```tsx
// BAD - React 18 pattern, unnecessary in React 19
const Input = forwardRef<HTMLInputElement, Props>((props, ref) => {
  return <input ref={ref} {...props} />;
});

// GOOD - React 19: ref is just a prop
function Input({ ref, ...props }: Props & { ref?: React.Ref<HTMLInputElement> }) {
  return <input ref={ref} {...props} />;
}
```

### 6.2 use() Instead of useContext()

```tsx
// BAD - React 18 pattern
const value = useContext(MyContext);

// GOOD - React 19: use() can be called conditionally
const value = use(MyContext);
```

### 6.3 useOptimistic for Instant Feedback

Update UI immediately, reconcile when the server responds.

```tsx
function StatusCard({ item }: { item: Item }) {
  const [optimistic, setOptimistic] = useOptimistic(item);

  async function handleStatusChange(newStatus: string) {
    setOptimistic({ ...item, status: newStatus }); // instant
    await updateStatus(item.id, newStatus);         // server catches up
  }

  return (
    <Card>
      <Badge>{optimistic.status}</Badge>
      <StatusSelector onChange={handleStatusChange} />
    </Card>
  );
}
```

| Action | Use optimistic? |
|--------|-----------------|
| Toggle, status change | Yes |
| Form submission | Yes (with validation) |
| Delete | Show confirmation first, then optimistic |
| Complex multi-step | No -- use loading state |

### 6.4 useTransition for Non-Blocking Mutations

Keep the UI responsive during server mutations.

```tsx
function SaveButton({ onSave }: { onSave: () => Promise<void> }) {
  const [isPending, startTransition] = useTransition();

  return (
    <Button
      onClick={() => startTransition(onSave)}
      disabled={isPending}
    >
      {isPending ? "Saving..." : "Save"}
    </Button>
  );
}
```

---

## 7. Component Extraction Signals + Size Targets

### Extraction Signals

| Signal | Extract as |
|--------|-----------|
| JSX block >50 lines with no parent state dependency | Presentational component |
| Loading skeleton | `{Name}Skeleton.tsx` (zero props) |
| Error/empty state | `{Name}ErrorState.tsx` |
| Modal + its state management | `use{Name}Modal` hook + `{Name}Modal.tsx` |
| Repeated JSX pattern across 3+ places | Shared presentational component |
| Form section with own validation | `{Section}Fields.tsx` + `use{Section}Validation` |

### Size Targets After Decomposition

| File | Target | Hard limit |
|------|--------|------------|
| Parent orchestrator | 200-400 lines | 500 lines |
| Custom hook | 50-150 lines | 200 lines |
| Presentational component | 20-80 lines | 120 lines |
| Skeleton / error state | 10-40 lines | 60 lines |

---

## 8. Common Mistakes

| Mistake | Fix |
|---------|-----|
| `useState` for immutable prop | Use `const x = prop` |
| `useState` for derivable value | Use `const x = !!otherState` or `useMemo` |
| Dead state (setter prefixed with `_`) | Delete entirely |
| useEffect with 8+ dependencies | Break into focused hooks by concern |
| `.length` as effect dep causing re-fires | Use a ref for context, not a dependency |
| Same function called 3x with same args | Compute once, store in const |
| `console.log` in production | Delete -- use structured logger |
| `forwardRef` in React 19 project | Remove wrapper, use `ref` as prop |
| `useContext()` in React 19 project | Replace with `use()` |
| Boolean props controlling variants | Create explicit variant components |
| State trapped in component, sibling needs it | Lift to provider |
| renderX props for static structure | Use children composition |

---

## 9. Quick Audit Checklist

Before shipping any component >300 lines:

- [ ] No browser APIs in useState initializers
- [ ] No dead state (unused setters or unread values)
- [ ] No derivable state stored in useState
- [ ] Each useEffect owns exactly one concern
- [ ] No effect dependency that causes unintended re-fires
- [ ] Same value not computed more than once
- [ ] Loading/error JSX extracted to separate components
- [ ] File under 500 lines
- [ ] No boolean prop proliferation (3+ booleans controlling variants)
- [ ] Multi-step flows use discriminated union, not boolean soup
- [ ] Complex shared state lifted to provider, not trapped in component
- [ ] React 19: no forwardRef, use `use()` not `useContext()`
