---
description: Run a thorough code analysis — packages, patterns, performance, dead code — and record findings. Fans out to cheap parallel scan agents.
---

The user wants a full code analysis. This produces structured findings and, if the repo keeps a code-quality doc, updates it. Project-agnostic.

## Step 1 — Gather baseline metrics

Run in parallel:

1. **`flutter pub outdated`** — resolved vs latest for every dependency.
2. **File / LOC counts:**
   ```bash
   find lib -name '*.dart' | wc -l
   find lib -name '*.dart' -exec wc -l {} + | sort -rn | head -15
   ```
3. **Read `pubspec.yaml`** — SDK constraint, dependency sections.

## Step 2 — Fan out to four parallel scan agents

Launch these as **background subagents on a cheap model** (`subagent_type: Explore` or `general-purpose` with `model: haiku`). They scan and report; they don't reason about architecture — that's Step 3's job. Routing the noisy scanning to Haiku is the whole token play here: four ~30-50K scans stay out of the main thread and off the expensive model.

1. **Package analysis** — for each dependency: is it actually imported? right section (`dependencies` vs `dev_dependencies`)? redundant with another dep? breaking changes in the available upgrade?
2. **Pattern analysis** — anti-patterns (unsafe casts, missing null safety, state-layer rules from CLAUDE.md), best practices (const constructors, Dart 3 features, widget decomposition, disposal), consistency (naming, imports, file org).
3. **Performance analysis** — reactive-rebuild efficiency (over-broad observers, needless `.obs`), missing `const`, oversized build methods, animation controller lifecycle, `RepaintBoundary`, hot-path allocation.
4. **Code reduction** — dead code (unused symbols/imports, commented blocks), duplication, oversized files (>500 LOC) and methods (>50 lines), redundant defensive checks.

**Always pass the project's own caveats into each agent prompt** — pull them from `CLAUDE.md`'s critical-rules section so the scan respects them. (For example: dynamic i18n keys can't be proven unused by grep; data-table files have intentional row repetition.) This keeps the analysis from "finding" deliberate patterns.

## Step 3 — Synthesize (main thread, on the session model)

When all four return:

1. **Deduplicate** overlapping findings.
2. **Assign IDs** — if a code-quality doc exists, continue its ID scheme (check current highest); else number from 1.
3. **Rate severity** — High / Medium / Low by correctness risk, user-visible impact, maintenance burden.
4. **Record** — if `docs/CODE_QUALITY.md` exists, add findings to its Open/Active table and the next Phase row. Otherwise report inline only.
5. **Report** — table ranked by severity, counts by category, recommended execution order.

## Step 4 — Verify

If you changed any doc, run `flutter analyze` + `flutter test` to confirm nothing broke. Report results.

## Output format

```
## Code Analysis Results — [date]

### Metrics
- Files: <n> | LOC: <n> | Top 3 files: ...
- Packages: <n> deps, <n> dev | <n> outdated

### Findings (ranked)
| ID | Area | Severity | Finding |
|---|---|---|---|

### Summary
- High: <n> | Medium: <n> | Low: <n>
- Recommended execution order: ...
```
