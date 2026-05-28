import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:marchat_flutter/mc_crypto.dart';
import 'package:marchat_flutter/wire_message.dart';

Uint8List _testKey() => Uint8List.fromList(List<int>.generate(32, (i) => i));

void main() {
  group('MarchatGlobalE2E', () {
    late MarchatGlobalE2E e2e;

    setUp(() {
      e2e = MarchatGlobalE2E.fromRawKey32(_testKey());
    });

    test('encrypted DM uses outer dm type and recipient', () async {
      final msg = await e2e.encryptOutgoingText(
        'alice',
        'hello dm',
        outerType: WireTypes.dm,
        recipient: 'bob',
      );
      expect(msg.type, WireTypes.dm);
      expect(msg.recipient, 'bob');
      expect(msg.encrypted, isTrue);
      expect(msg.sender, 'alice');
      expect(msg.content, isNotEmpty);
      expect(msg.content, isNot(contains('hello dm')));

      final plain = await e2e.decryptIncomingTextPayload(msg.content);
      expect(plain, 'hello dm');
    });

    test('encrypted channel text omits recipient', () async {
      final msg = await e2e.encryptOutgoingText('alice', 'hello channel');
      expect(msg.type, WireTypes.text);
      expect(msg.recipient, isEmpty);
      expect(msg.encrypted, isTrue);

      final plain = await e2e.decryptIncomingTextPayload(msg.content);
      expect(plain, 'hello channel');
    });

    test('encrypt/decrypt round-trip for DM ciphertext', () async {
      final msg = await e2e.encryptOutgoingText(
        'alice',
        'secret',
        outerType: WireTypes.dm,
        recipient: 'bob',
      );
      final plain = await e2e.decryptIncomingTextPayload(msg.content);
      expect(plain, 'secret');
    });
  });
}
