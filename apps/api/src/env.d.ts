// Hono Context 변수 타입 선언 — c.set/get('userId'|'role'|'requestId') 타입 안전.
import 'hono';

declare module 'hono' {
  interface ContextVariableMap {
    userId: string;
    role: string;
    requestId: string;
    aud?: string; // access 토큰 audience(admin 스코프 검증, §17-4)
    webhookBody?: unknown; // webhook 서명 검증 후 파싱된 body(§11.4)
  }
}
