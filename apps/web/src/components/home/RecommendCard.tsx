import { Card } from '@helpbee/ui';

import { PlaceholderImage } from '@/components/PlaceholderImage';

export function RecommendCard({
  imageLabel,
  name,
  benefit,
}: {
  imageLabel: string;
  name: string;
  benefit: string;
}) {
  return (
    <Card className="flex flex-col overflow-hidden shadow-sm ring-1 ring-honey-100">
      <PlaceholderImage label={imageLabel} className="aspect-[4/3] w-full rounded-none" />
      <div className="p-6 text-center">
        <h3 className="text-xl font-bold text-bee-black">{name}</h3>
        <p className="mt-2 text-lg leading-relaxed text-bee-black/70">{benefit}</p>
      </div>
    </Card>
  );
}
