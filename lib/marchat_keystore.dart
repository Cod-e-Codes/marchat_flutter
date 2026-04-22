import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// Reads marchat `keystore.dat` (same on-disk format as `client/crypto/keystore.go`):
/// - **v3:** `marchatk` (8) || `0x03` (1) || PBKDF2 salt (16) || AES-GCM ciphertext
/// - **legacy v2:** raw AES-GCM; PBKDF2 salt is UTF-8 bytes of the **absolute keystore path**
///
/// PBKDF2: HMAC-SHA256, **100_000** iterations, **32** byte key. Inner JSON:
/// `{"global_key":{"key":"<base64 32 bytes>",...},"version":"2.0"}`.
class MarchatKeystoreException implements Exception {
  MarchatKeystoreException(this.message);
  final String message;
  @override
  String toString() => message;
}

abstract final class MarchatKeystore {
  static const _magic = [
    0x6d,
    0x61,
    0x72,
    0x63,
    0x68,
    0x61,
    0x74,
    0x6b,
  ]; // "marchatk"
  static const _formatV3 = 3;
  static const _headerLen = 8 + 1 + 16;

  static final _pbkdf2 = Pbkdf2.hmacSha256(iterations: 100000, bits: 256);
  static final _aesGcm = AesGcm.with256bits();

  /// [keystorePathForLegacy] must match the Go client's resolved path string for v2 files.
  static Future<Uint8List> unlockToGlobalKey32({
    required Uint8List fileBytes,
    required String passphrase,
    required String keystorePathForLegacy,
  }) async {
    if (fileBytes.isEmpty) {
      throw MarchatKeystoreException('Keystore file is empty');
    }

    Uint8List plaintext;
    if (_isV3(fileBytes)) {
      final salt = fileBytes.sublist(9, _headerLen);
      final payload = fileBytes.sublist(_headerLen);
      final dk = await _deriveKey(utf8.encode(passphrase), salt);
      plaintext = await _aesGcmDecrypt(dk, payload);
    } else {
      final salt = utf8.encode(keystorePathForLegacy);
      final dk = await _deriveKey(utf8.encode(passphrase), salt);
      plaintext = await _aesGcmDecrypt(dk, fileBytes);
    }

    return _extractGlobalKey32(plaintext);
  }

  static bool _isV3(Uint8List b) {
    if (b.length < _headerLen) return false;
    for (var i = 0; i < 8; i++) {
      if (b[i] != _magic[i]) return false;
    }
    return b[8] == _formatV3;
  }

  static Future<SecretKey> _deriveKey(List<int> passphrase, List<int> salt) {
    return _pbkdf2.deriveKey(secretKey: SecretKey(passphrase), nonce: salt);
  }

  /// Go `decryptData`: nonce || ciphertext+tag (nonce length = GCM nonce size).
  static Future<Uint8List> _aesGcmDecrypt(
    SecretKey aesKey,
    Uint8List blob,
  ) async {
    try {
      final box = SecretBox.fromConcatenation(
        blob,
        nonceLength: _aesGcm.nonceLength,
        macLength: _aesGcm.macAlgorithm.macLength,
        copy: false,
      );
      final clear = await _aesGcm.decrypt(box, secretKey: aesKey);
      return Uint8List.fromList(clear);
    } catch (e) {
      throw MarchatKeystoreException(
        'Keystore decrypt failed (wrong passphrase or corrupt file): $e',
      );
    }
  }

  static Uint8List _extractGlobalKey32(Uint8List plaintext) {
    Map<String, dynamic> json;
    try {
      json = jsonDecode(utf8.decode(plaintext)) as Map<String, dynamic>;
    } catch (e) {
      throw MarchatKeystoreException('Keystore JSON parse failed: $e');
    }
    final gk = json['global_key'];
    if (gk is! Map<String, dynamic>) {
      throw MarchatKeystoreException('Keystore missing global_key');
    }
    final keyField = gk['key'];
    final Uint8List raw;
    if (keyField is String) {
      raw = Uint8List.fromList(base64Decode(keyField));
    } else if (keyField is List) {
      raw = Uint8List.fromList(keyField.cast<int>());
    } else {
      throw MarchatKeystoreException(
        'Keystore global_key.key has invalid type',
      );
    }
    if (raw.length != 32) {
      throw MarchatKeystoreException(
        'Global key must be 32 bytes, got ${raw.length}',
      );
    }
    return raw;
  }
}
