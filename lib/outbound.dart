import 'dart:io' show Platform;

/// Server rejects persistable NUL (`\x00`) with no broadcast (marchat v1.3.2).
String stripNul(String s) => s.replaceAll('\x00', '');

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

/// Exact token match used by the TUI (`text == cmd || HasPrefix(text, cmd+" ")`).
bool matchesColonCommand(String text, String cmd) {
  return text == cmd || text.startsWith('$cmd ');
}
