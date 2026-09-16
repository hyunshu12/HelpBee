import 'package:flutter_test/flutter_test.dart';
import 'package:helpbee_booth/data/slide_deck.dart';

void main() {
  group('SlideDeck 이동', () {
    test('next 는 마지막 장 전까지 true, 마지막 장에서 false 로 종료를 알린다', () {
      final d = SlideDeck(['a', 'b', 'c']);
      expect(d.index, 0);
      expect(d.next(), isTrue);
      expect(d.next(), isTrue);
      expect(d.index, 2);
      expect(d.isLast, isTrue);
      expect(d.next(), isFalse, reason: '마지막 장에서 다음 = 발표 종료');
      expect(d.index, 2, reason: '넘치지 않는다');
    });

    test('prev 는 첫 장에서 무시된다', () {
      final d = SlideDeck(['a', 'b']);
      expect(d.prev(), isFalse);
      expect(d.index, 0);
      d.next();
      expect(d.prev(), isTrue);
      expect(d.index, 0);
    });

    test('isDemo 는 demoIndex 장에서만 참', () {
      final d = SlideDeck(['a', 'b', 'c'], demoIndex: 1);
      expect(d.isDemo, isFalse);
      d.next();
      expect(d.isDemo, isTrue);
      expect(SlideDeck(['a']).isDemo, isFalse, reason: 'demoIndex null');
    });

    test('returnFromDemo 는 시연 장 다음으로, 시연 장이 마지막이면 그 장에 머문다', () {
      final d = SlideDeck(['a', 'b', 'c'], demoIndex: 1)..returnFromDemo();
      expect(d.index, 2);
      final last = SlideDeck(['a', 'b'], demoIndex: 1)..returnFromDemo();
      expect(last.index, 1);
      final none = SlideDeck(['a', 'b'])
        ..next()
        ..returnFromDemo();
      expect(none.index, 1, reason: 'demoIndex 없으면 아무 것도 안 한다');
    });
  });

  group('slideDeckFromAssetKeys', () {
    test('assets/slides 의 jpg·png 만 이름순으로 고른다', () {
      final d = slideDeckFromAssetKeys([
        'assets/slides/03.jpg',
        'assets/cases.json',
        'assets/slides/01.jpg',
        'assets/slides/notes.txt',
        'assets/photos/x.jpg',
        'assets/slides/02.jpg',
      ], demoIndex: 2);
      expect(d, isNotNull);
      expect(d!.paths, [
        'assets/slides/01.jpg',
        'assets/slides/02.jpg',
        'assets/slides/03.jpg',
      ]);
      expect(d.demoIndex, 2);
    });

    test('슬라이드가 하나도 없으면 null — 부스 빌드에서 발표 모드가 열리지 않게', () {
      expect(slideDeckFromAssetKeys(['assets/cases.json']), isNull);
      expect(slideDeckFromAssetKeys(const []), isNull);
    });

    test('demoIndex 가 범위를 벗어나면 버린다', () {
      final d = slideDeckFromAssetKeys(['assets/slides/01.jpg'], demoIndex: 5);
      expect(d!.demoIndex, isNull);
    });
  });
}
