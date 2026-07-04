'use client';

import { zodResolver } from '@hookform/resolvers/zod';
import { Button, Card, Input } from '@helpbee/ui';
import { useRouter } from 'next/navigation';
import { useState } from 'react';
import { useForm } from 'react-hook-form';
import { z } from 'zod';

import { Banner } from '@/src/components/Banner';
import { messageForCode } from '@/src/lib/errors';

const schema = z.object({
  email: z.string().email('올바른 이메일을 입력해 주세요.'),
  password: z.string().min(1, '비밀번호를 입력해 주세요.'),
});
type FormValues = z.infer<typeof schema>;

export default function LoginPage() {
  const router = useRouter();
  const [serverError, setServerError] = useState<string | null>(null);
  const {
    register,
    handleSubmit,
    formState: { errors, isSubmitting },
  } = useForm<FormValues>({ resolver: zodResolver(schema) });

  async function onSubmit(values: FormValues) {
    setServerError(null);
    const res = await fetch('/api/session', {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify(values),
    });
    if (res.ok) {
      router.replace('/');
      router.refresh();
      return;
    }
    const body = (await res.json().catch(() => ({}))) as { code?: string };
    setServerError(messageForCode(body.code, '로그인에 실패했습니다.'));
  }

  return (
    <main className="flex min-h-screen items-center justify-center bg-honey-50 px-4">
      <Card className="w-full max-w-md space-y-6 p-8 shadow-md">
        <div className="space-y-1 text-center">
          <h1 className="font-logo text-3xl font-bold text-honey-600">HelpBee</h1>
          <p className="text-base text-bee-brown">관리자 콘솔</p>
        </div>

        {serverError && <Banner tone="error">{serverError}</Banner>}

        <form onSubmit={handleSubmit(onSubmit)} className="space-y-4" noValidate>
          <div className="space-y-1">
            <label htmlFor="email" className="text-sm font-semibold text-bee-brown">
              이메일
            </label>
            <Input id="email" type="email" autoComplete="username" {...register('email')} />
            {errors.email && <p className="text-sm text-red-600">{errors.email.message}</p>}
          </div>

          <div className="space-y-1">
            <label htmlFor="password" className="text-sm font-semibold text-bee-brown">
              비밀번호
            </label>
            <Input
              id="password"
              type="password"
              autoComplete="current-password"
              {...register('password')}
            />
            {errors.password && <p className="text-sm text-red-600">{errors.password.message}</p>}
          </div>

          <Button type="submit" className="w-full" disabled={isSubmitting}>
            {isSubmitting ? '로그인 중…' : '로그인'}
          </Button>
        </form>
      </Card>
    </main>
  );
}
