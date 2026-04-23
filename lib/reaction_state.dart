// In-memory reaction aggregation for marchat wire messages (same role as
// `reactions map[int64]map[string]map[string]bool` in marchat `client/main.go`).

int? parseWireTargetId(dynamic v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is num) return v.toInt();
  return null;
}

/// Applies one `type: reaction` envelope: [reaction] holds `emoji`, `target_id`,
/// and optional `is_removal` (Go `shared.ReactionMeta`).
void applyMarchatReactionUpdate({
  required Map<int, Map<String, Set<String>>> byTarget,
  required String sender,
  required Map<String, dynamic>? reaction,
}) {
  if (reaction == null) return;
  final tid = parseWireTargetId(reaction['target_id']);
  if (tid == null || tid == 0) return;
  final emoji = reaction['emoji'] as String? ?? '';
  if (emoji.isEmpty) return;
  final removal = reaction['is_removal'] == true;

  if (removal) {
    final byEmoji = byTarget[tid];
    if (byEmoji == null) return;
    final reactors = byEmoji[emoji];
    if (reactors == null) return;
    reactors.remove(sender);
    if (reactors.isEmpty) {
      byEmoji.remove(emoji);
    }
    if (byEmoji.isEmpty) {
      byTarget.remove(tid);
    }
    return;
  }

  byTarget.putIfAbsent(tid, () => <String, Set<String>>{});
  byTarget[tid]!.putIfAbsent(emoji, () => <String>{});
  byTarget[tid]![emoji]!.add(sender);
}

/// One line under a message, TUI-style: `emoji count  emoji count`.
String? formatReactionSummary(
  Map<int, Map<String, Set<String>>> byTarget,
  int messageId,
) {
  if (messageId == 0) return null;
  final byEmoji = byTarget[messageId];
  if (byEmoji == null || byEmoji.isEmpty) return null;
  final emojis = byEmoji.keys.toList()..sort();
  final parts = <String>[];
  for (final e in emojis) {
    final n = byEmoji[e]!.length;
    if (n > 0) {
      parts.add('$e $n');
    }
  }
  if (parts.isEmpty) return null;
  return parts.join('  ');
}
