import 'package:flutter_test/flutter_test.dart';
import 'package:helpbee_booth/data/booth_case.dart';
import 'package:helpbee_booth/data/case_kind.dart';
import 'package:helpbee_booth/data/risk_tier.dart';

void main() {
  test('fromJson이 티어와 박스를 읽는다', () {
    final c = BoothCase.fromJson(const {
      'id': 'danger-90',
      'photo': 'photos/danger-90.jpg',
      'kind': 'varroa',
      'disease': 'varroa',
      'diseaseLabel': '응애',
      'imageWidth': 1920,
      'imageHeight': 1080,
      'riskScore': 90,
      'tier': 'danger',
      'beeTotal': 6,
      'sickCount': 1,
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
      'kind': 'healthy',
      'disease': null,
      'diseaseLabel': null,
      'imageWidth': 1920,
      'imageHeight': 1080,
      'riskScore': 0,
      'tier': 'safe',
      'beeTotal': 12,
      'sickCount': 0,
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

  test('kind 를 읽고, 건강 여부는 tier 가 아니라 kind 로 판단한다', () {
    // 회귀: 예전 isHealthy 는 tier == safe 였다. 다른 병 케이스는 응애가 0이라
    // compute_risk 상 tier=safe 가 나오므로(2026-09-08 실측), 병든 벌통에
    // '건강함' 추측이 정답 처리되는 버그가 있었다.
    final visible = BoothCase.fromJson({
      'id': 'dwv-1',
      'photo': 'photos/dwv-1.jpg',
      'kind': 'visible',
      'disease': 'dwv',
      'diseaseLabel': '날개불구 바이러스',
      'imageWidth': 1920,
      'imageHeight': 1080,
      'riskScore': 0,
      'tier': 'safe',
      'beeTotal': 9,
      'sickCount': 4,
      'recommendations': <String>[],
      'boxes': <dynamic>[],
    });

    expect(visible.kind, CaseKind.visible);
    expect(visible.diseaseLabel, '날개불구 바이러스');
    expect(visible.sickCount, 4);
    expect(
      visible.isHealthy,
      isFalse,
      reason: 'tier 가 safe 여도 병든 벌통이다 — 건강함으로 치면 안 된다',
    );
  });

  test('정상 케이스만 isHealthy 다', () {
    final healthy = BoothCase.fromJson({
      'id': 'safe-0',
      'photo': 'photos/safe-0.jpg',
      'kind': 'healthy',
      'disease': null,
      'diseaseLabel': null,
      'imageWidth': 1920,
      'imageHeight': 1080,
      'riskScore': 0,
      'tier': 'safe',
      'beeTotal': 6,
      'sickCount': 0,
      'recommendations': <String>[],
      'boxes': <dynamic>[],
    });
    expect(healthy.isHealthy, isTrue);
    expect(healthy.disease, isNull);
  });

  test('모르는 kind 는 healthy 로 떨어지지 않는다', () {
    // healthy 로 잘못 떨어지면 병든 벌통을 "정답: 건강함" 으로 채점한다.
    expect(caseKindFromName('nonsense'), CaseKind.varroa);
    expect(caseKindFromName(null), CaseKind.varroa);
  });

  test('다른 병 케이스는 그 병 처방을 첫 줄로 올린다', () {
    // 화면 제목이 '날개불구 바이러스'인데 첫 줄이 "응애 감염률 안전"이면
    // 관람객에게 모순으로 읽힌다 (2026-09-08 웹 실측).
    final c = BoothCase.fromJson({
      'id': 'dwv-1',
      'photo': 'photos/dwv-1.jpg',
      'kind': 'visible',
      'disease': 'dwv',
      'diseaseLabel': '날개불구 바이러스',
      'imageWidth': 1920,
      'imageHeight': 1080,
      'riskScore': 0,
      'tier': 'safe',
      'beeTotal': 9,
      'sickCount': 4,
      'recommendations': const [
        '응애 감염률이 안전 범위(3% 미만)입니다.',
        '응애 외 다른 질병 의심 영역이 탐지되었습니다.',
        '날개불구바이러스(DWV) 가능성 — 수의학적 진단이 필요합니다.',
      ],
      'boxes': <dynamic>[],
    });
    expect(c.orderedRecommendations.first, contains('다른 질병'));
    // 이어지는 문장이 바로 뒤에 붙어야 뜻이 끊기지 않는다.
    expect(c.orderedRecommendations[1], contains('DWV'));
    expect(c.orderedRecommendations, hasLength(3));
  });

  test('응애 케이스의 처방 순서는 건드리지 않는다', () {
    final c = BoothCase.fromJson({
      'id': 'danger-100',
      'photo': 'photos/danger-100.jpg',
      'kind': 'varroa',
      'disease': 'varroa',
      'diseaseLabel': '응애',
      'imageWidth': 1920,
      'imageHeight': 1080,
      'riskScore': 100,
      'tier': 'danger',
      'beeTotal': 7,
      'sickCount': 2,
      'recommendations': const ['즉시 처치', '다른 질병 확인'],
      'boxes': <dynamic>[],
    });
    expect(c.orderedRecommendations, ['즉시 처치', '다른 질병 확인']);
  });
}
