import 'dart:convert';

import 'package:flutter/services.dart';

import 'booth_case.dart';

/// assets/cases.json 을 읽어 케이스 목록을 만든다.
/// 실패하면 그대로 던진다 — 부스 앱은 에셋이 없으면 뜰 이유가 없다.
///
/// `loadString` 이 아니라 `load` + 직접 디코드다. `loadString` 은 50KB 를 넘으면
/// 별도 isolate 에서 UTF-8 을 풀고 그 결과를 기다리는데, 위젯 테스트의
/// FakeAsync 존에서는 그 Future 가 완료되지 않아 앱이 영영 "불러오는 중"에
/// 머문다(2026-09-16 — 15장·박스 400여 개로 80KB 가 되면서 실제로 겪었다).
/// 80KB 를 메인 isolate 에서 푸는 데 드는 시간은 밀리초 단위라 잃는 게 없다.
Future<List<BoothCase>> loadBoothCases(AssetBundle bundle) async {
  final bytes = await bundle.load('assets/cases.json');
  final raw = utf8.decode(
    bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
  );
  final decoded = jsonDecode(raw) as Map<String, dynamic>;
  return (decoded['cases'] as List<dynamic>)
      .map((e) => BoothCase.fromJson((e as Map).cast<String, dynamic>()))
      .toList(growable: false);
}
