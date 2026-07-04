import { cn } from '@helpbee/ui';

export function SectionHeading({
  title,
  subtitle,
  className,
}: {
  title: string;
  subtitle?: string;
  className?: string;
}) {
  return (
    <div className={cn('text-center', className)}>
      <h2 className="text-3xl font-bold text-bee-black md:text-4xl">{title}</h2>
      {subtitle ? <p className="mt-3 text-lg text-bee-black/70 md:text-xl">{subtitle}</p> : null}
    </div>
  );
}
