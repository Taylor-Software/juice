import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/models.dart';
import 'package:juice_oracle/engine/system_primer.dart';
import 'package:juice_oracle/state/providers.dart';

void main() {
  test('systemPrimerProvider resolves dnd from the active session', () async {
    final container = ProviderContainer(overrides: [
      sessionsProvider.overrideWith(() => _FakeSessions(
            const SessionMeta(id: 's1', name: 'C', systems: ['dnd']),
          )),
      rulesetsProvider.overrideWith(() => _FakeRulesets(const {'classic'})),
    ]);
    addTearDown(container.dispose);
    await container.read(sessionsProvider.future);
    await container.read(rulesetsProvider.future);
    expect(container.read(systemPrimerProvider), kSystemPrimers['dnd']);
  });

  test('systemPrimerProvider refines ironsworn family by ruleset', () async {
    final container = ProviderContainer(overrides: [
      sessionsProvider.overrideWith(() => _FakeSessions(
            const SessionMeta(id: 's1', name: 'C', systems: ['ironsworn']),
          )),
      rulesetsProvider.overrideWith(() => _FakeRulesets(const {'starforged'})),
    ]);
    addTearDown(container.dispose);
    await container.read(sessionsProvider.future);
    await container.read(rulesetsProvider.future);
    expect(container.read(systemPrimerProvider), kSystemPrimers['starforged']);
  });

  test('systemPrimerProvider is empty for a non-TTRPG campaign', () async {
    final container = ProviderContainer(overrides: [
      sessionsProvider.overrideWith(() => _FakeSessions(
            const SessionMeta(
                id: 's1', name: 'C', systems: ['juice', 'mythic']),
          )),
      rulesetsProvider.overrideWith(() => _FakeRulesets(const {})),
    ]);
    addTearDown(container.dispose);
    await container.read(sessionsProvider.future);
    await container.read(rulesetsProvider.future);
    expect(container.read(systemPrimerProvider), '');
  });
}

class _FakeSessions extends SessionsNotifier {
  _FakeSessions(this._meta);
  final SessionMeta _meta;
  @override
  Future<SessionsState> build() async =>
      SessionsState(active: _meta.id, sessions: [_meta]);
}

class _FakeRulesets extends RulesetsNotifier {
  _FakeRulesets(this._enabled);
  final Set<String> _enabled;
  @override
  Future<Set<String>> build() async => _enabled;
}
