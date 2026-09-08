import 'case_kind.dart';
import 'risk_tier.dart';

/// 이미지 원본 픽셀 좌표계의 박스 하나.
///
/// `cls` 는 `'varroa'`(응애 의심) · `'disease'`(다른 병 의심) · `'normal'`(그 외 벌).
/// 결과 화면이 각각 빨강 · 주황 · 초록으로 그린다.
class BoothBox {
  const BoothBox({
    required this.x,
    required this.y,
    required this.w,
    required this.h,
    required this.cls,
  });

  final double x;
  final double y;
  final double w;
  final double h;
  final String cls;

  factory BoothBox.fromJson(Map<String, dynamic> json) => BoothBox(
    x: (json['x'] as num).toDouble(),
    y: (json['y'] as num).toDouble(),
    w: (json['w'] as num).toDouble(),
    h: (json['h'] as num).toDouble(),
    cls: json['cls'] as String? ?? 'normal',
  );
}

/// 사진 1장 = 체험 케이스 1개. 전부 미리 계산된 고정값이다.
class BoothCase {
  const BoothCase({
    required this.id,
    required this.photo,
    required this.imageWidth,
    required this.imageHeight,
    required this.riskScore,
    required this.tier,
    required this.kind,
    required this.disease,
    required this.diseaseLabel,
    required this.beeTotal,
    required this.sickCount,
    required this.recommendations,
    required this.boxes,
  });

  final String id;
  final String photo;
  final int imageWidth;
  final int imageHeight;
  final int riskScore;
  final RiskTier tier;

  /// 라운드 배정 키이자 결과 화면 분기 기준.
  final CaseKind kind;

  /// `'varroa'` | `'dwv'` | `'chalkbrood'` | null(정상)
  final String? disease;

  /// 화면 표시명 (`'석고병'` 등). 정상이면 null.
  final String? diseaseLabel;

  final int beeTotal;

  /// 이상 개체 수 — 응애든 다른 병이든 하나로 센다.
  final int sickCount;
  final List<String> recommendations;
  final List<BoothBox> boxes;

  /// 관람객이 '건강함'이라고 답했을 때 맞은 것으로 칠지.
  ///
  /// **tier 가 아니라 kind 로 판단한다.** 다른 병 케이스는 응애가 0이라
  /// tier=safe 가 나오는데(2026-09-08 실측), 그걸 건강하다고 치면 병든 벌통에
  /// '건강함' 추측이 정답이 된다.
  bool get isHealthy => kind == CaseKind.healthy;

  factory BoothCase.fromJson(Map<String, dynamic> json) => BoothCase(
    id: json['id'] as String,
    photo: json['photo'] as String,
    imageWidth: (json['imageWidth'] as num).toInt(),
    imageHeight: (json['imageHeight'] as num).toInt(),
    riskScore: (json['riskScore'] as num).toInt(),
    tier: riskTierFromName(json['tier'] as String?),
    kind: caseKindFromName(json['kind'] as String?),
    disease: json['disease'] as String?,
    diseaseLabel: json['diseaseLabel'] as String?,
    beeTotal: (json['beeTotal'] as num).toInt(),
    sickCount: (json['sickCount'] as num).toInt(),
    recommendations: (json['recommendations'] as List<dynamic>)
        .map((e) => e as String)
        .toList(growable: false),
    boxes: (json['boxes'] as List<dynamic>)
        .map((e) => BoothBox.fromJson((e as Map).cast<String, dynamic>()))
        .toList(growable: false),
  );
}
