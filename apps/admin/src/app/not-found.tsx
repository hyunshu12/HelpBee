import { Button } from '@helpbee/ui';
import Link from 'next/link';

export default function NotFound() {
  return (
    <main className="flex min-h-screen flex-col items-center justify-center gap-4 bg-honey-50 px-4 text-center">
      <h1 className="text-4xl font-bold text-honey-600">404</h1>
      <p className="text-lg text-bee-brown">요청한 페이지를 찾을 수 없습니다.</p>
      <Link href="/">
        <Button>대시보드로</Button>
      </Link>
    </main>
  );
}
