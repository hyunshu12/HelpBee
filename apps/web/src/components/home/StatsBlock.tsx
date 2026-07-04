export function StatsBlock({ value, label }: { value: string; label: string }) {
  return (
    <div className="text-center">
      <div className="text-4xl font-extrabold text-honey-600 md:text-5xl">{value}</div>
      <div className="mt-2 text-lg font-medium text-bee-black/70">{label}</div>
    </div>
  );
}
