import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    environment: 'node',
    include: ['src/**/*.test.ts'],
    pool: 'forks',
    // 통합 스위트는 같은 helpbee_test DB를 공유하고 integration.test.ts가 전체 테이블 wipe를
    // 하므로, 파일 병렬 실행 시 서로의 데이터를 지운다. 순차 실행으로 격리.
    fileParallelism: false,
    testTimeout: 20000,
    hookTimeout: 20000,
  },
});
