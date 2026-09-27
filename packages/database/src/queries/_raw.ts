import { sql, type SQL } from 'drizzle-orm';

import { analyses } from '../schema/analyses';

/**
 * analyses.raw_response 의 최상위 필드를 텍스트로 읽는다.
 * drizzle 0.29 + postgres-js 조합은 jsonb 를 **JSON 문자열로 이중 인코딩**해 저장한다
 * (jsonb_typeof = 'string'). 그대로 `->>'tier'` 하면 항상 NULL — 문자열이면 한 번 풀어서 읽는다.
 * 객체로 저장된 행(수동/다른 경로)도 동일하게 동작.
 */
export function rawResponseField(key: string): SQL<string | null> {
  return sql<string | null>`(case when jsonb_typeof(${analyses.rawResponse}) = 'string' then (${analyses.rawResponse} #>> '{}')::jsonb else ${analyses.rawResponse} end) ->> ${sql.raw(`'${key.replace(/[^a-z0-9_]/gi, '')}'`)}`;
}
