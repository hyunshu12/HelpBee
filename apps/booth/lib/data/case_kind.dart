/// 케이스의 성격. **라운드 배정의 유일한 키**이자, 결과 화면이 무엇을
/// 그릴지 결정하는 값이다 (설계 §2·§4.4).
///
/// - [visible]  눈에 보이는 병 (석고병·날개불구) — R1, 관람객이 맞히기 쉽다
/// - [varroa]   응애 — R2/R3, 알고 봐도 안 보인다
/// - [healthy]  정상 — R3 의 함정
///
/// tier 로 대신할 수 없다: 다른 병 케이스는 응애가 0이라 `compute_risk` 가
/// tier=safe 를 준다(2026-09-08 실측 — chalk-1/chalk-2/dwv-1 모두 safe).
/// tier 는 *응애* 위험도라 병 종류를 구분하지 못한다.
enum CaseKind { visible, varroa, healthy }

/// cases.json 의 kind 문자열 → enum.
///
/// 모르는 값은 [CaseKind.varroa] 로 떨어뜨린다 — healthy 로 잘못 떨어지면
/// 병든 벌통을 "정답: 건강함"으로 채점하게 되므로, 틀리더라도 안전한 쪽으로.
CaseKind caseKindFromName(String? name) => switch (name) {
  'visible' => CaseKind.visible,
  'healthy' => CaseKind.healthy,
  _ => CaseKind.varroa,
};
