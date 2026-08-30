import 'package:flutter/widgets.dart';

/// 부스 화면의 코너 스케일. apps/mobile(카드 16)보다 크게 잡는다 — 화면이
/// 1366x1024 로 훨씬 넓어 같은 반경이면 각져 보인다.
abstract final class AppRadius {
  AppRadius._();

  static const double chip = 999;
  static const double button = 18;
  static const double photo = 24;
  static const double card = 28;

  static const BorderRadius buttonRadius = BorderRadius.all(
    Radius.circular(button),
  );
  static const BorderRadius photoRadius = BorderRadius.all(
    Radius.circular(photo),
  );
  static const BorderRadius cardRadius = BorderRadius.all(
    Radius.circular(card),
  );
}
