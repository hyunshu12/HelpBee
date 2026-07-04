const STORE = {
  appstore: { label: 'App Store', url: process.env.NEXT_PUBLIC_APP_STORE_URL },
  playstore: { label: 'Google Play', url: process.env.NEXT_PUBLIC_PLAY_STORE_URL },
} as const;

export function StoreBadge({ store }: { store: keyof typeof STORE }) {
  const { label, url } = STORE[store];
  return (
    <a
      href={url || '#'}
      target="_blank"
      rel="noopener noreferrer"
      className="inline-flex items-center rounded-xl border border-bee-black/15 bg-white px-3 py-2 text-sm font-semibold text-bee-black transition-colors hover:bg-honey-50"
    >
      {label}
    </a>
  );
}
