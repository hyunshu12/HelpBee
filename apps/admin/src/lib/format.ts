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

/**
 * VDI 표시 문자열 — AI가 한 번만 반올림한 `raw_response.vdi_display`(tier의 근거)를 그대로 쓴다(스펙 §3, 재반올림 금지).
 * numeric(6,3) 컬럼을 toFixed(1)로 다시 반올림하면 9.950→"9.9"처럼 tier(high)와 모순될 수 있어,
 * 숫자 컬럼은 vdi_display가 없는 행(구 row 등)의 폴백으로만 쓴다. CI는 tier 근거가 아니므로 toFixed 허용.
 */
export function formatVdi(row: {
  vdi: number | null;
  vdiCiLow: number | null;
  vdiCiHigh: number | null;
  rawResponse: Record<string, unknown> | null;
}): string {
  const display = row.rawResponse?.vdi_display;
  const main =
    typeof display === 'string' && display !== ''
      ? display
      : row.vdi != null
        ? row.vdi.toFixed(1)
        : null;
  if (main == null) return '-';
  const ci =
    row.vdiCiLow != null && row.vdiCiHigh != null
      ? ` (${row.vdiCiLow.toFixed(1)}–${row.vdiCiHigh.toFixed(1)}%)`
      : '';
  return `${main}%${ci}`;
}
