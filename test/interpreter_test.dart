import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:juice_oracle/engine/oracle_interpreter.dart';
import 'package:juice_oracle/state/interpreter.dart';

import 'fake_interpreter.dart';

void main() {
  test('InterpreterStatus equality + progress default', () {
    const a = InterpreterStatus(InterpreterPhase.installing, progress: 40);
    expect(a.phase, InterpreterPhase.installing);
    expect(a.progress, 40);
    expect(const InterpreterStatus(InterpreterPhase.ready).progress, 0);
    expect(
        const InterpreterStatus(InterpreterPhase.error, message: 'x').message,
        'x');
  });

  test('interpreterServiceProvider is overridable with the fake', () {
    final fake = FakeInterpreterService();
    final c = ProviderContainer(overrides: [
      interpreterServiceProvider.overrideWithValue(fake),
    ]);
    addTearDown(c.dispose);
    expect(c.read(interpreterServiceProvider), same(fake));
  });

  // -- buildSummaryPrompt / parseSummary --------------------------------------

  test('buildSummaryPrompt includes both entries and a recap instruction', () {
    final prompt =
        buildSummaryPrompt(['We entered the keep.', 'The gate fell.']);
    expect(prompt, contains('We entered the keep.'));
    expect(prompt, contains('The gate fell.'));
    expect(prompt.toLowerCase(), contains('recap'));
  });

  test('buildSummaryPrompt caps at 20 entries (oldest-first tail)', () {
    final entries = List.generate(25, (i) => 'entry $i');
    final prompt = buildSummaryPrompt(entries);
    // First 5 should be dropped; last 20 kept.
    expect(prompt, isNot(contains('entry 0')));
    expect(prompt, contains('entry 5'));
    expect(prompt, contains('entry 24'));
  });

  test('buildSummaryPrompt flattens and caps each entry', () {
    // A pasted multi-paragraph epic must neither break the bullet structure
    // nor eat the generation window (kPromptMaxFieldChars per entry).
    final long = 'saga ${'x' * 600}';
    final prompt = buildSummaryPrompt(['Line one\n\nline two', long]);
    expect(prompt, contains('- Line one line two'));
    expect(prompt, isNot(contains(long)));
    expect(prompt, contains('…'));
  });

  test('parseSummary strips think tags and trims', () {
    expect(parseSummary('<think>internal</think> The party fled.'),
        'The party fled.');
    expect(parseSummary('  plain text  '), 'plain text');
    expect(
        parseSummary('<think>multi\nline\nthought</think>\nActual recap here.'),
        'Actual recap here.');
  });

  // -- FakeInterpreterService.summarize scripting -----------------------------

  test('fake summarize returns queued summary and records entries', () async {
    final fake = FakeInterpreterService(
        initial: const InterpreterStatus(InterpreterPhase.ready));
    fake.queuedSummary.add('Recap text');
    final result = await fake.summarize(['entry a', 'entry b']);
    expect(result, 'Recap text');
    expect(fake.lastSummaryEntries, ['entry a', 'entry b']);
    expect(fake.summaryCalls, 1);
  });

  test('fake summarize returns canned string when queue is empty', () async {
    final fake = FakeInterpreterService(
        initial: const InterpreterStatus(InterpreterPhase.ready));
    final result = await fake.summarize(['x']);
    expect(result, 'A canned recap.');
  });

  test('fake summarize throws summaryError when set', () async {
    final fake = FakeInterpreterService(
        initial: const InterpreterStatus(InterpreterPhase.ready));
    fake.summaryError = Exception('model error');
    expect(() => fake.summarize(['x']), throwsException);
  });
}
