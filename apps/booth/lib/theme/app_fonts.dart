/// 번들 서체 이름의 단일 소스.
///
/// 왜 상수로 두는가: `TextPainter` 처럼 **위젯 트리 밖에서** 그리는 텍스트는
/// 테마를 상속하지 않는다. 거기서 서체를 지정하지 않으면 플랫폼 기본 서체로
/// 떨어지는데, Flutter Web 에는 한글 기본 서체가 없어 글자가 전부 두부(□)로
/// 그려진다 (2026-08-31 실측: 추이 그래프의 '위험 70+' 라벨).
library;

/// 본문 한글 서체. pubspec.yaml 의 `fonts:` 선언과 반드시 같아야 한다.
const String kBodyFont = 'NotoSansKR';

/// 표시용(헤드라인·숫자) 서체.
const String kDisplayFont = 'Jua';

/// 서브셋에 없는 글자를 위한 폴백. 두부 대신 최소한 읽히게 한다.
const List<String> kFontFallback = [kDisplayFont];
