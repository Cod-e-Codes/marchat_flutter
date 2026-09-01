import 'package:flutter_test/flutter_test.dart';
import 'package:marchat_flutter/ws_close.dart';

void main() {
  test('1009 reconnects with file-size status', () {
    final d = interpretWsClose(kWsCloseMessageTooBig, 'Message too big');
    expect(d.reconnect, isTrue);
    expect(d.fileSizeError, isTrue);
    expect(d.statusText, 'file exceeds server size limit');
  });

  test('1008 does not reconnect and keeps close reason', () {
    final d = interpretWsClose(
      kWsClosePolicyViolation,
      'Username already taken - please choose a different username',
    );
    expect(d.reconnect, isFalse);
    expect(d.fileSizeError, isFalse);
    expect(d.statusText, contains('Username already taken'));
  });

  test('1002 does not reconnect', () {
    final d = interpretWsClose(kWsCloseProtocolError, 'bad handshake json');
    expect(d.reconnect, isFalse);
    expect(d.statusText, 'bad handshake json');
  });

  test('other closes reconnect', () {
    final d = interpretWsClose(1006, '');
    expect(d.reconnect, isTrue);
    expect(d.statusText, 'closed');
  });
}
