import 'package:flutter/services.dart';

/// 발표 슬라이드 묶음 — 에셋 경로 목록과 현재 장. 위젯을 모른다.
///
/// 이사장님 발표(2026-09)용. 슬라이드는 Figma 에서 내보내
/// `assets/slides/01.jpg …` 에 둔 것뿐이고, 앱은 그걸 넘기기만 한다.
class SlideDeck {
  SlideDeck(this.paths, {this.demoIndex}) : assert(paths.isNotEmpty);

  /// 이름순. 첫 장이 `paths[0]`.
  final List<String> paths;

  /// "시연 시작" 버튼이 뜨는 장(0-base). null 이면 시연 없는 덱.
  final int? demoIndex;

  int index = 0;

  bool get isFirst => index == 0;
  bool get isLast => index == paths.length - 1;
  bool get isDemo => demoIndex != null && index == demoIndex;

  /// 다음 장. 마지막 장이면 false — 호출자가 "발표 끝"으로 처리한다.
  bool next() {
    if (isLast) return false;
    index++;
    return true;
  }

  /// 이전 장. 첫 장이면 false 로 무시.
  bool prev() {
    if (isFirst) return false;
    index--;
    return true;
  }

  /// 시연에서 돌아올 때 — 시연 장의 **다음** 장. 시연 장이 마지막이면 그 장.
  void returnFromDemo() {
    final d = demoIndex;
    if (d == null) return;
    index = (d + 1).clamp(0, paths.length - 1);
  }
}

/// 에셋 키 목록에서 `assets/slides/*.png|jpg` 만 이름순으로 골라 덱을 만든다.
/// 하나도 없으면 null — 슬라이드가 없는 부스 빌드에서는 발표 모드 자체가 없다.
///
/// 순수 함수로 떼어둔 이유: [AssetManifest] 는 테스트에서 가짜로 만들기 번거롭다.
SlideDeck? slideDeckFromAssetKeys(Iterable<String> keys, {int? demoIndex}) {
  final paths =
      keys
          .where(
            (k) =>
                k.startsWith('assets/slides/') &&
                (k.endsWith('.png') || k.endsWith('.jpg')),
          )
          .toList()
        ..sort();
  if (paths.isEmpty) return null;
  final demo = demoIndex != null && demoIndex >= 0 && demoIndex < paths.length
      ? demoIndex
      : null;
  return SlideDeck(paths, demoIndex: demo);
}

/// 앱 에셋 매니페스트에서 덱을 만든다. 슬라이드가 없으면 null.
Future<SlideDeck?> loadSlideDeck(AssetBundle bundle, {int? demoIndex}) async {
  final manifest = await AssetManifest.loadFromAssetBundle(bundle);
  return slideDeckFromAssetKeys(manifest.listAssets(), demoIndex: demoIndex);
}
