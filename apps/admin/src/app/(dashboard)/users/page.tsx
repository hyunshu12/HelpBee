'use client';

import { Badge, Input, Skeleton } from '@helpbee/ui';
import { keepPreviousData, useQuery } from '@tanstack/react-query';
import { type ColumnDef } from '@tanstack/react-table';
import { useRouter } from 'next/navigation';
import { useMemo, useState } from 'react';

import { Banner } from '@/src/components/Banner';
import { Select } from '@/src/components/Select';
import { DataTable } from '@/src/components/tables/DataTable';
import { apiFetchList } from '@/src/lib/api';
import { formatKst, label, ROLE_LABEL, STATUS_LABEL } from '@/src/lib/format';
import { queryKeys } from '@/src/lib/query-keys';
import { useDebouncedValue } from '@/src/lib/use-debounced-value';
import type { AdminUserRow } from '@/src/lib/types';

const PAGE_SIZE = 20;

export default function UsersPage() {
  const router = useRouter();
  const [page, setPage] = useState(1);
  const [searchInput, setSearchInput] = useState('');
  const [role, setRole] = useState('');
  const [status, setStatus] = useState('');
  const search = useDebouncedValue(searchInput, 300);

  const params = { page, pageSize: PAGE_SIZE, search: search || undefined, role: role || undefined, status: status || undefined };

  const { data, isLoading, isError } = useQuery({
    queryKey: queryKeys.usersList(params),
    queryFn: () =>
      apiFetchList<AdminUserRow>('admin/users', {
        query: { page, pageSize: PAGE_SIZE, search, role, status },
      }),
    placeholderData: keepPreviousData,
  });

  const columns = useMemo<ColumnDef<AdminUserRow, unknown>[]>(
    () => [
      { header: '이메일', accessorKey: 'email' },
      { header: '이름', accessorKey: 'name' },
      {
        header: '권한',
        accessorKey: 'role',
        cell: ({ row }) => label(ROLE_LABEL, row.original.role),
      },
      {
        header: '상태',
        accessorKey: 'status',
        cell: ({ row }) => {
          const s = row.original.status;
          return (
            <Badge variant={s === 'active' ? 'soft' : 'solid'}>{label(STATUS_LABEL, s)}</Badge>
          );
        },
      },
      {
        header: '가입일',
        accessorKey: 'createdAt',
        cell: ({ row }) => formatKst(row.original.createdAt),
      },
    ],
    [],
  );

  function resetPageAnd(setter: (v: string) => void) {
    return (v: string) => {
      setter(v);
      setPage(1);
    };
  }

  return (
    <div className="space-y-6">
      <h1 className="text-2xl font-bold text-bee-black">사용자</h1>

      <div className="flex flex-wrap gap-3">
        <Input
          placeholder="이메일 · 이름 검색"
          value={searchInput}
          onChange={(e) => {
            setSearchInput(e.target.value);
            setPage(1);
          }}
          className="max-w-xs"
        />
        <Select value={role} onChange={(e) => resetPageAnd(setRole)(e.target.value)}>
          <option value="">권한 전체</option>
          <option value="user">일반</option>
          <option value="admin">관리자</option>
        </Select>
        <Select value={status} onChange={(e) => resetPageAnd(setStatus)(e.target.value)}>
          <option value="">상태 전체</option>
          <option value="active">정상</option>
          <option value="blocked">차단</option>
          <option value="deleted">탈퇴</option>
        </Select>
      </div>

      {isError && <Banner tone="error">사용자 목록을 불러오지 못했습니다.</Banner>}

      {isLoading && !data ? (
        <Skeleton className="h-64 rounded-2xl" />
      ) : (
        <DataTable
          columns={columns}
          data={data?.items ?? []}
          page={page}
          pageSize={PAGE_SIZE}
          total={data?.total ?? 0}
          onPageChange={setPage}
          onRowClick={(u) => router.push(`/users/${u.id}`)}
          emptyMessage="조건에 맞는 사용자가 없습니다."
        />
      )}
    </div>
  );
}
