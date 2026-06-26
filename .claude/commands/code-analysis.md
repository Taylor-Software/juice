---
description: Run a thorough code analysis — packages, patterns, performance, dead code, security — and record findings. Fans out to cheap parallel scan agents.
---

Full deep-dive analysis of Flutter/Dart project code health: packages, architecture, performance, code reduction, and security. Read-only — no source edits unless the user follows up with "fix N". Always write a dated report to `docs/code-analysis/YYYY-MM-DD-analysis.md`; if `docs/CODE_QUALITY.md` exists, also update its Open/Active table with new finding IDs.

## Severity scale

- **🔴 CRITICAL** — bugs, security issues, data loss risk. Fix before next ship.
- **🟠 HIGH** — performance hot path, large refactor opportunity, broken pattern.
- **🟡 MEDIUM** — anti-patterns, minor refactors, dead code, missed coverage on important paths.
- **🟢 LOW** — style, naming, doc fixes, minor cleanups.
- **💡 IDEA** — architectural suggestions; not necessarily wrong today.

Each finding: severity + file:line + one-sentence problem + suggested fix.

## Step 1 — Gather baseline metrics

Run in parallel:

1. **`flutter pub outdated`** — resolved vs latest for every dependency.
2. **File / LOC counts:**
   ```bash
   find lib -name '*.dart' | wc -l
   find lib -name '*.dart' -exec wc -l {} + | sort -rn | head -15
   ```
3. **Read `pubspec.yaml`** — SDK constraint, dependency sections.
4. **`flutter analyze`** — lint pass; note issue count by severity.
5. **Test count:** `grep -rl 'test\|testWidgets' test/ --include='*.dart' | wc -l`

## Step 2 — Fan out to five parallel scan agents

Launch as **background subagents (`model: haiku`)**. They scan and report; synthesis is Step 3's job. Routing the noisy scanning to Haiku keeps the large scans out of the main context and off the expensive model.

**Before dispatching each agent:** pull the project's caveats from `CLAUDE.md`'s critical-rules / conventions section and prepend them to every agent prompt. This prevents the scan from flagging deliberate patterns (e.g., dynamic i18n keys that look unused, data-table files with intentional repetition, engine-internal conventions).

### Agent 1 — Package analysis

For each dependency in `pubspec.yaml`:
- Is it actually imported anywhere in `lib/`?
- Is it in the right section (`dependencies` vs `dev_dependencies`)?
- Is it redundant with another dep (wraps the same functionality)?
- What does `flutter pub outdated` report — any breaking-change upgrades available?

### Agent 2 — Architecture + anti-pattern scan

Walk the source tree. For each file, flag:

**General:**
- **God objects** — classes > 500 LOC or > 20 public members
- **Deep nesting** — > 4 levels of conditionals / loops
- **Long methods** — > 50 LOC
- **Magic numbers** — literal constants used > 1 place in logic (not const-declared)
- **Duplicated code** — copy-paste blocks > 10 LOC
- **Unused exports / dead code** — public symbols with no references
- **Suspicious null handling** — `!` operator chains, swallowed errors, empty catch blocks
- **String-typed identifiers** — IDs or flags stored as raw strings instead of enums / newtypes
- **Premature abstractions** — interfaces with only one implementation, factories without variation
- **Mixed concerns** — UI code reaching into data/engine layer; rendering logic in data classes
- **TODO / FIXME comments** — especially ones older than a month

