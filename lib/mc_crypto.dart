import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'wire_message.dart';

/// Global ChaCha20-Poly1305 E2E compatible with marchat `shared.EncryptTextMessage` /
/// `DecryptTextMessage` (inner payload is JSON of a `Message` with plaintext content).
class MarchatGlobalE2E {
  MarchatGlobalE2E._(this._secretKey);

  final SecretKey _secretKey;
  static final Cipher _cipher = Chacha20.poly1305Aead();

  /// [keyMaterial] must be exactly 32 raw key bytes (same as decoded
  /// `MARCHAT_GLOBAL_E2E_KEY` / keystore global key).
  static MarchatGlobalE2E fromRawKey32(Uint8List keyMaterial) {
    if (keyMaterial.length != 32) {
      throw ArgumentError.value(
        keyMaterial.length,
        'keyMaterial',
        'global E2E key must be 32 bytes',
      );
    }
    return MarchatGlobalE2E._(SecretKeyData(keyMaterial));
  }

  static Uint8List? tryDecodeGlobalKeyBase64(String? b64) {
    if (b64 == null || b64.trim().isEmpty) return null;
    try {
      final k = base64Decode(b64.trim());
      if (k.length != 32) return null;
      return Uint8List.fromList(k);
    } catch (_) {
      return null;
    }
  }

  Future<ChatWireMessage> encryptOutgoingText(String sender, String plainText) async {
    final innerMap = <String, dynamic>{
      'sender': sender,
      'content': plainText,
      'type': WireTypes.text,
      'created_at': DateTime.now().toUtc().toIso8601String(),
    };
    final innerBytes = utf8.encode(jsonEncode(innerMap));
    final box = await _cipher.encrypt(
      innerBytes,
      secretKey: _secretKey,
    );
    final packed = box.concatenation();
    return ChatWireMessage(
      sender: sender,
      content: base64Encode(packed),
      createdAt: DateTime.now(),
      type: WireTypes.text,
      encrypted: true,
    );
  }

  Future<String> decryptIncomingTextPayload(String contentB64) async {
    final raw = base64Decode(contentB64.trim());
    final box = SecretBox.fromConcatenation(
      raw,
      nonceLength: _cipher.nonceLength,
      macLength: _cipher.macAlgorithm.macLength,
      copy: false,
    );
    final clear = await _cipher.decrypt(box, secretKey: _secretKey);
    final inner = jsonDecode(utf8.decode(clear)) as Map<String, dynamic>;
    return inner['content'] as String? ?? '';
  }

  /// Raw binary encrypt: nonce || ciphertext||tag (matches `KeyStore.EncryptRaw`).
  Future<Uint8List> encryptRaw(Uint8List data) async {
    final box = await _cipher.encrypt(
      data,
      secretKey: _secretKey,
    );
    return box.concatenation();
  }

  Future<Uint8List> decryptRaw(Uint8List packed) async {
    final box = SecretBox.fromConcatenation(
      packed,
      nonceLength: _cipher.nonceLength,
      macLength: _cipher.macAlgorithm.macLength,
      copy: false,
    );
    return Uint8List.fromList(await _cipher.decrypt(box, secretKey: _secretKey));
  }
}
