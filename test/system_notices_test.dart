import 'package:flutter_test/flutter_test.dart';
import 'package:marchat_flutter/system_notices.dart';

void main() {
  test('ephemeral System usage stays out of the transcript', () {
    expect(
      isTranscriptSystemMessage(
        sender: 'System',
        content: 'Unknown command: :foo',
        messageId: 0,
      ),
      isFalse,
    );
    expect(
      isTranscriptSystemNotice('Usage: :kick <user>'),
      isFalse,
    );
  });

  test('search, join, and kick notices stay in the transcript', () {
    expect(isTranscriptSystemNotice('Search results for foo:'), isTrue);
    expect(isTranscriptSystemNotice('$kSearchNoResultsPrefix foo'), isTrue);
    expect(isTranscriptSystemNotice('Joined channel #dev'), isTrue);
    expect(isTranscriptSystemNotice('alice has been kicked'), isTrue);
    expect(isTranscriptSystemNotice(kE2eSearchNoResultsHint), isTrue);
  });

  test('persisted System rows stay in the transcript', () {
    expect(
      isTranscriptSystemMessage(
        sender: 'System',
        content: 'Unknown command: :foo',
        messageId: 12,
      ),
      isTrue,
    );
  });

  test('non-System chat always stays in the transcript', () {
    expect(
      isTranscriptSystemMessage(
        sender: 'alice',
        content: 'hi',
        messageId: 0,
      ),
      isTrue,
    );
  });

  test('E2E search hint trigger', () {
    expect(shouldAppendE2eSearchHint('$kSearchNoResultsPrefix query'), isTrue);
    expect(shouldAppendE2eSearchHint('Search results for query:'), isFalse);
  });
}
