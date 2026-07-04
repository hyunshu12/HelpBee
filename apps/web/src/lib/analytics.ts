let loaded = false;

type GtagWindow = {
  dataLayer?: unknown[];
  gtag?: (...args: unknown[]) => void;
};

/**
 * GA4/Hotjar 로더 — 쿠키 동의 후에만 호출(CookieConsent).
 * env(NEXT_PUBLIC_GA_ID / NEXT_PUBLIC_HOTJAR_ID)가 없으면 미로드.
 */
export function loadAnalytics(): void {
  if (loaded || typeof window === 'undefined') return;

  const gaId = process.env.NEXT_PUBLIC_GA_ID;
  const hotjarId = process.env.NEXT_PUBLIC_HOTJAR_ID;
  if (!gaId && !hotjarId) return;

  loaded = true;
  const w = window as unknown as GtagWindow;

  if (gaId) {
    const script = document.createElement('script');
    script.async = true;
    script.src = `https://www.googletagmanager.com/gtag/js?id=${gaId}`;
    document.head.appendChild(script);

    w.dataLayer = w.dataLayer || [];
    w.gtag = (...args: unknown[]) => {
      w.dataLayer!.push(args);
    };
    w.gtag('js', new Date());
    w.gtag('config', gaId);
  }

  if (hotjarId) {
    const script = document.createElement('script');
    script.async = true;
    script.src = `https://static.hotjar.com/c/hotjar-${hotjarId}.js?sv=6`;
    document.head.appendChild(script);
  }
}
