import { Card } from '@helpbee/ui';
import type { ReactNode } from 'react';

export function IntroCard({
  icon,
  title,
  description,
}: {
  icon: ReactNode;
  title: string;
  description: string;
}) {
  return (
    <Card className="flex flex-col items-center p-8 text-center shadow-sm ring-1 ring-honey-100">
      <div
        aria-hidden="true"
        className="flex h-16 w-16 items-center justify-center rounded-full bg-honey-50 text-honey-600"
      >
        {icon}
      </div>
      <h3 className="mt-6 text-xl font-bold text-bee-black">{title}</h3>
      <p className="mt-3 text-lg leading-relaxed text-bee-black/70">{description}</p>
    </Card>
  );
}
