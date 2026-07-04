import { cn } from '@helpbee/ui';

/**
 * 촬영 단계의 팁 박스 — 시안의 강조 박스(연한 배경 + 꿀색 보더).
 * 사용자 노출 문자열은 모두 부모(StepRow / page)에서 props로 주입.
 */
export function TipBox({
  title,
  items,
  className,
}: {
  title: string;
  items: string[];
  className?: string;
}) {
  return (
    <div
      className={cn(
        'rounded-2xl border border-honey-500 bg-surface-tip p-6 md:p-8',
        className,
      )}
    >
      <p className="text-base font-bold uppercase tracking-wide text-honey-600">{title}</p>
      <ul className="mt-4 flex flex-col gap-3">
        {items.map((item) => (
          <li key={item} className="flex items-start gap-3 text-lg text-bee-black/80">
            <span
              aria-hidden="true"
              className="mt-2 inline-block h-2 w-2 shrink-0 rounded-full bg-honey-500"
            />
            <span>{item}</span>
          </li>
        ))}
      </ul>
    </div>
  );
}
