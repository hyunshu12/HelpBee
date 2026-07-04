import { Button, Card } from '@helpbee/ui';
import { useTranslations } from 'next-intl';

/** 직접 문의 3채널 카드 (실시간 채팅 / 이메일 / 전화). */
export function ContactChannels() {
  const t = useTranslations('contact');

  return (
    <div className="mt-10 grid grid-cols-1 gap-6 md:grid-cols-3">
      <Card className="flex flex-col gap-3 border border-honey-100 p-8 shadow-sm">
        <h3 className="text-xl font-bold text-bee-black">{t('channels.chat.title')}</h3>
        <p className="text-lg text-bee-black/70">{t('channels.chat.desc')}</p>
        <div className="mt-auto pt-4">
          <Button variant="primary" size="md" disabled aria-disabled="true">
            {t('channels.chat.action')}
          </Button>
        </div>
      </Card>

      <Card className="flex flex-col gap-3 border border-honey-100 p-8 shadow-sm">
        <h3 className="text-xl font-bold text-bee-black">{t('channels.email.title')}</h3>
        <p className="text-lg text-bee-black/70">{t('channels.email.desc')}</p>
        <div className="mt-auto pt-4">
          <a
            href="mailto:support@helpbee.com"
            className="text-lg font-semibold text-honey-600 underline-offset-4 hover:underline"
          >
            support@helpbee.com
          </a>
        </div>
      </Card>

      <Card className="flex flex-col gap-3 border border-honey-100 p-8 shadow-sm">
        <h3 className="text-xl font-bold text-bee-black">{t('channels.phone.title')}</h3>
        <p className="text-lg text-bee-black/70">{t('channels.phone.desc')}</p>
        <div className="mt-auto pt-4">
          <a
            href="tel:+820212345678"
            className="text-lg font-semibold text-honey-600 underline-offset-4 hover:underline"
          >
            02-1234-5678
          </a>
        </div>
      </Card>
    </div>
  );
}
