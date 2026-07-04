'use client';

import { zodResolver } from '@hookform/resolvers/zod';
import { Button, Input, Textarea, cn } from '@helpbee/ui';
import { useTranslations } from 'next-intl';
import { useId, useState } from 'react';
import { useForm, type Resolver } from 'react-hook-form';
import { z } from 'zod';

import { Link } from '@/i18n/navigation';
import { submitInquiry } from '@/lib/inquiries';

const INQUIRY_TYPES = ['service', 'tech', 'plan', 'etc'] as const;

// Validation messages stay inline (Korean) per spec; section/labels go through namespace.
const schema = z.object({
  name: z
    .string()
    .trim()
    .min(1, '이름을 입력해주세요.')
    .max(60, '이름은 60자 이내로 입력해주세요.'),
  email: z
    .string()
    .trim()
    .min(1, '이메일을 입력해주세요.')
    .email('올바른 이메일 형식이 아닙니다.'),
  type: z.enum(INQUIRY_TYPES),
  message: z.string().trim().min(1, '문의 내용을 입력해주세요.'),
  agree: z.literal(true, {
    errorMap: () => ({ message: '개인정보 수집 및 이용에 동의해주세요.' }),
  }),
});

type FormValues = z.infer<typeof schema>;

export function ContactForm() {
  const t = useTranslations('contact');
  const baseId = useId();
  const [notice, setNotice] = useState<string | null>(null);

  const {
    register,
    handleSubmit,
    formState: { errors, isSubmitting },
  } = useForm<FormValues>({
    // 모노레포에 zod3(web)·zod4(api)가 공존 → TS가 resolvers의 zod peer를 zod4로 해석해
    // zod3 스키마를 거부함. 런타임은 zod3로 정상이므로 타입만 우회.
    resolver: zodResolver(schema as never) as Resolver<FormValues>,
    defaultValues: { name: '', email: '', type: 'service', message: '', agree: false as never },
  });

  const onSubmit = handleSubmit(async (values) => {
    setNotice(null);
    const result = await submitInquiry({
      name: values.name,
      email: values.email,
      type: values.type,
      message: values.message,
      agree: values.agree,
    });
    // submitInquiry는 현재 { ok:false, reason:'NOT_IMPLEMENTED' } — throw하지 않고 안내만.
    if (!result.ok) {
      setNotice(t('form.notImplemented'));
    }
  });

  const labelClass = 'mb-2 block text-lg font-semibold text-bee-black';
  const errorClass = 'mt-1 text-base text-red-600';

  return (
    <form
      noValidate
      onSubmit={onSubmit}
      className="mx-auto mt-10 flex max-w-2xl flex-col gap-6 rounded-3xl border border-honey-100 bg-white p-6 shadow-sm md:p-8"
    >
      {/* 이름 */}
      <div>
        <label htmlFor={`${baseId}-name`} className={labelClass}>
          {t('form.name.label')}
        </label>
        <Input
          id={`${baseId}-name`}
          type="text"
          autoComplete="name"
          aria-invalid={errors.name ? 'true' : undefined}
          {...register('name')}
        />
        {errors.name ? (
          <p role="alert" className={errorClass}>
            {errors.name.message}
          </p>
        ) : null}
      </div>

      {/* 이메일 */}
      <div>
        <label htmlFor={`${baseId}-email`} className={labelClass}>
          {t('form.email.label')}
        </label>
        <Input
          id={`${baseId}-email`}
          type="email"
          autoComplete="email"
          aria-invalid={errors.email ? 'true' : undefined}
          {...register('email')}
        />
        {errors.email ? (
          <p role="alert" className={errorClass}>
            {errors.email.message}
          </p>
        ) : null}
      </div>

      {/* 문의 유형 */}
      <div>
        <label htmlFor={`${baseId}-type`} className={labelClass}>
          {t('form.type.label')}
        </label>
        <select
          id={`${baseId}-type`}
          className="h-12 w-full rounded-xl border border-black/20 bg-white px-4 text-lg text-bee-black focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-honey-500"
          {...register('type')}
        >
          {INQUIRY_TYPES.map((value) => (
            <option key={value} value={value}>
              {t(`form.type.options.${value}`)}
            </option>
          ))}
        </select>
      </div>

      {/* 문의 내용 */}
      <div>
        <label htmlFor={`${baseId}-message`} className={labelClass}>
          {t('form.message.label')}
        </label>
        <Textarea
          id={`${baseId}-message`}
          rows={5}
          placeholder={t('form.message.placeholder')}
          aria-invalid={errors.message ? 'true' : undefined}
          {...register('message')}
        />
        {errors.message ? (
          <p role="alert" className={errorClass}>
            {errors.message.message}
          </p>
        ) : null}
      </div>

      {/* 개인정보 동의 */}
      <div>
        <div className="flex items-start gap-3">
          <input
            id={`${baseId}-agree`}
            type="checkbox"
            className="mt-1.5 h-5 w-5 shrink-0 rounded border-black/30 text-honey-500 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-honey-500"
            aria-invalid={errors.agree ? 'true' : undefined}
            {...register('agree')}
          />
          <label htmlFor={`${baseId}-agree`} className="text-lg text-bee-black">
            {t('form.agree.label')}{' '}
            <Link
              href="/privacy"
              className="font-semibold text-honey-600 underline-offset-4 hover:underline"
            >
              {t('form.agree.link')}
            </Link>
          </label>
        </div>
        {errors.agree ? (
          <p role="alert" className={errorClass}>
            {errors.agree.message}
          </p>
        ) : null}
      </div>

      {notice ? (
        <p
          role="status"
          className="rounded-2xl bg-surface-tip px-5 py-4 text-center text-lg text-bee-black"
        >
          {notice}
        </p>
      ) : null}

      <Button type="submit" variant="primary" size="lg" disabled={isSubmitting} className={cn('w-full')}>
        {t('form.submit')}
      </Button>
    </form>
  );
}
