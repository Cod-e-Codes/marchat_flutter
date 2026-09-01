import 'package:flutter_test/flutter_test.dart';
import 'package:marchat_flutter/reaction_aliases.dart';

void main() {
  test('resolveReactionEmoji maps TUI aliases including thumbsup', () {
    expect(resolveReactionEmoji('+1'), '👍');
    expect(resolveReactionEmoji('thumbsup'), '👍');
    expect(resolveReactionEmoji('THUMBSDOWN'), '👎');
    expect(resolveReactionEmoji('heart'), '❤️');
    expect(resolveReactionEmoji('🚀'), '🚀');
  });
}
