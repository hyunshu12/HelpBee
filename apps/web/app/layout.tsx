import type { Metadata } from 'next'

export const metadata: Metadata = {
  title: 'HelpBee',
  description: 'AI 기반 스마트 양봉 진단 플랫폼',
}

export default function RootLayout({
  children,
}: {
  children: React.ReactNode
}) {
  return (
    <html lang="ko">
      <body>{children}</body>
    </html>
  )
}
