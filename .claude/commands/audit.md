---
description: Run flutter analyze + flutter test and summarize results — errors, warnings, test failures
---

The user wants a full project audit run.

## What to do

Use the analyze and test commands `CLAUDE.md` names as the gate (e.g. a tag exclusion, or `melos run` in a monorepo); if it names none, `flutter analyze` and `flutter test`.

1. **Run the analyze command** in the project root. Capture the output.
2. **Run the test command** in the project root. Capture the output (it can be large; use a tmp file if needed).
3. **Summarize:**
   - **Analyze:** count of errors / warnings / infos. List every error and warning with file:line. Infos can be summarized as "N infos (mostly prefer_single_quotes)" without enumeration.
   - **Tests:** total passed / failed / skipped. List every failing test with the failure message. If all passed, say so in one line.
4. **Flag regressions** — if either analyze or test surfaced new errors compared to the last clean state, call those out at the top.

## Output format

```
## Audit results

### flutter analyze
- Errors: <n>
- Warnings: <n>
- Infos: <n>

<list errors and warnings, file:line>

### flutter test
- Passed: <n>
- Failed: <n>
- Skipped: <n>

<list failures with messages, or "All tests passed">

### Verdict
✅ Clean / 🟡 Lint-grade only / 🔴 Build broken
```

Token cost: this is a runner — 1-2K tokens of summarization regardless of suite size, since the bulk of the output gets compressed into counts + the failures list.
