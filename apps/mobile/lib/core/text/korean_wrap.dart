/// 한글 줄바꿈 보정.
///
/// Flutter에는 CSS `word-break: keep-all`에 해당하는 API가 없다. 기본 줄바꿈은
/// 한글을 음절 단위로 끊기 때문에 "즉시"가 "즉 / 시"로 갈라진다. 음절 사이에
/// WORD JOINER(U+2060)를 넣어 어절이 통째로 다음 줄로 넘어가게 만든다.
library;

final RegExp _hangulRun = RegExp('[가-힣]{2,}');

/// 한글이 이보다 길게 이어지면 손대지 않는다. 끊을 자리를 전부 없애면 줄 폭보다
/// 긴 덩어리가 잘리지 못하고 넘치기 때문.
const int _maxRunLength = 20;

const String _wordJoiner = '\u2060';

/// 연속된 한글 음절 사이에 WORD JOINER를 끼워 어절 중간 줄바꿈을 막는다.
/// 공백·문장부호·영문·개행은 그대로 두므로 그 자리에서는 정상적으로 줄이 바뀐다.
String keepAll(String text) {
  return text.replaceAllMapped(_hangulRun, (match) {
    final run = match[0]!;
    if (run.length > _maxRunLength) return run;
    return run.split('').join(_wordJoiner);
  });
}
