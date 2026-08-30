import 'dart:convert';

import 'package:flutter/services.dart';

import 'booth_case.dart';

/// assets/cases.json 을 읽어 케이스 목록을 만든다.
/// 실패하면 그대로 던진다 — 부스 앱은 에셋이 없으면 뜰 이유가 없다.
Future<List<BoothCase>> loadBoothCases(AssetBundle bundle) async {
  final raw = await bundle.loadString('assets/cases.json');
  final decoded = jsonDecode(raw) as Map<String, dynamic>;
  return (decoded['cases'] as List<dynamic>)
      .map((e) => BoothCase.fromJson((e as Map).cast<String, dynamic>()))
      .toList(growable: false);
}
