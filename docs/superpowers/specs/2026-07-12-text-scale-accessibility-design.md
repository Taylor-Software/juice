# Reading text scale + contrast pass — design

**Date:** 2026-07-12
**Source:** QoL assessment #9 — a reading-size slider for a text-heavy app,
plus the audit's low-contrast-muted-chips observation.

## Text scale

App-global `textScaleProvider` (`juice.text_scale.v1`, double 0.85–1.4,
default 1.0; per-device like `aiEnabledProvider` — not session-scoped, not
exported). Applied in `JuiceApp` via `MaterialApp.builder`: the MediaQuery
textScaler is replaced with `linear(systemScale × userScale)`, so the OS
accessibility setting still applies underneath. Settings sheet gains a
"Reading size" slider (`settings-text-scale`, 5% steps, Reset button).

## Contrast pass (WCAG AA, computed statically from the tokens)

| Token (light) | Was | Now | Ratio on `card` |
|---|---|---|---|
| `inkMuted` | `8A7466` (3.74) | `7D6759` | 4.51 |
| `inkFaint` | `9A8576` (2.98) | `8A7466` | 3.74 |
| `chaosChipText` | `8A5A18` (4.31 on chip bg) | `7E5214` | 4.94 |
| `inkFaint` (dark) | `8F7E70` (3.81) | `9C8A7B` | 4.48 |

Hues kept (warm tome palette); hierarchy preserved (`faint` < `muted` <
`body` 7.17). Dark `inkMuted` (5.55) and chaos chip (8.01) already passed.
Touch targets: compact `IconButton`s follow the M3 48px input padding —
no change needed.

## Tests

`test/text_scale_test.dart`: default/persist/clamp + load-on-build.
