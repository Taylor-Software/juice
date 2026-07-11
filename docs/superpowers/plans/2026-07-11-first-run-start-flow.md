# First-Run Start Flow — plan

Spec: `docs/superpowers/specs/2026-07-11-first-run-start-flow-design.md`

1. **launcher_screen.dart**
   - Compute `pristine` in `build` (sessions + journal already watched).
   - Branch the body: pristine → `launcher-start-first` FilledButton +
     `launcher-skip-blank` TextButton + Import row (welcome card + AI gate
     unchanged); else → today's layout.
   - `_new(context, ref, {required bool wasPristine})`: after successful
     create (all three start branches), `await remove('default')` when
     `wasPristine`. Same cleanup after successful `_import` when pristine.
2. **Tests** (`test/launcher_first_run_test.dart`, + touch existing
   launcher tests if they assumed Continue):
   - pristine → Start-first shown, Continue/campaign-list absent.
   - journal non-empty → normal launcher.
   - renamed default → normal launcher.
   - wizard create from pristine → sessions no longer contain 'default'.
   - skip → dismisses gate (route lands), campaign untouched.
3. `flutter analyze` + full test suite; browser spot-check of the pristine
   launcher + create-flow.
4. Docs: CLAUDE.md first-run bullet + audit doc disposition; ship via
   `/ship-pr`, squash-merge.
