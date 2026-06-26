import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/state/interpreter.dart';

void main() {
  group('formatDownloadSize', () {
    test('under 1 GB shows MB', () {
      expect(formatDownloadSize(0), '~0 MB');
      expect(formatDownloadSize(500), '~500 MB');
      expect(formatDownloadSize(999), '~999 MB');
    });

    test('at 1 GB shows one-decimal GB', () {
      expect(formatDownloadSize(1000), '~1.0 GB');
    });

    test('above 1 GB shows one-decimal GB', () {
      expect(formatDownloadSize(2600), '~2.6 GB');
      expect(formatDownloadSize(10000), '~10.0 GB');
    });
  });

  group('InterpreterStatus', () {
    test('default progress and message are zero/empty', () {
      const s = InterpreterStatus(InterpreterPhase.loading);
      expect(s.phase, InterpreterPhase.loading);
      expect(s.progress, 0);
      expect(s.message, '');
    });

    test('carries progress and message when provided', () {
      const s = InterpreterStatus(
        InterpreterPhase.installing,
        progress: 42,
        message: 'Downloading…',
      );
      expect(s.progress, 42);
      expect(s.message, 'Downloading…');
    });

    test('error phase carries message', () {
      const s = InterpreterStatus(
        InterpreterPhase.error,
        message: 'Load failed',
      );
      expect(s.phase, InterpreterPhase.error);
      expect(s.message, 'Load failed');
    });
  });
}
