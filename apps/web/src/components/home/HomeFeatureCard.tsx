import { Card } from '@helpbee/ui';
import type { ReactNode } from 'react';

export function HomeFeatureCard({
  icon,
  title,
  description,
}: {
  icon: ReactNode;
  title: string;
  description: string;
}) {
  return (
    <Card className="flex items-start gap-5 p-6 shadow-sm ring-1 ring-honey-100 md:p-8">
      <div
        aria-hidden="true"
        className="flex h-12 w-12 shrink-0 items-center justify-center rounded-full bg-honey-500 text-white"
      >
        {icon}
      </div>
      <div>
        <h3 className="text-xl font-bold text-bee-black">{title}</h3>
        <p className="mt-2 text-lg leading-relaxed text-bee-black/70">{description}</p>
      </div>
    </Card>
  );
}
