import 'package:flutter_test/flutter_test.dart';
import 'package:marchat_flutter/reaction_state.dart';

void main() {
  test('parseWireTargetId', () {
    expect(parseWireTargetId(42), 42);
    expect(parseWireTargetId(42.0), 42);
    expect(parseWireTargetId(null), isNull);
    expect(parseWireTargetId('x'), isNull);
  });

  test('applyMarchatReactionUpdate add and remove', () {
    final m = <int, Map<String, Set<String>>>{};
    applyMarchatReactionUpdate(
      byTarget: m,
      sender: 'alice',
      reaction: {'emoji': 'A', 'target_id': 10},
    );
    applyMarchatReactionUpdate(
      byTarget: m,
      sender: 'bob',
      reaction: {'emoji': 'A', 'target_id': 10},
    );
    expect(formatReactionSummary(m, 10), 'A 2');

    applyMarchatReactionUpdate(
      byTarget: m,
      sender: 'alice',
      reaction: {'emoji': 'A', 'target_id': 10, 'is_removal': true},
    );
    expect(formatReactionSummary(m, 10), 'A 1');

    applyMarchatReactionUpdate(
      byTarget: m,
      sender: 'bob',
      reaction: {'emoji': 'A', 'target_id': 10, 'is_removal': true},
    );
    expect(formatReactionSummary(m, 10), isNull);
    expect(m.isEmpty, isTrue);
  });
}
