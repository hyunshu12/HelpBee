import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helpbee_booth/data/booth_case.dart';
import 'package:helpbee_booth/data/case_kind.dart';
import 'package:helpbee_booth/data/risk_tier.dart';
import 'package:helpbee_booth/screens/report_screen.dart';
import 'package:helpbee_booth/widgets/risk_gauge.dart';
import 'package:helpbee_booth/widgets/surfaces.dart';

import 'test_surface.dart';

// 실제 danger-100 케이스(assets/cases.json)의 recommendations 5개를 그대로 옮김 —
// 위험 티어의 실제 최악 케이스(처방 5개)로 오버플로 유무를 검증하기 위함.
BoothCase _danger() => const BoothCase(
  id: 'danger-90',
  photo: 'photos/danger-90.jpg',
  kind: CaseKind.varroa,
  disease: 'varroa',
  diseaseLabel: '응애',
  imageWidth: 1920,
  imageHeight: 1080,
  riskScore: 90,
  tier: RiskTier.danger,
  beeTotal: 6,
  sickCount: 1,
  recommendations: [
    '응애 감염률이 위험 범위(10% 이상)입니다. 즉시 처치가 필요합니다.',
    '우선 alcohol wash 또는 sugar roll로 정확한 mite-per-100-bees를 측정하세요.',
    '수의사 또는 양봉 전문가 자문 후 처치제(개미산/옥살산/Apivar)를 적용하세요.',
    '주변 벌통도 함께 검사하세요 — 응애는 봉간 전파됩니다.',
    'AI 추정치는 참고용입니다. 정확한 감염 정도는 실측 검사(가루설탕/알코올워시)를 병행하세요.',
  ],
  boxes: [BoothBox(x: 519, y: 71, w: 811, h: 636, cls: 'varroa')],
);

BoothCase _safe() => const BoothCase(
  id: 'safe-0',
  photo: 'photos/safe-0.jpg',
  kind: CaseKind.healthy,
  disease: null,
  diseaseLabel: null,
  imageWidth: 1920,
  imageHeight: 1080,
  riskScore: 0,
  tier: RiskTier.safe,
  beeTotal: 6,
  sickCount: 0,
  recommendations: ['응애 감염률이 안전 범위(3% 미만)입니다. 정기 모니터링을 유지하세요.'],
  boxes: [BoothBox(x: 100, y: 100, w: 200, h: 200, cls: 'normal')],
);

