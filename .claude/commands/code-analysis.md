---
description: Run a thorough code analysis — packages, patterns, performance, dead code — and report findings.
---

Full code analysis run. Produces structured findings.

## Step 1 — Baseline metrics

Run in parallel:

1. **`flutter pub outdated`** — resolved vs latest for every dependency.
2. **File/LOC counts:**
   ```bash
   find lib -name '*.dart' | wc -l
   find lib -name '*.dart' -exec cat {} + | wc -l
   find lib -name '*.dart' -exec wc -l {} + | sort -rn | head -15
   ```
3. **Read `pubspec.yaml`** — SDK constraint, dependencies.

## Step 2 — Four parallel analysis agents

Launch simultaneously:

1. **Package analysis** — verify each dep is used (grep imports), check dep section placement, flag redundancies, note available upgrades.

2. **Code pattern analysis** — scan `lib/` for anti-patterns (unsafe casts, missing null safety), best practices (const constructors, Dart 3 features, widget decomposition, disposal), consistency (naming, imports, file organization).

3. **Performance analysis** — state management rebuild efficiency, widget rebuild patterns (missing const, large build methods), animation lifecycle, memory allocation in hot paths.

4. **Code reduction** — dead code (unused functions/fields/imports, commented blocks), duplication (near-identical widgets, repeated logic), oversized files (>500 LOC), unnecessary code (redundant getters, defensive checks on non-nullable types).

## Step 3 — Synthesize

1. **Deduplicate** overlapping findings.
2. **Rate severity** — High / Medium / Low based on correctness risk, user impact, maintenance burden.
3. **Update docs** — if `docs/CODE_QUALITY.md` exists, add new findings. Otherwise create it.
4. **Report** summary table ranked by severity.

## Step 4 — Verify

Run `flutter analyze` and `flutter test` to confirm doc-only changes don't break anything.

## Output format

```
## Code Analysis Results — [date]

### Metrics
- Files: <n> | LOC: <n> | Top 3 files: ...
- Packages: <n> deps, <n> dev_deps | <n> outdated

### Findings (ranked by severity)

| ID | Area | Severity | Finding |
|---|---|---|---|
| ... | ... | ... | ... |

### Summary
- High: <n> | Medium: <n> | Low: <n>
- Recommended execution order: ...
```

Token cost: ~150-200K total (4 parallel agents each ~30-50K).
