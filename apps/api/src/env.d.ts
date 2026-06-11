// Hono Context 변수 타입 선언 — c.set/get('userId'|'role'|'requestId') 타입 안전.
import 'hono';

declare module 'hono' {
  interface ContextVariableMap {
    userId: string;
    role: string;
    requestId: string;
  }
}
