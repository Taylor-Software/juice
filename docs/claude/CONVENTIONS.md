# Project conventions

Durable coding and documentation rules. Mirrored from per-user
memory so any Claude session reads the same playbook.

---

## Working principles

1. Don't assume. Don't hide confusion. Surface tradeoffs.
2. Minimum code that solves the problem. Nothing speculative.
3. Touch only what you must. Clean up only your own mess.
4. Define success criteria. Loop until verified.

---

## Documentation maintenance

### Update docs in the same change as code

| Code change | Doc updates required |
|---|---|
| New feature/screen | CLAUDE.md architecture, README if public |
| Architecture change | docs/claude/CONVENTIONS.md, CLAUDE.md |
| Build/deploy change | Build docs |
| New dependency | CLAUDE.md stack section |
| Test changes | CLAUDE.md test section |

### Where findings go

| Finding | Lives in |
|---|---|
| Architecture / perf / refactor | CODE_QUALITY.md (if exists) |
| Feature TODO | TODO.md or PLAN.md |
| Product scope | Requirements docs |
| Design pattern | CONVENTIONS.md or PROJECT_NOTES.md |

---

## Testing

- `flutter analyze` + `flutter test` must pass before every merge.
- Tests use descriptive names that explain the behavior, not the
  implementation.
- Prefer `TestWidgetsFlutterBinding.ensureInitialized()` in test
  files that load assets.

---

## Code style

The `analysis_options.yaml` at the project root is the source of
truth for lint rules. Add per-project overrides there rather than
disabling rules inline.

---

## Project-specific conventions

Add project-specific rules below this line as they emerge during
development. Each rule should explain the **why** (what went wrong
or what constraint drives it) and **how to apply** (when the rule
kicks in).

<!-- Add project-specific conventions here -->
