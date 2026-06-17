import { cn } from '@helpbee/ui';

export type PricingTableRow = {
  label: string;
  basic: string;
  pro: string;
  enterprise: string;
};

export type PricingTableProps = {
  columns: {
    feature: string;
    basic: string;
    pro: string;
    enterprise: string;
  };
  rows: PricingTableRow[];
};

export function PricingTable({ columns, rows }: PricingTableProps) {
  return (
    <div className="overflow-x-auto rounded-2xl border border-bee-black/10">
      <table className="w-full min-w-[640px] border-collapse text-left">
        <caption className="sr-only">{columns.feature}</caption>
        <thead>
          <tr className="bg-honey-500 text-white">
            <th scope="col" className="px-6 py-4 text-lg font-bold">
              {columns.feature}
            </th>
            <th scope="col" className="px-6 py-4 text-center text-lg font-bold">
              {columns.basic}
            </th>
            <th scope="col" className="px-6 py-4 text-center text-lg font-bold">
              {columns.pro}
            </th>
            <th scope="col" className="px-6 py-4 text-center text-lg font-bold">
              {columns.enterprise}
            </th>
          </tr>
        </thead>
        <tbody>
          {rows.map((row, index) => (
            <tr
              key={row.label}
              className={cn(index % 2 === 1 ? 'bg-surface-row' : 'bg-white')}
            >
              <th
                scope="row"
                className="px-6 py-4 text-lg font-semibold text-bee-black"
              >
                {row.label}
              </th>
              <td className="px-6 py-4 text-center text-lg text-bee-black/80">{row.basic}</td>
              <td className="px-6 py-4 text-center text-lg font-semibold text-honey-700">
                {row.pro}
              </td>
              <td className="px-6 py-4 text-center text-lg text-bee-black/80">
                {row.enterprise}
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}
