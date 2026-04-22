/// Same tokens as `reactionAliases` in marchat `client/render.go`.
final Map<String, String> kReactionAliases = {
  '+1': '👍',
  '-1': '👎',
  'heart': '❤️',
  'laugh': '😂',
  'fire': '🔥',
  'party': '🎉',
  'eyes': '👀',
  'check': '✅',
  'x': '❌',
  'think': '🤔',
  'clap': '👏',
  'rocket': '🚀',
  'wave': '👋',
  '100': '💯',
  'sad': '😢',
  'wow': '😮',
  'angry': '😡',
  'skull': '💀',
  'pray': '🙏',
  'star': '⭐',
};

String resolveReactionEmoji(String input) {
  final e = kReactionAliases[input.toLowerCase()];
  return e ?? input;
}
