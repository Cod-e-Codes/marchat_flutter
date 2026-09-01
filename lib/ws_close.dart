/// RFC 6455 close codes used by the marchat server handshake and file-size path.
const int kWsCloseProtocolError = 1002;
const int kWsClosePolicyViolation = 1008;
const int kWsCloseMessageTooBig = 1009;

/// How the GUI should treat a finished WebSocket (TUI: `client/websocket.go`).
class WsCloseDecision {
  final String statusText;
  final bool reconnect;
  final bool fileSizeError;

  const WsCloseDecision({
    required this.statusText,
    required this.reconnect,
    this.fileSizeError = false,
  });
}

/// Maps a close frame to status text and whether to retry.
///
/// 1009: file too big, reconnect after a banner (TUI v1.3.3).
/// 1008 / 1002: handshake policy or protocol reject; do not reconnect.
WsCloseDecision interpretWsClose(int? code, String? reason) {
  final r = (reason ?? '').trim();
  if (code == kWsCloseMessageTooBig) {
    return const WsCloseDecision(
      statusText: 'file exceeds server size limit',
      reconnect: true,
      fileSizeError: true,
    );
  }
  if (code == kWsClosePolicyViolation || code == kWsCloseProtocolError) {
    return WsCloseDecision(
      statusText: r.isNotEmpty ? r : 'connection rejected (close $code)',
      reconnect: false,
    );
  }
  return WsCloseDecision(
    statusText: r.isNotEmpty ? r : 'closed',
    reconnect: true,
  );
}
