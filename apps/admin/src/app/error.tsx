'use client';

import { Button } from '@helpbee/ui';

export default function Error({ reset }: { error: Error; reset: () => void }) {
  return (
    <main className="flex min-h-screen flex-col items-center justify-center gap-4 bg-honey-50 px-4 text-center">
      <h1 className="text-2xl font-bold text-bee-black">문제가 발생했습니다</h1>
      <p className="text-base text-bee-brown">잠시 후 다시 시도해 주세요.</p>
      <Button onClick={reset}>다시 시도</Button>
    </main>
  );
}
