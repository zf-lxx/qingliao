import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:qingliao/widgets/image_viewer.dart';

void main() {
  testWidgets(
    'shared image opens, double-tap zooms, bars toggle, vertical drag returns to thumbnail',
    (tester) async {
      final bytes = Uint8List.fromList(
        img.encodePng(img.Image(width: 20, height: 30)),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: GestureDetector(
                  key: const Key('source-image'),
                  behavior: HitTestBehavior.opaque,
                  onTap: () => openImageViewer(
                    context,
                    bytes: bytes,
                    tag: 'photo',
                    sender: '测试用户',
                    time: '00:04',
                  ),
                  child: Hero(
                    tag: 'photo',
                    curve: Curves.linear,
                    child: SizedBox(
                      width: 120,
                      height: 180,
                      child: Image.memory(bytes, width: 120),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('source-image')));
      await tester.pumpAndSettle();
      expect(find.byType(ImageViewer), findsOneWidget);
      expect(find.text('测试用户'), findsOneWidget);
      final viewer = find.byType(InteractiveViewer);
      await tester.tapAt(const Offset(400, 300));
      await tester.pump(const Duration(milliseconds: 60));
      await tester.tapAt(const Offset(400, 300));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<InteractiveViewer>(viewer)
            .transformationController!
            .value
            .getMaxScaleOnAxis(),
        greaterThan(2),
      );
      await tester.tapAt(const Offset(400, 300));
      await tester.pump(const Duration(milliseconds: 60));
      await tester.tapAt(const Offset(400, 300));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<InteractiveViewer>(viewer)
            .transformationController!
            .value
            .getMaxScaleOnAxis(),
        closeTo(1, .01),
      );
      await tester.tapAt(const Offset(400, 300));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.text('测试用户'), findsNothing);
      await tester.drag(viewer, const Offset(0, 180));
      await tester.pumpAndSettle();
      expect(find.byType(ImageViewer), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
