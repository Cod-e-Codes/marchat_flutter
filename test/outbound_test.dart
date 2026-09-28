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

  test('maxMessageBytesFromEnv default, bytes over MB, invalid falls back', () {
    expect(maxMessageBytesFromEnv({}), kDefaultMaxMessageBytes);
    expect(maxMessageBytesFromEnv({}), 32 * 1024);
    expect(
      maxMessageBytesFromEnv({
        'MARCHAT_MAX_MESSAGE_BYTES': '100',
        'MARCHAT_MAX_MESSAGE_MB': '2',
      }),
      100,
    );
    expect(maxMessageBytesFromEnv({'MARCHAT_MAX_MESSAGE_MB': '2'}), 2 * 1024 * 1024);
    expect(
      maxMessageBytesFromEnv({
        'MARCHAT_MAX_MESSAGE_BYTES': '0',
        'MARCHAT_MAX_MESSAGE_MB': '2',
      }),
      kDefaultMaxMessageBytes,
    );
    expect(
      maxMessageBytesFromEnv({'MARCHAT_MAX_MESSAGE_MB': 'nope'}),
      kDefaultMaxMessageBytes,
    );
  });

  test('contentExceedsMessageLimit uses UTF-8 bytes and allows the cap', () {
    const env = {'MARCHAT_MAX_MESSAGE_BYTES': '4'};
    expect(contentExceedsMessageLimit('abcd', env), isFalse);
    expect(contentExceedsMessageLimit('abcde', env), isTrue);
    expect(contentExceedsMessageLimit('éé', {'MARCHAT_MAX_MESSAGE_BYTES': '4'}), isFalse);
    expect(contentExceedsMessageLimit('ééx', {'MARCHAT_MAX_MESSAGE_BYTES': '4'}), isTrue);
    expect(contentExceedsMessageLimit('hi', {}), isFalse);
  });

  test('formatMessageLimit and banner match the TUI', () {
    expect(formatMessageLimit(0), '32 KiB');
    expect(formatMessageLimit(32 * 1024), '32 KiB');
    expect(formatMessageLimit(1024 * 1024), '1.0 MB');
    expect(formatMessageLimit(100), '100 bytes');
    expect(
      messageTooLargeBanner({'MARCHAT_MAX_MESSAGE_BYTES': '4'}),
      '[ERROR] Message too large (max 4 bytes)',
    );
  });

  test('matchesColonCommand does not swallow longer tokens', () {
    expect(matchesColonCommand(':dm alice hi', ':dm'), isTrue);
    expect(matchesColonCommand(':dm', ':dm'), isTrue);
    expect(matchesColonCommand(':dms', ':dm'), isFalse);
    expect(matchesColonCommand(':dmhide bob', ':dm'), isFalse);
  });
}
