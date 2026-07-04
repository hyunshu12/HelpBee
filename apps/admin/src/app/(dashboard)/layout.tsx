import type { ReactNode } from 'react';

import { LogoutButton } from '@/src/components/LogoutButton';
import { SidebarNav } from '@/src/components/SidebarNav';
import { Providers } from '@/src/app/providers';

export default function DashboardLayout({ children }: { children: ReactNode }) {
  return (
    <Providers>
      <div className="flex min-h-screen">
        <aside className="hidden w-60 shrink-0 flex-col border-r border-honey-200 bg-white p-4 md:flex">
          <div className="mb-6 px-4 pt-2">
            <span className="font-logo text-2xl font-bold text-honey-600">HelpBee</span>
            <p className="text-xs text-bee-brown">관리자</p>
          </div>
          <SidebarNav />
        </aside>

        <div className="flex min-w-0 flex-1 flex-col">
          <header className="flex h-16 items-center justify-between border-b border-honey-200 bg-white px-6">
            <span className="text-base font-semibold text-bee-black md:hidden">HelpBee 관리자</span>
            <div className="ml-auto">
              <LogoutButton />
            </div>
          </header>
          <main className="flex-1 p-6">{children}</main>
        </div>
      </div>
    </Providers>
  );
}
