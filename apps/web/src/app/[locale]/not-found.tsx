import { Button } from '@helpbee/ui';
import Link from 'next/link';

import { Container } from '@/components/Container';

// 404는 locale 컨텍스트 밖에서도 렌더될 수 있어 고정 문구 사용. 링크는 middleware가 로케일 보정.
export default function NotFound() {
  return (
    <Container className="flex flex-col items-center gap-6 py-24 text-center md:py-32">
      <p className="text-6xl font-extrabold text-honey-500">404</p>
      <h1 className="text-3xl font-bold text-bee-black md:text-4xl">페이지를 찾을 수 없습니다</h1>
      <p className="text-lg text-bee-black/70">요청하신 페이지가 존재하지 않거나 이동되었습니다.</p>
      <div className="flex flex-wrap justify-center gap-3">
        <Link href="/">
          <Button>홈으로</Button>
        </Link>
        <Link href="/blog">
          <Button variant="outline">블로그 둘러보기</Button>
        </Link>
      </div>
    </Container>
  );
}
