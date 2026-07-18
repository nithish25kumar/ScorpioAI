// Basic smoke test: verifies the chat screen renders its core widgets.
//
// Run with: flutter test

import 'package:chatbot_app/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('ChatScreen renders input field and send button',
      (WidgetTester tester) async {
    await tester.pumpWidget(const ChatApp());

    expect(find.byType(TextField), findsOneWidget);
    expect(find.byIcon(Icons.send), findsOneWidget);
  });
}
