/// Matches marchat TUI `searchNoResultsPrefix` / `e2eSearchNoResultsHint`.
const String kSearchNoResultsPrefix = 'No results found for:';
const String kE2eSearchNoResultsHint =
    'With E2E enabled, server search matches stored ciphertext, not decrypted plaintext in chat.';

/// Whether a System line belongs in the scrollable transcript (TUI `isTranscriptSystemNotice`).
bool isTranscriptSystemNotice(String content) {
  final c = content.trim();
  if (c.isEmpty) return false;
  final cl = c.toLowerCase();
  if (c == kE2eSearchNoResultsHint) return true;
  if (c.contains('\n')) return true;
  if (cl.startsWith('search results for ')) return true;
  if (cl.startsWith(kSearchNoResultsPrefix.toLowerCase())) return true;
  if (cl.startsWith('pinned messages')) return true;
  if (cl == 'no pinned messages') return true;
  if (cl.startsWith('active channels:')) return true;
  if (cl.startsWith('joined channel #')) return true;
  if (cl.startsWith('left #')) return true;
  if (cl.startsWith('chat history cleared')) return true;
  if (cl.startsWith('you have been kicked')) return true;
  if (cl.startsWith('message ') &&
      (cl.contains(' pinned by ') || cl.contains(' unpinned by '))) {
    return true;
  }
  if (cl.contains('has been kicked')) return true;
  if (cl.contains('permanently banned')) return true;
  if (cl.contains('has been unbanned')) return true;
  if (cl.contains('forcibly disconnected')) return true;
  if (cl.startsWith('available themes:')) return true;
  if (cl.startsWith('dm conversations:')) return true;
  return false;
}

/// Whether a wire/local message belongs in the transcript (TUI `isTranscriptSystemMessage`).
bool isTranscriptSystemMessage({
  required String sender,
  required String content,
  required int messageId,
}) {
  if (sender != 'System') return true;
  if (messageId < 0) return isTranscriptSystemNotice(content);
  if (messageId > 0) return true;
  return isTranscriptSystemNotice(content);
}

bool shouldAppendE2eSearchHint(String content) {
  return content.trim().startsWith(kSearchNoResultsPrefix);
}
