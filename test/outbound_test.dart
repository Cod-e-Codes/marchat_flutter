import 'package:flutter_test/flutter_test.dart';
import 'package:marchat_flutter/outbound.dart';

void main() {
  test('stripNul removes NUL bytes', () {
    expect(stripNul('before\x00after'), 'beforeafter');
    expect(stripNul('clean'), 'clean');
    expect(stripNul('\x00'), '');
  });

  test('maxFileBytesFromEnv default and env overrides', () {
    expect(maxFileBytesFromEnv({}), 1024 * 1024);
    expect(maxFileBytesFromEnv({'MARCHAT_MAX_FILE_BYTES': '2048'}), 2048);
    expect(maxFileBytesFromEnv({'MARCHAT_MAX_FILE_MB': '2'}), 2 * 1024 * 1024);
    expect(
      maxFileBytesFromEnv({
        'MARCHAT_MAX_FILE_BYTES': '100',
        'MARCHAT_MAX_FILE_MB': '9',
      }),
      100,
    );
  });

  test('formatFileLimit', () {
    expect(formatFileLimit(1024 * 1024), '1MB');
    expect(formatFileLimit(100), '100 bytes');
  });

  test('matchesColonCommand does not swallow longer tokens', () {
    expect(matchesColonCommand(':dm alice hi', ':dm'), isTrue);
    expect(matchesColonCommand(':dm', ':dm'), isTrue);
    expect(matchesColonCommand(':dms', ':dm'), isFalse);
    expect(matchesColonCommand(':dmhide bob', ':dm'), isFalse);
  });
}
