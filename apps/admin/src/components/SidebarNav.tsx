'use client';

import { cn } from '@helpbee/ui';
import Link from 'next/link';
import { usePathname } from 'next/navigation';

const NAV = [
  { href: '/', label: '대시보드' },
  { href: '/users', label: '사용자' },
  { href: '/audit-log', label: '감사 로그' },
];

export function SidebarNav() {
  const pathname = usePathname();
  return (
    <nav className="space-y-1">
      {NAV.map((item) => {
        const active = item.href === '/' ? pathname === '/' : pathname.startsWith(item.href);
        return (
          <Link
            key={item.href}
            href={item.href}
            className={cn(
              'block rounded-xl px-4 py-2.5 text-base font-medium transition-colors',
              active ? 'bg-honey-500 text-white' : 'text-bee-brown hover:bg-honey-100',
            )}
          >
            {item.label}
          </Link>
        );
      })}
    </nav>
  );
}
