# Oracle Interpreter Phase 2 (Mobile Platform Config) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the oracle interpreter's mobile path (Qwen3 0.6B `.litertlm` via flutter_gemma) actually buildable/runnable on Android (arm64) and iOS (16+), per the spec's Phase 2.

**Architecture:** No Dart changes — the per-platform model spec already ships. This is platform config only: Android ABI restriction + optional OpenCL libs; iOS deployment target 16.0 + static frameworks + file sharing.

**Tech Stack:** Gradle Kotlin DSL, AndroidManifest, CocoaPods Podfile, Xcode pbxproj.

**Spec:** docs/superpowers/specs/2026-06-11-oracle-interpreter-design.md ("Phasing", Phase 2 PR).
**Branch:** `feat/interpreter-mobile` off `main`.

Constraints:
- `flutter test` stays green (254) and `flutter analyze --no-fatal-infos` stays at exactly 1 pre-existing info — config-only change, but run the gates anyway.
- Runtime device verification is best-effort (no physical device); the controller attempts an iOS-simulator runtime pass after the tasks. Disclose limits in the PR.

---

### Task 1: Android — arm64 ABI filter + OpenCL native libs

flutter_gemma's `.litertlm`/GPU paths are arm64-only; without the filter,
non-arm64 APK splits ship a broken interpreter. OpenCL entries let the GPU
delegate load on devices that have it (all `required="false"`).

**Files:**
- Modify: `android/app/build.gradle.kts` (defaultConfig block, ~line 18)
- Modify: `android/app/src/main/AndroidManifest.xml` (inside `<application>`, before `</application>` at line 33)

- [ ] **Step 1: build.gradle.kts** — append inside `defaultConfig { ... }`:

```kotlin
        // flutter_gemma's LiteRT-LM/GPU native paths are arm64-only; other
        // ABIs would ship a broken interpreter (spec: oracle-interpreter
        // phase 2).
        ndk {
            abiFilters += "arm64-v8a"
        }
```

(Kotlin DSL: `abiFilters` is a MutableSet<String>; `+=` works. If gradle
sync complains, use `abiFilters.add("arm64-v8a")`.)

- [ ] **Step 2: AndroidManifest.xml** — add immediately before `</application>`:

```xml
        <!-- Optional OpenCL for flutter_gemma's GPU delegate; CPU fallback
             exists, so none are required. -->
        <uses-native-library android:name="libOpenCL.so" android:required="false"/>
        <uses-native-library android:name="libOpenCL-car.so" android:required="false"/>
        <uses-native-library android:name="libOpenCL-pixel.so" android:required="false"/>
```

- [ ] **Step 3: Verify build + ABI contents**

Run: `flutter build apk --release` → succeeds.
Run: `unzip -l build/app/outputs/flutter-apk/app-release.apk | grep 'lib/' | awk '{print $4}' | cut -d/ -f2 | sort -u` → exactly `arm64-v8a`.

- [ ] **Step 4: Commit**

```bash
git add android/app/build.gradle.kts android/app/src/main/AndroidManifest.xml
git commit -m "feat: Android arm64 ABI filter + optional OpenCL libs for on-device interpreter"
```

---

### Task 2: iOS — platform 16.0, static frameworks, file sharing

flutter_gemma (MediaPipe GenAI pods) needs iOS 16+ and static linkage.
`UIFileSharingEnabled` exposes the app's Documents (where the model file
lives) in Finder/Files — required per the flutter_gemma setup, and useful
for clearing the 480 MB model.

**Files:**
- Modify: `ios/Podfile` (lines 1-2: commented platform; line 31: `use_frameworks!`)
- Modify: `ios/Runner/Info.plist` (add key inside the top-level `<dict>`)
- Modify: `ios/Runner.xcodeproj/project.pbxproj` (3× `IPHONEOS_DEPLOYMENT_TARGET = 13.0;` → `16.0;`)

- [ ] **Step 1: Podfile** — replace the commented platform line pair:

```ruby
# flutter_gemma (MediaPipe GenAI) requires iOS 16+.
platform :ios, '16.0'
```

and change `use_frameworks!` to:

```ruby
  use_frameworks! :linkage => :static
```

- [ ] **Step 2: Info.plist** — add inside the main `<dict>` (alphabetical placement near the other UI* keys is fine):

```xml
	<key>UIFileSharingEnabled</key>
	<true/>
```

- [ ] **Step 3: pbxproj** — replace all three `IPHONEOS_DEPLOYMENT_TARGET = 13.0;` with `IPHONEOS_DEPLOYMENT_TARGET = 16.0;` (sed is fine; verify count stays 3).

- [ ] **Step 4: Verify**

Run: `flutter build ios --simulator` → succeeds (runs `pod install` with the
new Podfile; this is the real check that static linkage + 16.0 resolve).
Commit `ios/Podfile.lock` if (re)generated.

- [ ] **Step 5: Commit**

```bash
git add ios/Podfile ios/Podfile.lock ios/Runner/Info.plist ios/Runner.xcodeproj/project.pbxproj
git commit -m "feat: iOS 16 deployment target, static frameworks, file sharing for on-device interpreter"
```

(If `flutter build ios --simulator` regenerated other ios/ files — e.g.
`ios/Flutter/` xcconfigs — include them; generated and expected.)

---

### Task 3: Gates + docs touch-up

- [ ] **Step 1:** `flutter test` → 254 green. `flutter analyze --no-fatal-infos` → 1 pre-existing info. `flutter build web` → still succeeds.

- [ ] **Step 2:** README.md — in the oracle-interpreter feature paragraph, the
"arm64 on mobile" claim is now real for local builds; append one sentence:

```
  Mobile builds target arm64 (Android) and iOS 16+.
```

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "docs: note mobile build targets for the interpreter"
```

---

## Verification (controller, after tasks)

1. Confirm APK ABI listing (Task 1 Step 3 output).
2. Best-effort runtime: launch the app on an iOS simulator (`flutter run -d <iphone-sim>`), open Interpret on a seeded result entry, confirm consent → download → (CPU) load reaches cards OR document precisely where the simulator path stops (simulators may lack the GPU delegate; CPU fallback should engage). Not a merge blocker — physical-device verification is explicitly out of reach; disclose in PR.
3. PR → CI green → squash-merge → roadmap.
