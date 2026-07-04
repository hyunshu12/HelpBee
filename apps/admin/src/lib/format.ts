/** 표시용 포매터 + 한국어 라벨 매핑. */

const KST = new Intl.DateTimeFormat('ko-KR', {
  timeZone: 'Asia/Seoul',
  year: 'numeric',
  month: '2-digit',
  day: '2-digit',
  hour: '2-digit',
  minute: '2-digit',
});

export function formatKst(iso: string | null): string {
  if (!iso) return '-';
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return '-';
  return KST.format(d);
}

export const ROLE_LABEL: Record<string, string> = { user: '일반', admin: '관리자' };
export const STATUS_LABEL: Record<string, string> = {
  active: '정상',
  blocked: '차단',
  deleted: '탈퇴',
};
export const HEALTH_LABEL: Record<string, string> = {
  healthy: '건강',
  warning: '주의',
  critical: '위험',
};
export const ANALYSIS_STATUS_LABEL: Record<string, string> = {
  pending: '대기',
  success: '성공',
  failed: '실패',
};
export const PROVIDER_LABEL: Record<string, string> = { openai: 'OpenAI', yolo: 'YOLO' };
export const PLAN_LABEL: Record<string, string> = { free: '무료', basic: '베이직', pro: '프로' };

export function label(map: Record<string, string>, key: string | null | undefined): string {
  if (!key) return '-';
  return map[key] ?? key;
}