**Flutter / Dart specific:**
- **Long `build()` methods** — > 100 LOC; decompose into smaller widgets
- **Missing `const` constructors** — `StatelessWidget` subclasses or immutable data classes that could be `const` but aren't
- **`BuildContext` across async gap** — `await` inside a method that then uses `context` without a `mounted` check; crashes after widget disposal
- **`setState()` without `mounted` check** — calling `setState` in an async callback without checking `if (!mounted) return` first
- **`GlobalKey` overuse** — each `GlobalKey` forces its subtree out of the element tree on rebuild; prefer keys local to list items
- **`super.initState()` not first** — overrides that call `super.initState()` anywhere other than the first line
- **`super.dispose()` not last** — overrides that call `super.dispose()` anywhere other than the last line
- **`WillPopScope` usage** — deprecated since Flutter 3.12; replace with `PopScope`
- **`MaterialStateProperty` usage** — renamed to `WidgetStateProperty` in Flutter 3.19; old name is deprecated
- **`MediaQuery.of(context)` for a single field** — `MediaQuery.of(context).size` / `.padding` / `.textScaler` rebuilds on ANY metric change; prefer `MediaQuery.sizeOf(context)`, `MediaQuery.paddingOf(context)`, etc. (available since Flutter 3.10)
- **`AutomaticKeepAliveClientMixin` without `super.build`** — must call `super.build(context)` and return its result, or the mixin has no effect
- **`context.dependOnInheritedWidgetOfExactType` in `initState`** — illegal; must be in `didChangeDependencies`
- **Dart 3 idioms missing:** `if-else` chains on a type field → `switch` expression; multi-value returns as `List` or positional args → named records `({T a, U b})`; abstract class with closed subclass set → `sealed class` for compile-time exhaustiveness

Cap at 20–25 findings. Pick highest-signal.

### Agent 3 — Performance + memory scan

Light static scan only (full profiling is out of scope):

**General:**
- O(n²) or worse loops in hot paths (engine ticks, render frames)
- Unbounded allocations per frame (`new` inside `update` / `render` / `build`)
- Synchronous I/O on the UI thread
- Large objects copied where references would do
- Stream subscriptions or listeners not removed in `dispose` / cleanup paths
- Over-broad reactive observers (subscribing to a whole model when only one field is needed)

**Flutter / Dart specific:**
- **`ListView(children: [...])` for unbounded / large lists** — use `ListView.builder` to build lazily; `children:` builds all items upfront
- **`Opacity(opacity: animated_value)`** — `Opacity` triggers `saveLayer` (offscreen raster pass) on non-Impeller; use `FadeTransition` (shader-based, no saveLayer) or `AnimatedOpacity` for animated values
- **`ClipRRect` / `ClipPath` / `BackdropFilter` without `RepaintBoundary`** — each triggers `saveLayer` every frame; wrap in `RepaintBoundary` to isolate the raster cost
- **`Image.network` / `Image.asset` without `cacheWidth` / `cacheHeight`**  — large source images decoded at full resolution waste GPU memory; set dimensions matching display size
- **`Column` + `Expanded` inside `SingleChildScrollView`** — throws `RenderFlex` unbounded-height error at runtime; `Expanded` requires a bounded parent
- **Nested `SingleChildScrollView` in the same axis** — causes `RenderBox` double-scroll confusion and layout jank; use `CustomScrollView` with `SliverList`
- **Controllers created inside `build()`** — `TextEditingController`, `ScrollController`, `FocusNode`, `PageController`, `AnimationController` created in `build()` produce a new instance on every rebuild and leak the old one; create in `initState`, dispose in `dispose`
- **`print()` / `debugPrint()` not guarded by `kDebugMode`** — active in release builds; performance hit and potential info leak
- **Missing `RepaintBoundary` around heavy `CustomPaint`** — costly painters that repaint independently of the widget tree should be isolated

### Agent 4 — Code reduction + refactoring

Identify **removable code**:
- Dead feature flags (always-on or always-off conditionals)
- Backwards-compat shims for migrations that completed
- Duplicate utility functions
- Unused imports / symbols
- Test scaffolding that no longer matches the code under test

For each: file + estimated LOC removable.

Identify **refactoring opportunities** (structure correct, shape can improve):
- **Extract widget** — `build()` sections > 30 LOC with a clear visual purpose; extract to `StatelessWidget` (enables `const`, improves rebuild scope)
- **Extract method** — logic blocks > 20 LOC with a single clear purpose inside a larger method
- **Inline variable** — single-use variables that obscure rather than clarify
- **Replace conditional with polymorphism** — switch / if-else chains dispatching on a type field
- **Introduce parameter object** — methods with > 4 parameters that cluster naturally
- **Pull up / push down** — logic duplicated across sibling classes that belongs in a shared base or mixin
- **Rename for intent** — identifiers whose names don't match what they actually do
- **Split file** — source files > 300 LOC mixing multiple distinct responsibilities

