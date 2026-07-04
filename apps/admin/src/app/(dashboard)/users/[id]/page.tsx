'use client';

import { Badge, Button, Card, Skeleton } from '@helpbee/ui';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import Link from 'next/link';
import { useParams } from 'next/navigation';
import { useState } from 'react';

import { Banner } from '@/src/components/Banner';
import { ConfirmAction } from '@/src/components/ConfirmAction';
import { apiFetch, apiFetchList } from '@/src/lib/api';
import { ApiError } from '@/src/lib/errors';
import { formatKst, label, PLAN_LABEL, ROLE_LABEL, STATUS_LABEL } from '@/src/lib/format';
import { queryKeys } from '@/src/lib/query-keys';
import type { AdminUserDetail, AdminUserRow } from '@/src/lib/types';

/**
 * ⚠️ GET /v1/admin/users/:id 엔드포인트가 없다(백엔드에 미구현).
 * MVP 우회: 사용자 목록(pageSize=100)에서 id로 찾아 표시. PATCH 응답은 전체 detail을 주므로
 * 액션 후에는 정확한 최신 상태로 갱신된다. (CLAUDE.md Decision Log / follow-up: 백엔드에 상세 라우트 추가)
 */
async function fetchUserById(id: string): Promise<AdminUserRow | undefined> {
  const { items } = await apiFetchList<AdminUserRow>('admin/users', {
    query: { page: 1, pageSize: 100 },
  });
  return items.find((u) => u.id === id);
}

type BannerState = { tone: 'success' | 'error'; text: string } | null;

export default function UserDetailPage() {
  const params = useParams<{ id: string }>();
  const id = params.id;
  const qc = useQueryClient();
  const [banner, setBanner] = useState<BannerState>(null);
  // PATCH가 반환한 최신 detail을 우선 표시(있으면).
  const [detail, setDetail] = useState<AdminUserDetail | null>(null);

  const { data: row, isLoading, isError } = useQuery({
    queryKey: queryKeys.userDetail(id),
    queryFn: () => fetchUserById(id),
  });

  const patch = useMutation({
    mutationFn: (body: { role?: 'user' | 'admin'; status?: 'active' | 'blocked' }) =>
      apiFetch<AdminUserDetail>(`admin/users/${id}`, { method: 'PATCH', body }),
    onSuccess: (updated, vars) => {
      setDetail(updated);
      setBanner({ tone: 'success', text: actionMessage(vars) });
      qc.invalidateQueries({ queryKey: ['users', 'list'] });
    },
    onError: (err) => {
      setBanner({ tone: 'error', text: err instanceof ApiError ? err.message : '작업에 실패했습니다.' });
    },
  });

  const view: AdminUserRow | AdminUserDetail | undefined = detail ?? row;

  if (isLoading) return <Skeleton className="h-72 rounded-2xl" />;
  if (isError || !view) {
    return (
      <div className="space-y-4">
        <BackLink />
        <Banner tone="error">사용자를 찾을 수 없습니다. (목록에서 다시 선택해 주세요)</Banner>
      </div>
    );
  }

  const isBlocked = view.status === 'blocked';
  const isAdmin = view.role === 'admin';
  const isDeleted = view.status === 'deleted';

  return (
    <div className="space-y-6">
      <BackLink />
      <div className="flex items-center gap-3">
        <h1 className="text-2xl font-bold text-bee-black">{view.name}</h1>
        <Badge variant={view.status === 'active' ? 'soft' : 'solid'}>
          {label(STATUS_LABEL, view.status)}
        </Badge>
      </div>

      {banner && <Banner tone={banner.tone}>{banner.text}</Banner>}

      <Card className="grid grid-cols-1 gap-4 p-6 shadow-sm sm:grid-cols-2">
        <Field label="이메일" value={view.email} />
        <Field label="권한" value={label(ROLE_LABEL, view.role)} />
        <Field label="플랜" value={label(PLAN_LABEL, view.plan ?? undefined)} />
        <Field
          label="이메일 인증"
          value={view.emailVerifiedAt ? formatKst(view.emailVerifiedAt) : '미인증'}
        />
        <Field label="가입일" value={formatKst(view.createdAt)} />
        {detail && <Field label="분석 횟수" value={String(detail.analysisCount)} />}
      </Card>

      <Card className="space-y-3 p-6 shadow-sm">
        <h2 className="text-base font-semibold text-bee-black">계정 관리</h2>
        {isDeleted ? (
          <p className="text-base text-bee-brown">탈퇴한 사용자입니다.</p>
        ) : (
          <div className="flex flex-wrap items-center gap-3">
            {isBlocked ? (
              <ConfirmAction
                label="차단 해제"
                onConfirm={() => patch.mutate({ status: 'active' })}
                disabled={patch.isPending}
              />
            ) : (
              <ConfirmAction
                label="차단"
                variant="outline"
                onConfirm={() => patch.mutate({ status: 'blocked' })}
                disabled={patch.isPending}
              />
            )}
            {isAdmin ? (
              <ConfirmAction
                label="관리자 강등"
                variant="outline"
                onConfirm={() => patch.mutate({ role: 'user' })}
                disabled={patch.isPending}
              />
            ) : (
              <ConfirmAction
                label="관리자 승격"
                variant="outline"
                onConfirm={() => patch.mutate({ role: 'admin' })}
                disabled={patch.isPending}
              />
            )}
          </div>
        )}
      </Card>
    </div>
  );
}

function actionMessage(v: { role?: string; status?: string }): string {
  if (v.status === 'blocked') return '사용자를 차단했습니다.';
  if (v.status === 'active') return '차단을 해제했습니다.';
  if (v.role === 'admin') return '관리자로 승격했습니다.';
  if (v.role === 'user') return '관리자에서 강등했습니다.';
  return '변경되었습니다.';
}

function Field({ label: l, value }: { label: string; value: string }) {
  return (
    <div>
      <dt className="text-sm text-bee-brown">{l}</dt>
      <dd className="text-base text-bee-black">{value}</dd>
    </div>
  );
}

function BackLink() {
  return (
    <Link href="/users">
      <Button variant="ghost" size="sm">
        ← 사용자 목록
      </Button>
    </Link>
  );
}
