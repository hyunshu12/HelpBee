import { Badge, Button, Card, cn } from '@helpbee/ui';

import { Link } from '@/i18n/navigation';

export type PricingCardProps = {
  name: string;
  description: string;
  price: string;
  priceNote: string;
  features: string[];
  ctaLabel: string;
  ctaHref: '/download' | '/contact';
  ctaVariant: 'primary' | 'outline';
  recommended?: boolean;
  recommendedLabel?: string;
  featuresLabel: string;
};

export function PricingCard({
  name,
  description,
  price,
  priceNote,
  features,
  ctaLabel,
  ctaHref,
  ctaVariant,
  recommended = false,
  recommendedLabel,
  featuresLabel,
}: PricingCardProps) {
  return (
    <Card
      className={cn(
        'relative flex flex-col gap-6 p-6 md:p-8',
        recommended
          ? 'border-2 border-honey-500 shadow-lg shadow-honey-500/10 md:-mt-4 md:mb-4'
          : 'border border-bee-black/10',
      )}
    >
      {recommended && recommendedLabel ? (
        <Badge
          variant="solid"
          className="absolute -top-3 left-1/2 -translate-x-1/2 px-4 py-1 text-base"
        >
          {recommendedLabel}
        </Badge>
      ) : null}

      <div className="flex flex-col gap-2">
        <h3 className="text-2xl font-bold text-bee-black">{name}</h3>
        <p className="text-lg text-bee-black/70">{description}</p>
      </div>

      <div className="flex flex-col gap-1">
        <span className="text-3xl font-extrabold text-honey-600 md:text-4xl">{price}</span>
        <span className="text-base text-bee-black/50">{priceNote}</span>
      </div>

      <div className="flex flex-1 flex-col gap-3">
        <span className="text-base font-semibold text-bee-black/60">{featuresLabel}</span>
        <ul className="flex flex-col gap-3">
          {features.map((feature) => (
            <li key={feature} className="flex items-start gap-3 text-lg text-bee-black/80">
              <span
                aria-hidden="true"
                className="mt-1 flex h-5 w-5 flex-none items-center justify-center rounded-full bg-honey-100 text-sm font-bold text-honey-700"
              >
                ✓
              </span>
              <span>{feature}</span>
            </li>
          ))}
        </ul>
      </div>

      <Link href={ctaHref} className="mt-2 block">
        <Button variant={ctaVariant} size="lg" className="w-full">
          {ctaLabel}
        </Button>
      </Link>
    </Card>
  );
}
