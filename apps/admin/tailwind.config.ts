import type { Config } from 'tailwindcss';
// Next가 tsc moduleResolution을 'node'(레거시)로 강제해 exports 서브패스를 못 푸므로
// 설정 파일에서는 소스 상대경로로 직접 가져온다(런타임 jiti도 동일하게 해석).
import preset from '../../packages/ui/src/tokens/tailwind.preset';

const config: Config = {
  presets: [preset],
  content: [
    './src/**/*.{ts,tsx,mdx}',
    '../../packages/ui/src/**/*.{ts,tsx}',
  ],
};

export default config;
