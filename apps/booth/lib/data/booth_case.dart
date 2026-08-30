import 'risk_tier.dart';

/// 이미지 원본 픽셀 좌표계의 박스 하나. cls 는 현재 'varroa' 뿐이다
/// (정상 벌 박스는 생성 단계에서 버린다 — 설계 §6).
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
    cls: json['cls'] as String? ?? 'varroa',
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
    required this.beeTotal,
    required this.varroaCount,
    required this.recommendations,
    required this.boxes,
  });

  final String id;
  final String photo;
  final int imageWidth;
  final int imageHeight;
  final int riskScore;
  final RiskTier tier;
  final int beeTotal;
  final int varroaCount;
  final List<String> recommendations;
  final List<BoothBox> boxes;

  /// 관람객이 '건강함'이라고 답했을 때 맞은 것으로 칠지.
  bool get isHealthy => tier == RiskTier.safe;

  factory BoothCase.fromJson(Map<String, dynamic> json) => BoothCase(
    id: json['id'] as String,
    photo: json['photo'] as String,
    imageWidth: (json['imageWidth'] as num).toInt(),
    imageHeight: (json['imageHeight'] as num).toInt(),
    riskScore: (json['riskScore'] as num).toInt(),
    tier: riskTierFromName(json['tier'] as String?),
    beeTotal: (json['beeTotal'] as num).toInt(),
    varroaCount: (json['varroaCount'] as num).toInt(),
    recommendations: (json['recommendations'] as List<dynamic>)
        .map((e) => e as String)
        .toList(growable: false),
    boxes: (json['boxes'] as List<dynamic>)
        .map((e) => BoothBox.fromJson((e as Map).cast<String, dynamic>()))
        .toList(growable: false),
  );
}
