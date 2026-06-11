---
description: Run flutter analyze + flutter test and summarize results.
---

Full project audit run.

## Steps

1. **Run `flutter analyze`** in project root. Capture output.
2. **Run `flutter test`** in project root. Capture output.
3. **Summarize:**
   - **Analyze:** errors / warnings / infos. List every error and warning with file:line. Infos summarized as count.
   - **Tests:** passed / failed / skipped. List every failing test with message. If all passed, one line.

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

<list failures, or "All tests passed">

### Verdict
✅ Clean / 🟡 Lint-grade only / 🔴 Build broken
```
