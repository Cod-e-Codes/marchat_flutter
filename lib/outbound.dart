import 'dart:convert';
import 'dart:io' show Platform;

/// Server rejects persistable NUL (`\x00`) with no broadcast (marchat v1.3.2).
String stripNul(String s) => s.replaceAll('\x00', '');

/// Chat `content` cap when neither message env var is set (marchat v1.3.8).
const int kDefaultMaxMessageBytes = 32 * 1024;

/// Thrown after the composer banner is shown so the draft stays in the field.
class MessageTooLarge implements Exception {
  const MessageTooLarge();
}

/// TUI file cap: `MARCHAT_MAX_FILE_BYTES`, else `MARCHAT_MAX_FILE_MB`, else 1 MiB.
int maxFileBytesFromEnv([Map<String, String>? env]) {
  final e = env ?? Platform.environment;
  final bytesRaw = e['MARCHAT_MAX_FILE_BYTES']?.trim() ?? '';
  if (bytesRaw.isNotEmpty) {
    final v = int.tryParse(bytesRaw);
    if (v != null && v > 0) return v;
  }
  final mbRaw = e['MARCHAT_MAX_FILE_MB']?.trim() ?? '';
  if (mbRaw.isNotEmpty) {
    final v = int.tryParse(mbRaw);
    if (v != null && v > 0) return v * 1024 * 1024;
  }
  return 1024 * 1024;
}

String formatFileLimit(int maxBytes) {
  if (maxBytes % (1024 * 1024) == 0) {
    return '${maxBytes ~/ (1024 * 1024)}MB';
  }
  return '$maxBytes bytes';
}

/// TUI chat cap: `MARCHAT_MAX_MESSAGE_BYTES`, else `MARCHAT_MAX_MESSAGE_MB`, else 32 KiB.
/// A present value that does not parse or is not positive falls back to the default.
/// Bytes wins when both are set. An invalid bytes value does not fall through to MB.
int maxMessageBytesFromEnv([Map<String, String>? env]) {
  final e = env ?? Platform.environment;
  final bytesRaw = e['MARCHAT_MAX_MESSAGE_BYTES']?.trim() ?? '';
  if (bytesRaw.isNotEmpty) {
    final v = int.tryParse(bytesRaw);
    if (v != null && v > 0) return v;
    return kDefaultMaxMessageBytes;
  }
  final mbRaw = e['MARCHAT_MAX_MESSAGE_MB']?.trim() ?? '';
  if (mbRaw.isNotEmpty) {
    final v = int.tryParse(mbRaw);
    if (v != null && v > 0) return v * 1024 * 1024;
    return kDefaultMaxMessageBytes;
  }
  return kDefaultMaxMessageBytes;
}

/// UTF-8 byte length of wire `content`. A length equal to the cap is allowed.
bool contentExceedsMessageLimit(String content, [Map<String, String>? env]) {
  return utf8.encode(content).length > maxMessageBytesFromEnv(env);
}

/// Same rendering as Go `shared.FormatMessageLimit`.
String formatMessageLimit(int n) {
  if (n <= 0) n = kDefaultMaxMessageBytes;
  const oneMb = 1024 * 1024;
  const oneKib = 1024;
  if (n % oneMb == 0) {
    return '${(n / oneMb).toStringAsFixed(1)} MB';
  }
  if (n % oneKib == 0) {
    return '${n ~/ oneKib} KiB';
  }
  return '$n bytes';
}

String messageTooLargeBanner([Map<String, String>? env]) {
  return '[ERROR] Message too large (max ${formatMessageLimit(maxMessageBytesFromEnv(env))})';
}

/// Exact token match used by the TUI (`text == cmd || HasPrefix(text, cmd+" ")`).
bool matchesColonCommand(String text, String cmd) {
  return text == cmd || text.startsWith('$cmd ');
}