For each: file:line + one-sentence rationale + complexity (trivial / medium / invasive).

### Agent 5 — Security + release config

**General security:**
- Hardcoded credentials or API keys in source (not just `.env`)
- SQL string concatenation (injection risk)
- Unvalidated user input flowing to system commands or eval
- Secrets in comments or test fixtures

**Flutter / Android / iOS release config:**
- **`android:debuggable="true"`** in `android/app/src/main/AndroidManifest.xml` — must be absent or `false` in release builds
- **`android:usesCleartextTraffic="true"`** in AndroidManifest — allows unencrypted HTTP; remove or scope to debug only
- **`NSAllowsArbitraryLoads: true`** in `ios/Runner/Info.plist` — disables Apple ATS; must have a justification or be removed
- **`debugDefaultTargetPlatformOverride`** not guarded by `kDebugMode` — leaks into release builds
- **`print()` / `debugPrint()` in `lib/`** not guarded by `kDebugMode` — surfaces internal state in release logs
- **Dev / staging API base URLs committed in `lib/`** — hardcoded non-prod endpoints that ship in release

**Dart strictness:**
- Nullable types used where non-null would suffice
- Immutability annotations missing on data classes (`@immutable`)
- `async` functions not properly awaited (fire-and-forget without error handling)
- `RNG` / `DateTime` not injectable (tests can't be deterministic)
- Public APIs undocumented where the active lint level requires it

## Step 3 — Synthesize (main thread, session model)

When all five return:

1. **Deduplicate** overlapping findings across agents.
2. **Assign IDs** — if `docs/CODE_QUALITY.md` exists, continue its highest ID; else number from 1.
3. **Rate severity** using the five-level scale above; correctness risk > user-visible impact > maintenance burden.
4. **Write report** to `docs/code-analysis/<YYYY-MM-DD>-analysis.md` (create directory if missing).
5. **Update `docs/CODE_QUALITY.md`** if it exists — add findings to Open/Active table and a new Phase row.
6. **Report inline** — table ranked by severity, counts by category, top 3 next moves.

Cap the report at ~250 lines / 30 findings. Long reports get ignored; surface the top findings, not all of them.

## Step 4 — Verify

Run `flutter analyze` + `flutter test` to confirm nothing broke and to surface the baseline counts. Report results.

## Output format

```markdown
# Code Analysis — YYYY-MM-DD

**Project:** <name>
**Scope:** <n> source files · <n> LOC · <n> test files
**Toolchain:** Flutter/Dart · <lint level>
**Packages:** <n> deps · <n> dev · <n> outdated

## Headline

One paragraph: what's healthy, what needs attention, top-3 priorities.

## Findings

| ID | Severity | Area | File:line | Finding | Fix |
|---|---|---|---|---|---|
| 1 | 🔴 CRITICAL | Security | foo.dart:42 | Hardcoded API key | Move to env |
| 2 | 🟠 HIGH | Perf | bar.dart:88 | O(n²) in render loop | Cache sorted list |
| ... | | | | | |

## Coverage gaps

- `lib/src/foo.dart` — no tests for error path
- ...

## Top 3 next moves

1. ...
2. ...
3. ...

## Methodology

Generated by `/code-analysis`. Re-run monthly or after major work to track drift.
```

## Notes

- **Read-only.** Don't edit source files unless the user follows up with "fix N" or similar.
- Prefer specific **file:line citations** over abstract claims.
- Skip trivial style nits if the linter already catches them — avoid noise.
- If a finding is debatable (taste, not bug), mark it **💡 IDEA**, not 🟡 MEDIUM.
- Don't auto-commit the report — let the user review and commit it themselves.
