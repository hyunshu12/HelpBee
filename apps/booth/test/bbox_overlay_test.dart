import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helpbee_booth/data/booth_case.dart';
import 'package:helpbee_booth/widgets/bbox_overlay.dart';

void main() {
  testWidgets('박스가 있어도 없어도 예외 없이 렌더된다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 800,
          height: 600,
          child: BboxOverlay(
            photoAsset: 'assets/photos/danger-90.jpg',
            imageSize: const Size(1920, 1080),
            boxes: const [
              BoothBox(x: 519, y: 71, w: 292, h: 565, cls: 'varroa'),
              BoothBox(x: 900, y: 120, w: 240, h: 480, cls: 'normal'),
            ],
            animate: false,
          ),
        ),
      ),
    );
    expect(find.byType(CustomPaint), findsWidgets);

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 800,
          height: 600,
          child: BboxOverlay(
            photoAsset: 'assets/photos/safe-0.jpg',
            imageSize: const Size(1920, 1080),
            boxes: const [],
            animate: false,
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
  });
}
