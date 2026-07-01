import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/oracle_interpreter.dart';
import 'package:juice_oracle/state/cloud_interpreter.dart';
import 'package:juice_oracle/state/interpreter.dart';

import 'fake_interpreter.dart';

class _StubCloud implements CloudInterpreter {
  _StubCloud(this.result);
  final List<OracleInterpretation> result;
  OracleSeed? lastSeed;
  String? lastKey;

  @override
  Future<List<OracleInterpretation>> interpret(
      OracleSeed seed, String apiKey) async {
    lastSeed = seed;
    lastKey = apiKey;
    return result;
  }
}

void main() {
  const cloudResult = [OracleInterpretation(lens: 'literal', reading: 'cloud')];

  test('cloud disabled -> delegates to on-device', () async {
    final onDevice = FakeInterpreterService();
    final cloud = _StubCloud(cloudResult);
    final routing = RoutingInterpreterService(
      onDevice,
      cloudEnabled: () => false,
      cloudApiKey: () async => 'sk-ant-present',
      cloudInterpreter: cloud,
    );
    final result = await routing.interpret(const OracleSeed(resultText: 'x'));
    expect(onDevice.interpretCalls, 1);
    expect(cloud.lastSeed, isNull);
    expect(result.first.reading, 'fallback'); // FakeInterpreterService default
  });

  test('cloud enabled but no key -> delegates to on-device', () async {
    final onDevice = FakeInterpreterService();
    final cloud = _StubCloud(cloudResult);
    final routing = RoutingInterpreterService(
      onDevice,
      cloudEnabled: () => true,
      cloudApiKey: () async => null,
      cloudInterpreter: cloud,
    );
    await routing.interpret(const OracleSeed(resultText: 'x'));
    expect(onDevice.interpretCalls, 1);
    expect(cloud.lastSeed, isNull);
  });

  test('cloud enabled with a key -> routes to cloud, not on-device', () async {
    final onDevice = FakeInterpreterService();
    final cloud = _StubCloud(cloudResult);
    final routing = RoutingInterpreterService(
      onDevice,
      cloudEnabled: () => true,
      cloudApiKey: () async => 'sk-ant-present',
      cloudInterpreter: cloud,
    );
    const seed = OracleSeed(resultText: 'x');
    final result = await routing.interpret(seed);
    expect(onDevice.interpretCalls, 0);
    expect(cloud.lastSeed, same(seed));
    expect(cloud.lastKey, 'sk-ant-present');
    expect(result.first.reading, 'cloud');
  });

  test('every other method delegates straight through to on-device', () async {
    final onDevice = FakeInterpreterService();
    final routing = RoutingInterpreterService(
      onDevice,
      cloudEnabled: () => true,
      cloudApiKey: () async => 'sk-ant-present',
      cloudInterpreter: _StubCloud(cloudResult),
    );
    expect(routing.status, same(onDevice.status));
    expect(routing.downloadLabel, onDevice.downloadLabel);
    await routing.refresh();
    await routing.warmUp();
    await routing.voiceLine(const VoiceSeed(line: 'y', mood: 'default'));
    await routing.summarize(const ['a']);
    await routing.gmChat(const GmChatSeed(history: []));
    await routing.narrate(const NarrateSeed(mode: NarrateMode.continueScene));
    await routing.fleshOut(const FleshOutSeed(entityKind: 'npc', name: 'x'));
    await routing.rankSuggestions(const RankSuggestionsSeed(candidates: []));
    await routing.dispose();
    expect(onDevice.refreshCalls, 1);
    expect(onDevice.warmUpCalls, 1);
    expect(onDevice.voiceCalls, 1);
    expect(onDevice.summaryCalls, 1);
    expect(onDevice.gmChatCalls, 1);
    expect(onDevice.narrateCalls, 1);
    expect(onDevice.fleshOutCalls, 1);
    expect(onDevice.rankCalls, 1);
    expect(onDevice.disposeCalls, 1);
  });
}
