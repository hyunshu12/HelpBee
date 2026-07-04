import { Button } from '@helpbee/ui';

import { Container } from '@/components/Container';
import { PlaceholderImage } from '@/components/PlaceholderImage';
import { Link } from '@/i18n/navigation';

export function Hero({
  title,
  subtitle,
  cta,
  imageLabel,
}: {
  title: string;
  subtitle: string;
  cta: string;
  imageLabel: string;
}) {
  return (
    <section className="bg-gradient-to-b from-honey-50 to-white">
      <Container className="grid grid-cols-1 items-center gap-10 py-16 md:grid-cols-2 md:gap-12 md:py-24">
        <div className="text-center md:text-left">
          <h1 className="text-4xl font-extrabold leading-tight text-bee-black md:text-5xl">
            {title}
          </h1>
          <p className="mt-6 text-lg leading-relaxed text-bee-black/70 md:text-xl">{subtitle}</p>
          <div className="mt-8 flex justify-center md:justify-start">
            <Link href="/download">
              <Button variant="primary" size="lg">
                {cta}
              </Button>
            </Link>
          </div>
        </div>
        <PlaceholderImage label={imageLabel} className="aspect-[4/3] w-full rounded-3xl" />
      </Container>
    </section>
  );
}
