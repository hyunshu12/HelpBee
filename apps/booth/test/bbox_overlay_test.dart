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
            photoAsset: 'assets/photos/varroa-2.jpg',
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
            photoAsset: 'assets/photos/healthy-1.jpg',
            imageSize: const Size(1920, 1080),
            boxes: const [],
            animate: false,
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
  });

  group('boxStyleFor — 검출기 스타일', () {
    test('세 클래스가 색·라벨로 구분된다', () {
      final v = boxStyleFor('varroa');
      expect(v.color, AppColors.tierDanger);
      expect(v.tag, '응애');

      final d = boxStyleFor('disease');
      expect(d.color, AppColors.boxDisease);
      expect(d.tag, '질병');

      final n = boxStyleFor('normal');
      expect(n.color, AppColors.tierSafe);
      expect(n.tag, '정상 벌', reason: '초록 박스에 글자가 없으면 저게 뭔지 알 수 없다');
    });

    test('라벨이 오면 그 이름을 그대로 태그로 쓴다', () {
      // 3-class 는 색만 정한다 — 초록 박스에도 성충과 유충(애벌레)이 섞여 있어서
      // 원본 라벨의 구분을 살려야 한다 (2026-09-14 피드백).
      expect(boxStyleFor('normal', label: '유충').tag, '유충');
      expect(boxStyleFor('disease', label: '부저병').tag, '부저병');
      expect(boxStyleFor('varroa', label: '응애').color, AppColors.tierDanger);
    });

    test('정상 박스가 많으면 이름표를 생략하고, 병든 박스는 항상 단다', () {
      // 소비판 광각은 정상 박스가 58개 — 전부 이름표를 달면 사진이 글자에 묻힌다.
      List<BoothBox> normals(int n) => [
        for (var i = 0; i < n; i++)
          BoothBox(x: i * 10.0, y: 0, w: 5, h: 5, cls: 'normal', label: '유충'),
      ];
      expect(shouldTagNormals(normals(kMaxTaggedNormals)), isTrue);
      expect(shouldTagNormals(normals(kMaxTaggedNormals + 1)), isFalse);
      // 병든 박스 수는 판단에 안 들어간다 — 정상이 적으면 병이 많아도 단다.
      expect(
        shouldTagNormals([
          ...normals(3),
          for (var i = 0; i < 40; i++)
            BoothBox(x: i * 10.0, y: 50, w: 5, h: 5, cls: 'disease'),
        ]),
        isTrue,
      );
    });

    test('작은 박스는 화면에서 최소 크기까지 키워 그린다', () {
      // 부저병 박스는 소방 한 칸이라 화면에서 20px 남짓 — 태그보다도 작아
      // "검출됐다"는 인상이 안 난다. 중심은 그대로 둔다.
      final small = inflateToMinimum(const Rect.fromLTWH(100, 100, 20, 20));
      expect(small.width, kMinBoxSide);
      expect(small.height, kMinBoxSide);
      expect(small.center, const Offset(110, 110));

      // 충분히 큰 박스는 건드리지 않는다 — 키우면 좌표가 거짓말이 된다.
      const big = Rect.fromLTWH(0, 0, 300, 200);
      expect(inflateToMinimum(big), big);
    });

    test('모르는 cls 는 정상 벌로 취급한다', () {
      expect(boxStyleFor('nonsense').color, AppColors.tierSafe);
      expect(boxStyleFor('').color, AppColors.tierSafe);
    });

    test('선이 얇다 — 실제 검출기 출력처럼', () {
      // 굵은 선 + 둥근 모서리는 일러스트 스티커처럼 보인다 (2026-09-08 피드백).
      expect(boxStyleFor('varroa').strokeWidth, lessThanOrEqualTo(3));
      expect(boxStyleFor('disease').strokeWidth, lessThanOrEqualTo(3));
      expect(boxStyleFor('normal').strokeWidth, lessThanOrEqualTo(3));
    });
  });

  group('감속', () {
    test('박스 하나가 그려지는 데 0.3초 이상 걸린다', () {
      // 240ms 는 "한 번에 다 뜬" 것처럼 보였다.
      expect(boxProgressAt(0, 200), lessThan(1.0));
      expect(boxProgressAt(0, 360), 1.0);
    });

    test('박스 사이가 충분히 벌어진다', () {
      // 첫 박스가 다 그려진 시점(360ms)에 두 번째는 아직 절반도 안 됐어야
      // "하나씩" 으로 보인다.
      expect(boxProgressAt(1, 360, count: 3), lessThan(0.5));
    });

    test('박스가 많아도 총 시간이 4.5초를 넘지 않는다', () {
      // 어트랙트가 8초마다 반복하고, 관람객이 결과를 기다리는 시간도 한계가 있다.
      for (final n in [1, 7, 14, 18, 40]) {
        expect(totalMs(n), lessThanOrEqualTo(4500), reason: '박스 $n개');
      }
      expect(totalMs(14), greaterThan(2500), reason: '너무 빨리 끝나도 안 된다');
    });

    test('시간이 지나면 모든 박스가 완성된다', () {
      for (final n in [3, 7, 18, 40]) {
        for (var i = 0; i < n; i++) {
          expect(
            boxProgressAt(i, totalMs(n), count: n),
            1.0,
            reason: '박스 $n개 중 $i번이 안 끝났다',
          );
        }
      }
    });
  });

  group('revealOrder — 정상 → 다른 병 → 응애', () {
    test('응애가 맨 마지막에 찍힌다', () {
      const boxes = [
        BoothBox(x: 0, y: 0, w: 1, h: 1, cls: 'varroa'),
        BoothBox(x: 1, y: 0, w: 1, h: 1, cls: 'normal'),
        BoothBox(x: 2, y: 0, w: 1, h: 1, cls: 'disease'),
        BoothBox(x: 3, y: 0, w: 1, h: 1, cls: 'normal'),
      ];
      expect(
        revealOrder(boxes).map((b) => b.cls).toList(),
        ['normal', 'normal', 'disease', 'varroa'],
        reason: '빨강이 먼저 찍히면 "찾아냈다" 는 연출이 김빠진다',
      );
    });

    test('박스를 하나도 잃거나 더하지 않는다', () {
      const boxes = [
        BoothBox(x: 0, y: 0, w: 1, h: 1, cls: 'varroa'),
        BoothBox(x: 1, y: 0, w: 1, h: 1, cls: 'disease'),
        BoothBox(x: 2, y: 0, w: 1, h: 1, cls: 'nonsense'),
      ];
      expect(revealOrder(boxes).length, boxes.length);
      expect(revealOrder(const <BoothBox>[]), isEmpty);
    });
  });
}
