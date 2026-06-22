# macOS on-device AI: LiteRtLm missing-dylib workaround

**Date:** 2026-06-22

## Symptom

On macOS desktop, after the model downloads, loading fails:

```
ArgumentError: Failed to load dynamic library 'LiteRtLm.framework/LiteRtLm':
dlopen(...): Library not loaded: @rpath/libGemmaModelConstraintProvider.dylib
  Referenced from: .../LiteRtLm.framework/Versions/A/LiteRtLm
  Reason: tried: ... (no such file)
```

## Root cause (upstream flutter_gemma)

`LiteRtLm.framework` (flutter_gemma's macOS native asset, confirmed on **0.16.5
through 1.1.0**) hard-links a dependency dylib:

```
otool -L LiteRtLm.framework/LiteRtLm
  @rpath/libGemmaModelConstraintProvider.dylib   ← required
```

Its `LC_RPATH` entries point at bazel `_solib_darwin_arm64/…` runfiles dirs that
don't exist in the shipped framework, plus `@loader_path`, `@loader_path/../../..`.

flutter_gemma's native-asset hook **downloads** the dependency dylibs into its
cache but only embeds `LiteRtLm.framework` (from `libLiteRtLm.dylib`). The
others are left behind:

```
~/Library/Caches/flutter_gemma/native/macos_arm64/
  libLiteRtLm.dylib                    → embedded as LiteRtLm.framework
  libStreamProxy.dylib                 → embedded as StreamProxy.framework
  libGemmaModelConstraintProvider.dylib → NOT embedded  ← the blocker
  libLiteRtMetalAccelerator.dylib       → NOT embedded  ← see "GPU" below
```

Bumping flutter_gemma 0.16.5 → 1.1.0 did **not** fix the embedding (verified).

## Workaround (this repo)

A `post_install` build phase in `macos/Podfile` ("Embed flutter_gemma LiteRtLm
dylib") copies `libGemmaModelConstraintProvider.dylib` from the flutter_gemma
cache into the app's `Contents/Frameworks/` at build time and ad-hoc-signs it.
LiteRtLm resolves it there via its `@loader_path/../../..` rpath, so the
framework's own signature seal is untouched (placing it *inside* the framework
would invalidate that seal).

Also required: the `com.apple.security.network.client` entitlement (both
DebugProfile + Release) so the model can download at all — sandboxed apps need
it; without it the download fails with `Operation not permitted (errno=1)`.

Verified: with the dylib embedded, `DynamicLibrary.open(LiteRtLm)` succeeds.

## Caveats / follow-ups

- **Machine-local source.** The build phase reads from
  `~/Library/Caches/flutter_gemma/native/macos_arm64/`. Fine for local dev (the
  hook populates it during build). For **CI / distribution**, vendor the dylib
  into the repo and copy from there instead.
- **Release / notarization.** The loose dylib is ad-hoc signed (`codesign -s -`).
  A notarized release build must sign it with the real identity + hardened
  runtime; revisit then.
- **GPU inference.** `libLiteRtMetalAccelerator.dylib` is also unembedded. The
  framework *loads* without it (not a hard LC_LOAD_DYLIB), but Metal/GPU
  inference may dlopen it lazily and fail. If GPU backend errors appear, extend
  the build phase to copy it too.
- **Remove when fixed upstream.** File against
  https://github.com/DenisovAV/flutter_gemma — the macOS native-asset hook
  should embed LiteRtLm's sibling dylibs. Delete the Podfile phase once it does.
