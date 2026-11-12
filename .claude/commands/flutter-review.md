---
description: Diff-scoped Flutter anti-pattern scanner. Run standalone (/flutter-review) at any time, or called internally by ship-pr as a blocking gate before commit. BLOCK findings abort ship-pr.
---

Scan a Dart diff for Flutter anti-patterns. Report only; never edit source.

**Mode.** Standalone (`/flutter-review`): `git diff HEAD -- '*.dart'`, heading label `HEAD`. Ship-pr gate: `git diff --cached -- '*.dart'`, label `staged`; ship-pr aborts on `🚫 BLOCK`.

If the diff is empty, output `✅ PASS — no Dart changes in diff` and stop.

Read `CLAUDE.md` first. Do not flag a pattern its conventions / critical-rules sections sanction.

Check **added or modified lines only** (`+`), except A5. Scope B1/B2 to the same method body: from the `await` to that method's closing brace. Do not flag across methods or callbacks.

## BLOCK

| ID | Look for | Fix |
|---|---|---|
| B1 | `context` used after `await` (`Navigator.of`, `ScaffoldMessenger.of`, `Theme.of`, `showDialog(context:`, `context.go/push`…) with no `if (!mounted) return` between | add the guard after the `await` |
| B2 | `setState(` / `notifyListeners(` after `await` with no `mounted` guard | add the guard before the call |
| B3 | `TextEditingController` / `ScrollController` / `FocusNode` / `PageController` / `AnimationController` constructed inside `build()`. If `initState` is not in the diff, flag as suspected: "initState not visible in diff — verify manually" | create in `initState`, dispose in `dispose` |
| B4 | `super.initState()` not the first statement of `initState` (comments and blank lines don't count) | move it first |
| B5 | `super.dispose()` not the last statement of `dispose` (comments and blank lines don't count) | move it last |
| B6 | `WillPopScope` | `PopScope(canPop:, onPopInvokedWithResult:)` |
| B7 | Under `lib/`: an `http(s)://` URL to a non-localhost host, or a credential literal (`sk_`, `pk_`, `AIza`, `Bearer `, `token=`, or a 32+ char non-UUID hex string assigned to `key`/`secret`/`token`/`password`/`credential`) | move to environment config |

## ADVISORY

| ID | Look for | Prefer |
|---|---|---|
| A1 | `MediaQuery.of(context).size/.padding/.textScaleFactor/.devicePixelRatio/.viewInsets/.viewPadding/.orientation` | `MediaQuery.sizeOf` / `paddingOf` / `textScalerOf` / `viewInsetsOf`… |
| A2 | `ListView(children:` with more than 3 items or any dynamic content (spread, for-in, call, non-const) | `ListView.builder` |
| A3 | `Opacity(opacity:` with a non-literal value | `FadeTransition` / `AnimatedOpacity` |
| A4 | `print(` / `debugPrint(` outside `if (kDebugMode) { }` (a method that opens with `if (!kDebugMode) return;` is fine) | wrap in `kDebugMode` |
| A5 | A **removed** `const WidgetName(` where the diff shows `WidgetName extends StatelessWidget` (skip if the class isn't in the diff) | restore `const` unless args became mutable |

## Output

One line per finding, `file:line | BLOCK|ADVISORY | one-sentence problem | fix`, sorted by file then line within each tier.

No findings at all: output only `✅ PASS — diff is clean`. Otherwise:

```
## Flutter Review — <staged|HEAD>

### BLOCK findings
<lines, or none>

### ADVISORY findings
<lines, or none>

### Verdict
✅ PASS — no blockers
```

or, with any BLOCK finding, the verdict line `🚫 BLOCK — N blocker(s) found, fix before ship`. The verdict is always the last line; ship-pr reads it.
