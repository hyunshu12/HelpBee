import 'package:flutter_test/flutter_test.dart';
import 'package:helpbee_booth/data/booth_case.dart';
import 'package:helpbee_booth/data/risk_tier.dart';

void main() {
  test('fromJson이 티어와 박스를 읽는다', () {
    final c = BoothCase.fromJson(const {
      'id': 'danger-90',
      'photo': 'photos/danger-90.jpg',
      'imageWidth': 1920,
      'imageHeight': 1080,
      'riskScore': 90,
      'tier': 'danger',
      'beeTotal': 6,
      'varroaCount': 1,
      'recommendations': ['즉시 처치가 필요합니다.'],
      'boxes': [
        {'x': 224.0, 'y': 413.0, 'w': 814.0, 'h': 664.0, 'cls': 'varroa'},
      ],
    });

    expect(c.id, 'danger-90');
    expect(c.tier, RiskTier.danger);
    expect(c.riskScore, 90);
    expect(c.boxes, hasLength(1));
    expect(c.boxes.first.w, 814.0);
    expect(c.recommendations.first, '즉시 처치가 필요합니다.');
  });

  test('박스가 없는 정상 케이스를 읽는다', () {
    final c = BoothCase.fromJson(const {
      'id': 'safe-0',
      'photo': 'photos/safe-0.jpg',
      'imageWidth': 1920,
      'imageHeight': 1080,
      'riskScore': 0,
      'tier': 'safe',
      'beeTotal': 12,
      'varroaCount': 0,
      'recommendations': <String>[],
      'boxes': <Map<String, dynamic>>[],
    });

    expect(c.tier, RiskTier.safe);
    expect(c.boxes, isEmpty);
  });

  test('알 수 없는 tier 문자열은 unknown으로 떨어진다', () {
    expect(riskTierFromName('nonsense'), RiskTier.unknown);
  });

  test('티어 한글명은 실제 앱 배지 문구와 같다', () {
    expect(riskTierLabel(RiskTier.safe), '안전');
    expect(riskTierLabel(RiskTier.watch), '주의');
    expect(riskTierLabel(RiskTier.danger), '위험');
  });
}
