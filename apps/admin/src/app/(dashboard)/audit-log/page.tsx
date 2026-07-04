'use client';

import { Button, Input, Skeleton, Table, TBody, Td, Th, THead, Tr } from '@helpbee/ui';
import { useInfiniteQuery } from '@tanstack/react-query';
import { useState } from 'react';

import { Banner } from '@/src/components/Banner';
import { apiFetch } from '@/src/lib/api';
import { formatKst } from '@/src/lib/format';
import { queryKeys } from '@/src/lib/query-keys';
import { useDebouncedValue } from '@/src/lib/use-debounced-value';
import type { AuditLogPage } from '@/src/lib/types';

export default function AuditLogPageView() {
  const [entityInput, setEntityInput] = useState('');
  const [actionInput, setActionInput] = useState('');
  const entity = useDebouncedValue(entityInput, 300);
  const action = useDebouncedValue(actionInput, 300);

  const { data, isLoading, isError, fetchNextPage, hasNextPage, isFetchingNextPage } =
    useInfiniteQuery({
      queryKey: queryKeys.auditLogs({ entity: entity || undefined, action: action || undefined }),
      queryFn: ({ pageParam }) =>
        apiFetch<AuditLogPage>('admin/audit-logs', {
          query: { limit: 50, cursor: pageParam as string | undefined, entity, action },
        }),
      initialPageParam: undefined as string | undefined,
      getNextPageParam: (last) => last.nextCursor ?? undefined,
    });

  const rows = data?.pages.flatMap((p) => p.items) ?? [];

  return (
    <div className="space-y-6">
      <h1 className="text-2xl font-bold text-bee-black">감사 로그</h1>

      <div className="flex flex-wrap gap-3">
        <Input
          placeholder="엔티티 (예: user)"
          value={entityInput}
          onChange={(e) => setEntityInput(e.target.value)}
          className="max-w-xs"
        />
        <Input
          placeholder="액션 (예: admin.user.status_change)"
          value={actionInput}
          onChange={(e) => setActionInput(e.target.value)}
          className="max-w-sm"
        />
      </div>

      {isError && <Banner tone="error">감사 로그를 불러오지 못했습니다.</Banner>}

      {isLoading ? (
        <Skeleton className="h-64 rounded-2xl" />
      ) : (
        <>
          <Table>
            <THead>
              <Tr>
                <Th>시각(KST)</Th>
                <Th>액션</Th>
                <Th>엔티티</Th>
                <Th>수행자</Th>
                <Th>상세</Th>
              </Tr>
            </THead>
            <TBody>
              {rows.length === 0 ? (
                <Tr>
                  <Td colSpan={5} className="py-10 text-center text-bee-brown">
                    로그가 없습니다.
                  </Td>
                </Tr>
              ) : (
                rows.map((r) => (
                  <Tr key={r.id}>
                    <Td className="whitespace-nowrap font-mono text-sm">{formatKst(r.createdAt)}</Td>
                    <Td className="font-mono text-sm">{r.action}</Td>
                    <Td className="font-mono text-sm">
                      {r.entity}
                      {r.entityId ? `/${r.entityId.slice(0, 8)}` : ''}
                    </Td>
                    <Td className="font-mono text-sm">{r.actorId ? r.actorId.slice(0, 8) : '-'}</Td>
                    <Td>
                      {r.metadata ? (
                        <details>
                          <summary className="cursor-pointer text-sm text-honey-700">보기</summary>
                          <pre className="mt-1 max-w-md overflow-x-auto whitespace-pre-wrap break-all rounded-lg bg-honey-50 p-2 text-xs">
                            {JSON.stringify(r.metadata, null, 2)}
                          </pre>
                        </details>
                      ) : (
                        <span className="text-bee-brown">-</span>
                      )}
                    </Td>
                  </Tr>
                ))
              )}
            </TBody>
          </Table>

          {hasNextPage && (
            <div className="flex justify-center">
              <Button
                variant="outline"
                onClick={() => fetchNextPage()}
                disabled={isFetchingNextPage}
              >
                {isFetchingNextPage ? '불러오는 중…' : '더 보기'}
              </Button>
            </div>
          )}
        </>
      )}
    </div>
  );
}
