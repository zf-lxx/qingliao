import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qingliao/main.dart';
import 'package:qingliao/core/api.dart';

void main() {
  test('production requires HTTPS and server root, no token in URL', () {
    expect(
      normalizeServer('https://chat.example.com/'),
      'https://chat.example.com',
    );
    expect(normalizeServer('http://127.0.0.1:8088'), 'http://127.0.0.1:8088');
    for (final url in [
      'http://evil.example',
      'https://u:p@host',
      'https://host/v1',
      'https://host?token=x',
      'file:///tmp',
    ]) {
      expect(() => normalizeServer(url), throwsFormatException);
    }
  });
  testWidgets(
    'UTF-16 emoji and nested bold/italic render without splitting surrogate pairs',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EntityText(
              text: '你好 😀 Flutter',
              entities: [
                {'type': 'bold', 'offset': 0, 'length': 5},
                {'type': 'italic', 'offset': 3, 'length': 2},
                {
                  'type': 'underline',
                  'offset': 4,
                  'length': 1,
                }, // malformed ignored
              ],
              revealed: false,
              onReveal: () {},
            ),
          ),
        ),
      );
      expect(find.byType(RichText), findsWidgets);
      expect(tester.takeException(), isNull);
      final rich = tester.widget<RichText>(find.byType(RichText).last);
      expect(rich.text.toPlainText(), '你好 😀 Flutter');
    },
  );
}
