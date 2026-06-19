import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/state/interpreter.dart';

void main() {
  test('formatDownloadSize: MB under 1 GB, decimal GB above', () {
    expect(formatDownloadSize(475), '~475 MB');
    expect(formatDownloadSize(999), '~999 MB');
    expect(formatDownloadSize(1000), '~1.0 GB');
    expect(formatDownloadSize(2588), '~2.6 GB');
  });
}
