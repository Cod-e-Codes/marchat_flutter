// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:marchat_flutter/main.dart';

void main() {
  testWidgets('Marchat app loads configuration screen', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(MarchatApp());

    // Verify that the configuration screen loads
    expect(find.text('marchat - Configuration'), findsOneWidget);
    expect(find.text('Username'), findsOneWidget);
    expect(find.text('Server URL'), findsOneWidget);
    expect(find.text('Connect'), findsOneWidget);
  });
}
