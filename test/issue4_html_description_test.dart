import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sloth/screens/task_detail_screen.dart';

void main() {
  test('looksLikeHtml detects Tiptap output, not plain text', () {
    expect(
      looksLikeHtml(
        '<p dir="auto">Hello <strong>world</strong><br>line two</p>',
      ),
      isTrue,
    );
    expect(looksLikeHtml('<ul>\n<li>a</li>\n</ul>'), isTrue);
    expect(looksLikeHtml('I <3 this task'), isFalse);
    expect(looksLikeHtml('1 < 2 and 3 > 2'), isFalse);
    expect(looksLikeHtml('plain description'), isFalse);
    expect(looksLikeHtml(''), isFalse);
  });

  testWidgets('HTML description renders with tags hidden', (tester) async {
    final controller = TextEditingController(
      text: '<p dir="auto">Hello <strong>world</strong></p>',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NotesFieldPreview(controller: controller),
        ),
      ),
    );
    await tester.pump();
    // Tags parsed into a rich node, not the raw string.
    expect(find.text('Hello world', findRichText: true), findsOneWidget);
    expect(find.textContaining('<strong>'), findsNothing);
    expect(find.text('Hello <strong>world</strong>'), findsNothing);
  });

  testWidgets('plain text description keeps the raw TextField', (tester) async {
    final controller = TextEditingController(text: 'plain description');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: NotesFieldPreview(controller: controller)),
      ),
    );
    await tester.pump();
    expect(find.byType(TextField), findsOneWidget);
  });
}
