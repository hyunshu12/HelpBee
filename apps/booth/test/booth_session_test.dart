import 'package:flutter_test/flutter_test.dart';
import 'package:helpbee_booth/data/booth_case.dart';
import 'package:helpbee_booth/data/booth_session.dart';
import 'package:helpbee_booth/data/risk_tier.dart';

const _danger = BoothCase(
  id: 'danger-90',
  photo: 'p',
  imageWidth: 1920,
  imageHeight: 1080,
  riskScore: 90,
  tier: RiskTier.danger,
  beeTotal: 6,
  varroaCount: 1,
  recommendations: [],
  boxes: [],
);

void main() {
  test('예시 4점 위에 이번 세션 진단이 얹힌다', () {
    final s = BoothSession();
    expect(s.chartScores, BoothSession.seedScores);

    s.record(_danger);
    expect(s.chartScores, [...BoothSession.seedScores, 90]);
  });

  test('초기화하면 관람객 기록만 지워지고 예시 4점은 남는다', () {
    final s = BoothSession()..record(_danger);
    s.reset();
    expect(s.history, isEmpty);
    expect(s.chartScores, BoothSession.seedScores);
  });

  test('기록이 바뀌면 리스너에게 알린다', () {
    final s = BoothSession();
    var notified = 0;
    s.addListener(() => notified++);
    s.record(_danger);
    s.reset();
    expect(notified, 2);
  });
}