BoothCase _visible() => const BoothCase(
  id: 'dwv-1',
  photo: 'photos/dwv-1.jpg',
  kind: CaseKind.visible,
  disease: 'dwv',
  diseaseLabel: '날개불구 바이러스',
  imageWidth: 1920,
  imageHeight: 1080,
  riskScore: 0,
  tier: RiskTier.safe,
  beeTotal: 9,
  sickCount: 4,
  recommendations: ['응애 외 다른 질병 의심 영역이 탐지되었습니다.'],
  boxes: [BoothBox(x: 100, y: 100, w: 300, h: 200, cls: 'disease')],
);

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets('위험도 점수와 티어를 보여준다', (tester) async {
    await useBoothSurface(tester);
    await tester.pumpWidget(
      _wrap(
        ReportScreen(
          case_: _danger(),
          guess: null,
          isLastRound: false,
          isBonus: false,
          onNext: () {},
        ),
      ),
    );
    expect(find.text('90'), findsOneWidget);
    expect(find.text('위험'), findsOneWidget);
  });

  testWidgets('처방은 첫 줄만 보이고 나머지는 접혀 있다', (tester) async {
    await useBoothSurface(tester);
    await tester.pumpWidget(
      _wrap(
        ReportScreen(
          case_: _danger(),
          guess: null,
          isLastRound: false,
          isBonus: false,
          onNext: () {},
        ),
      ),
    );
    expect(find.textContaining('즉시 처치가 필요합니다'), findsOneWidget);
    expect(find.textContaining('alcohol wash'), findsNothing);

    await tester.tap(find.text('처방 더 보기'));
    await tester.pumpAndSettle();
    expect(find.textContaining('alcohol wash'), findsOneWidget);
  });

  testWidgets('틀린 추측은 내 답과 함께 위로하는 문구를 보여준다', (tester) async {
    await useBoothSurface(tester);
    // 위험 벌통을 '건강함' 이라고 답한 경우
    await tester.pumpWidget(
      _wrap(
        ReportScreen(
          case_: _danger(),
          guess: true,
          isLastRound: false,
          isBonus: false,
          onNext: () {},
        ),
      ),
    );
    expect(find.text('당신: 건강함'), findsOneWidget);
    // 응애를 놓친 관람객을 탓하지 않는다 — 못 찾는 게 정상이라는 게 메시지다.
    expect(find.textContaining('못 찾는 게 정상입니다'), findsOneWidget);
  });

  testWidgets('맞힌 추측은 정확하다고 알려준다', (tester) async {
    await useBoothSurface(tester);
    // 정상 벌통을 '건강함' 이라고 답한 경우
    await tester.pumpWidget(
      _wrap(
        ReportScreen(
          case_: _safe(),
          guess: true,
          isLastRound: false,
          isBonus: false,
          onNext: () {},
        ),
      ),
    );
    expect(find.text('당신: 건강함'), findsOneWidget);
    expect(find.textContaining('정말 건강합니다'), findsOneWidget);
  });

  testWidgets('문제 있음 이라고 답하면 그대로 표시된다', (tester) async {
    await useBoothSurface(tester);
    await tester.pumpWidget(
      _wrap(
        ReportScreen(
          case_: _danger(),
          guess: false,
          isLastRound: false,
          isBonus: false,
          onNext: () {},
        ),
      ),
    );
    expect(find.text('당신: 문제 있음'), findsOneWidget);
    expect(find.textContaining('맞히셨네요'), findsOneWidget);
  });

  testWidgets('추측을 건너뛰면 대조 줄이 아예 없다', (tester) async {
    await useBoothSurface(tester);
    // 위 세 테스트가 '당신:' 이 정상적으로는 렌더된다는 걸 증명하므로
    // 이 findsNothing 은 공허하지 않다.
    await tester.pumpWidget(
      _wrap(
        ReportScreen(
          case_: _danger(),
          guess: null,
          isLastRound: false,
          isBonus: false,
          onNext: () {},
        ),
      ),
    );
    expect(find.textContaining('당신'), findsNothing);
    expect(find.textContaining('못 찾는 게 정상입니다'), findsNothing);
    expect(find.textContaining('맞히셨네요'), findsNothing);
  });

  testWidgets('위험 케이스 처방을 전부 펼쳐도 오버플로가 없다', (tester) async {
    await useBoothSurface(tester);
    await tester.pumpWidget(
      _wrap(
        ReportScreen(
          case_: _danger(),
          guess: false,
          isLastRound: false,
          isBonus: false,
          onNext: () {},
        ),
      ),
    );
    await tester.tap(find.text('처방 더 보기'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  group('투어 버튼', () {
    testWidgets('마지막 라운드가 아니면 "다음 사진", 마지막이면 "결과 보기"', (tester) async {
      await useBoothSurface(tester);
      var next = 0;
      await tester.pumpWidget(
        _wrap(
          ReportScreen(
            case_: _danger(),
            guess: false,
            isLastRound: false,
            isBonus: false,
            onNext: () => next++,
          ),
        ),
      );
      expect(find.text('다음 사진 →'), findsOneWidget);
      // 투어 중엔 옆길이 없어야 3라운드가 만드는 대비가 살아난다.
      expect(find.text('기록 보기'), findsNothing);
      expect(find.text('다른 사진 해보기'), findsNothing);
      expect(find.text('QR 받기'), findsNothing);
      await tester.tap(find.text('다음 사진 →'));
      expect(next, 1);

      await tester.pumpWidget(
        _wrap(
          ReportScreen(
            case_: _danger(),
            guess: false,
            isLastRound: true,
            isBonus: false,
            onNext: () {},
          ),
        ),
      );
      expect(find.text('결과 보기 →'), findsOneWidget);
      expect(find.text('다음 사진 →'), findsNothing);
    });

    testWidgets('보너스 경로는 "마치기"로 끝난다', (tester) async {
      await useBoothSurface(tester);
      await tester.pumpWidget(
        _wrap(
          ReportScreen(
            case_: _danger(),
            guess: false,
            isLastRound: true,
            isBonus: true,
            onNext: () {},
          ),
        ),
      );
      expect(find.text('마치기 →'), findsOneWidget);
    });
  });

  group('kind 별 판정 영역', () {
    testWidgets('다른 병은 게이지도 티어 배지도 없이 병 이름을 보여준다', (tester) async {
      await useBoothSurface(tester);
      await tester.pumpWidget(
        _wrap(
          ReportScreen(
            case_: _visible(),
            guess: false,
            isLastRound: false,
            isBonus: false,
            onNext: () {},
          ),
        ),
      );

      expect(find.text('날개불구 바이러스'), findsOneWidget);
      expect(find.textContaining('4'), findsWidgets);
      // 티어는 *응애* 위험도라 다른 병에는 의미가 없다. compute_risk 상 safe 가
      // 나오므로(2026-09-08 실측), 배지를 그리면 병든 벌통에 초록 '안전' 이 붙는다.
      expect(find.text('안전'), findsNothing, reason: '다른 병에 안전 배지가 붙으면 안 된다');
      expect(find.byType(RiskGauge), findsNothing, reason: '응애 감염률 게이지는 응애 전용');
    });

    testWidgets('응애는 게이지와 티어 배지를 그대로 보여준다', (tester) async {
      await useBoothSurface(tester);
      await tester.pumpWidget(
        _wrap(
          ReportScreen(
            case_: _danger(),
            guess: null,
            isLastRound: false,
            isBonus: false,
            onNext: () {},
          ),
        ),
      );
      expect(find.byType(RiskGauge), findsOneWidget);
      expect(find.text('위험'), findsOneWidget);
    });
  });

  group('대조 문구', () {
    test('kind 와 정오답 조합마다 다른 문구가 나온다', () {
      expect(verdictFor(CaseKind.visible, false, false), contains('눈에 보이는 병'));
      expect(verdictFor(CaseKind.visible, true, false), contains('놓치셨네요'));
      expect(verdictFor(CaseKind.varroa, false, false), contains('맞히셨네요'));
      expect(verdictFor(CaseKind.varroa, true, false), contains('2mm'));
      expect(verdictFor(CaseKind.healthy, true, true), contains('정말 건강합니다'));
      expect(verdictFor(CaseKind.healthy, false, true), contains('함정'));
      expect(
        verdictFor(CaseKind.varroa, null, false),
        isNull,
        reason: '건너뛰면 대조 줄이 없다',
      );
    });

    test('여섯 문구가 서로 다르다', () {
      final all = <String>{
        for (final kind in [
          CaseKind.visible,
          CaseKind.varroa,
          CaseKind.healthy,
        ])
          for (final g in [true, false])
            verdictFor(kind, g, kind == CaseKind.healthy)!,
      };
      expect(all, hasLength(6), reason: '문구가 겹치면 라운드마다 같은 말을 한다');
    });
  });

  // 2026-08-31 회귀: 결과 화면의 사진 칸은 세로로 긴 컬럼이라, 액자가 사진
  // 비율을 안 따라가면 사진 위아래로 100px 넘는 흰 띠가 생긴다(웹 실측).
  // 이 화면의 핵심 연출이 사진 위 박스라 여백이 크면 그만큼 작아진다.
  testWidgets('사진 액자에 흰 띠가 생기지 않는다 (사진 비율 유지)', (tester) async {
    await useBoothSurface(tester);
    await tester.pumpWidget(
      _wrap(
        ReportScreen(
          case_: _danger(),
          guess: null,
          isLastRound: false,
          isBonus: false,
          onNext: () {},
        ),
      ),
    );

    final photo = tester.getSize(
      find
          .descendant(
            of: find.byType(PhotoFrame),
            matching: find.byType(ClipRRect),
          )
          .first,
    );

    expect(
      photo.width / photo.height,
      closeTo(1920 / 1080, 0.08),
      reason: '액자가 컬럼 높이만큼 늘어나면 사진 위아래가 흰 띠로 남는다',
    );
  });

  // 2026-08-31 설계 결정: 주 버튼(가장 크고 꿀색)은 **QR/마무리로 가는 길**이다.
  // 2026-08-31: 버튼 라벨이 잘리면 무슨 버튼인지 읽을 수 없다. 말줄임이
  // 실제로 일어나는지를 렌더 결과에서 직접 본다 — 눈으로만 확인하면 다음에
  // 문구를 늘렸을 때 조용히 재발한다.
  testWidgets('주 버튼 라벨이 말줄임 없이 한 줄에 들어간다', (tester) async {
    await useBoothSurface(tester);
    for (final config in [
      (isLastRound: false, isBonus: false, label: '다음 사진 →'),
      (isLastRound: true, isBonus: false, label: '결과 보기 →'),
      (isLastRound: true, isBonus: true, label: '마치기 →'),
    ]) {
      await tester.pumpWidget(
        _wrap(
          ReportScreen(
            case_: _danger(),
            guess: false,
            isLastRound: config.isLastRound,
            isBonus: config.isBonus,
            onNext: () {},
          ),
        ),
      );
      final paragraph = tester.renderObject<RenderParagraph>(
        find.text(config.label),
      );
      expect(
        paragraph.didExceedMaxLines,
        isFalse,
        reason: '"${config.label}" 이 버튼 안에서 잘린다',
      );
    }
  });
}
