import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 부스가 실제로 도는 화면 크기(iPad Air 13" 가로 논리 픽셀).
const Size kBoothSurface = Size(1366, 1024);

/// 위젯 테스트 표면을 실제 기기 크기로 맞춘다. 기본값 800x600 으로 테스트하면
/// 배포되지 않는 레이아웃을 검증하게 된다.
Future<void> useBoothSurface(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(kBoothSurface);
  addTearDown(() => tester.binding.setSurfaceSize(null));
}
