import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helpbee_booth/data/booth_case.dart';
import 'package:helpbee_booth/theme/app_colors.dart';
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

  group('boxStyleFor', () {
    test('varroa 는 굵은 빨강, 정상 벌은 얇은 초록', () {
      final v = boxStyleFor('varroa');
      expect(v.color, AppColors.tierDanger);
      expect(v.strokeWidth, 6);
      expect(v.alpha, 1.0);

      final n = boxStyleFor('normal');
      expect(n.color, AppColors.tierSafe);
      expect(n.strokeWidth, 3);
      expect(n.alpha, 0.75);
    });

    test('모르는 cls 는 정상 벌로 취급한다', () {
      expect(boxStyleFor('nonsense').color, AppColors.tierSafe);
      expect(boxStyleFor('').color, AppColors.tierSafe);
    });
  });

  // 2026-08-31: 박스를 전부 동시에 페이드인하면 "그림 한 장이 밝아진" 것으로
  // 보여서 탐지가 일어나는 인상이 안 난다. 하나씩 탁-탁-탁 찍혀야 한다.
  // 페인터는 위젯 테스트로 못 잡으므로(동시에 그려도 통과) 타이밍 계산을
  // 순수 함수로 떼어 검증한다.
  group('boxProgressAt — 순차 등장', () {
    test('첫 박스가 다 찍히기 전에 마지막 박스는 시작도 안 한다', () {
      // 첫 박스는 240ms 에 완성. 그 시점에 5번째 박스는 아직 0 이어야 한다.
      expect(boxProgressAt(0, 240), 1.0);
      expect(boxProgressAt(4, 240), 0.0, reason: '동시에 나타나면 순차 등장이 아니다');
    });

    test('박스마다 시작 시점이 뒤로 밀린다', () {
      // 같은 시각에 앞 박스가 뒤 박스보다 항상 더 진행돼 있어야 한다.
      const t = 400.0;
      final p = [for (var i = 0; i < 5; i++) boxProgressAt(i, t)];
      for (var i = 0; i < p.length - 1; i++) {
        expect(
          p[i],
          greaterThanOrEqualTo(p[i + 1]),
          reason: '$i 번 박스가 ${i + 1} 번보다 늦게 그려진다',
        );
      }
      expect(p.first, 1.0);
      expect(p.last, lessThan(1.0), reason: '400ms 에 5번째까지 끝나면 너무 빠르다');
    });

    test('전체 시간이 박스 수에 따라 늘어난다', () {
      expect(totalMs(1), 240);
      expect(totalMs(2), greaterThan(totalMs(1)));
      expect(totalMs(10), greaterThan(totalMs(2)));
      // 어트랙트는 4초마다 반복하므로 그 안에 끝나야 한다.
      expect(
        totalMs(16),
        lessThan(4000),
        reason: '박스가 많아도 어트랙트 반복 주기(4초) 안에 끝나야 한다',
      );
    });

    test('시간이 지나면 모든 박스가 완성된다', () {
      for (var i = 0; i < 16; i++) {
        expect(boxProgressAt(i, totalMs(16)), 1.0);
      }
    });
  });

  group('revealOrder — 빨강이 마지막', () {
    test('정상 벌을 먼저 훑고 감염 의심을 맨 나중에 찍는다', () {
      const boxes = [
        BoothBox(x: 0, y: 0, w: 1, h: 1, cls: 'varroa'),
        BoothBox(x: 1, y: 0, w: 1, h: 1, cls: 'normal'),
        BoothBox(x: 2, y: 0, w: 1, h: 1, cls: 'normal'),
        BoothBox(x: 3, y: 0, w: 1, h: 1, cls: 'varroa'),
      ];
      final order = revealOrder(boxes).map((b) => b.cls).toList();
      expect(order, [
        'normal',
        'normal',
        'varroa',
        'varroa',
      ], reason: '빨강이 먼저 찍히면 "찾아냈다" 는 연출이 김빠진다');
    });

    test('박스를 하나도 잃거나 더하지 않는다', () {
      const boxes = [
        BoothBox(x: 0, y: 0, w: 1, h: 1, cls: 'varroa'),
        BoothBox(x: 1, y: 0, w: 1, h: 1, cls: 'normal'),
        BoothBox(x: 2, y: 0, w: 1, h: 1, cls: 'nonsense'),
      ];
      expect(revealOrder(boxes).length, boxes.length);
      expect(revealOrder(const <BoothBox>[]), isEmpty);
    });
  });
}
