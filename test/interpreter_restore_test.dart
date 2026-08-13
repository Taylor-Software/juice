/// Two regressions from one device session (macOS, 2026-08-12):
///
/// 1. A downloaded model read as missing on every relaunch — the service
///    starts at needsDownload and only refresh() consults the disk, but
///    NOTHING called refresh().
/// 2. Tapping "Download model" then took warmUp's already-installed path
///    straight into _loadModel, whose GPU-first backend ladder SIGSEGV'd the
///    process inside LiteRT-LM (see interpreter_gemma.dart's ladder comment).
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loreseer/engine/emulator_data.dart';
import 'package:loreseer/engine/oracle.dart';
import 'package:loreseer/engine/oracle_data.dart';
import 'package:loreseer/engine/verdant_data.dart';
import 'package:loreseer/shared/home_shell.dart';
import 'package:loreseer/state/interpreter.dart';
import 'package:loreseer/state/interpreter_gemma.dart';
import 'package:loreseer/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_interpreter.dart';

Oracle _oracle() => Oracle(OracleData(
    jsonDecode(File('assets/oracle_data.json').readAsStringSync())
        as Map<String, dynamic>));

// Loaded from file, not rootBundle, which hangs the headless runner.
final _verdantOverride = verdantDataProvider.overrideWith((ref) async =>
    VerdantData(jsonDecode(File('assets/verdant_data.json').readAsStringSync())
        as Map<String, dynamic>));
final _emulatorOverride = emulatorDataProvider.overrideWith((ref) async =>
    EmulatorData(
        jsonDecode(File('assets/emulator_data.json').readAsStringSync())
            as Map<String, dynamic>));

void main() {
  group('backendsFor', () {
    test('Apple platforms are CPU-only', () {
      for (final p in [TargetPlatform.iOS, TargetPlatform.macOS]) {
        expect(GemmaInterpreterService.backendsFor(p),
            const [PreferredBackend.cpu],
            reason: '$p must never attempt the GPU backend');
      }
    });

    test('other platforms try GPU first, then CPU', () {
      for (final p in [
        TargetPlatform.android,
        TargetPlatform.linux,
        TargetPlatform.windows,
      ]) {
        expect(GemmaInterpreterService.backendsFor(p),
            const [PreferredBackend.gpu, PreferredBackend.cpu]);
      }
    });
  });

  group('model restore on launch', () {
    testWidgets('refreshes the interpreter when AI is enabled', (t) async {
      SharedPreferences.setMockInitialValues({'loreseer.ai_enabled.v1': true});
      final fake = FakeInterpreterService();
      await t.pumpWidget(ProviderScope(
        overrides: [
          _verdantOverride,
          _emulatorOverride,
          interpreterServiceProvider.overrideWithValue(fake),
        ],
        child: MaterialApp(home: HomeShell(oracle: _oracle())),
      ));
      await t.pumpAndSettle();
      expect(fake.refreshCalls, 1);
    });

    testWidgets('leaves the interpreter alone when AI is off', (t) async {
      SharedPreferences.setMockInitialValues({});
      final fake = FakeInterpreterService();
      await t.pumpWidget(ProviderScope(
        overrides: [
          _verdantOverride,
          _emulatorOverride,
          interpreterServiceProvider.overrideWithValue(fake),
        ],
        child: MaterialApp(home: HomeShell(oracle: _oracle())),
      ));
      await t.pumpAndSettle();
      expect(fake.refreshCalls, 0);
    });
  });
}
