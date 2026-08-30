import 'package:flutter/material.dart';

/// HelpBee design tokens (from Figma) + 부스 전용 확장.
///
/// This is the SINGLE source of truth for color hex values in the app.
/// Widgets/screens must NEVER hardcode hex — only reference [AppColors] or
/// `Theme.of(context)`.
abstract final class AppColors {
  AppColors._();

  // ── Brand / honey palette ────────────────────────────────────────────────
  /// CTA fill (primary buttons).
  static const Color honeyPrimary = Color(0xFFFFD869);

  /// Logo / wordmark brand color.
  static const Color honeyBrand = Color(0xFFF9CA46);

  /// Accent / subtitle (deep amber).
  static const Color amberDeep = Color(0xFFE79D04);

  /// Checkbox / selected light tint.
  static const Color honeyLight = Color(0xFFFFE18C);

  // ── Backgrounds / surfaces ───────────────────────────────────────────────
  /// Splash (dark) background.
  static const Color splashBg = Color(0xFF18130C);

  /// Scaffold background (light).
  static const Color bgLight = Color(0xFFFDFCF9);

  /// Card / sheet surface.
  static const Color surface = Color(0xFFFFFFFF);

  // ── Text ─────────────────────────────────────────────────────────────────
  static const Color textPrimary = Color(0xFF18130C);
  static const Color textSecondary = Color(0xFF3C3C3C);

  /// Input border + placeholder text.
  static const Color hintBorder = Color(0xFFB9B9B9);

  // ── Tier (risk) colors ───────────────────────────────────────────────────
  static const Color tierSafe = Color(0xFF2E9E5B);
  static const Color tierWatch = Color(0xFFE79D04);
  static const Color tierDanger = Color(0xFFD7443E);
  static const Color tierUnknown = Color(0xFFB9B9B9);

  // ── Semantic ─────────────────────────────────────────────────────────────
  static const Color error = Color(0xFFD32F2F);
  static const Color divider = Color(0xFFEAE6DD);

  /// Modal scrim (dim behind loading overlays / dialogs).
  static const Color scrim = Color(0x66000000);

  // ══ 부스 전용 확장 ════════════════════════════════════════════════════════
  // 부스는 서서, 1m 밖에서, 형광등 아래 보는 화면이다. apps/mobile 의 팔레트를
  // 그대로 쓰되 (1) 카드가 배경에서 떠 보이도록 따뜻한 그림자·테두리, (2) 어트랙트
  // /마무리처럼 시선을 끌어야 하는 화면용 다크 스테이지 색을 추가한다.

  /// 밝은 화면의 캔버스. bgLight 보다 노란기를 살짝 더 줘 꿀 톤을 유지한다.
  static const Color boothBg = Color(0xFFFFFBF0);

  /// 다크 스테이지 배경 (어트랙트·마무리). splashBg 와 같은 값 — 모바일 스플래시와
  /// 같은 검정을 써야 두 앱이 한 브랜드로 보인다.
  static const Color boothInk = splashBg;

  /// 다크 스테이지 위에 얹는 카드/패널 면.
  static const Color boothInkSoft = Color(0xFF241C12);

  /// 다크 스테이지의 헤어라인 테두리.
  static const Color boothInkLine = Color(0xFF3D3123);

  /// 다크 스테이지 본문 텍스트.
  static const Color onInk = Color(0xFFFDFCF9);

  /// 다크 스테이지 보조 텍스트.
  static const Color onInkSoft = Color(0xFFC4B79E);

  // ── 티어 배지의 옅은 배경 ────────────────────────────────────────────────
  static const Color tierSafeSoft = Color(0xFFE4F3EA);
  static const Color tierWatchSoft = Color(0xFFFCEFD8);
  static const Color tierDangerSoft = Color(0xFFFAE4E3);
  static const Color tierUnknownSoft = Color(0xFFEFEDE8);

  // ── 꿀색 옅은 톤 (칩·보조 버튼) ──────────────────────────────────────────
  static const Color honeySoft = Color(0xFFFFF3CF);
  static const Color honeyEdge = Color(0xFFEFDBA4);

  /// 카드 그림자. 회색이 아니라 **따뜻한 갈색 계열**이다 — 크림 배경 위에
  /// 중성 회색 그림자를 쓰면 화면이 탁해지고 "기본 템플릿" 인상이 난다.
  static const Color shadowWarm = Color(0x1A8A6A14);
  static const Color shadowWarmStrong = Color(0x2E6B4E0C);
}
