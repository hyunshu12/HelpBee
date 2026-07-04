'use client';

import { Button, Table, TBody, Td, Th, THead, Tr } from '@helpbee/ui';
import {
  flexRender,
  getCoreRowModel,
  useReactTable,
  type ColumnDef,
} from '@tanstack/react-table';

/**
 * TanStack Table v8 얇은 래퍼. 서버사이드 페이지네이션(page/pageSize는 상위 useQuery 키가 소유).
 * 정렬/필터는 서버가 담당하므로 여기선 렌더 + 페이지 이동 컨트롤만.
 */
export interface DataTableProps<TData> {
  columns: ColumnDef<TData, unknown>[];
  data: TData[];
  page: number;
  pageSize: number;
  total: number;
  onPageChange: (page: number) => void;
  onRowClick?: (row: TData) => void;
  emptyMessage?: string;
}

export function DataTable<TData>({
  columns,
  data,
  page,
  pageSize,
  total,
  onPageChange,
  onRowClick,
  emptyMessage = '데이터가 없습니다.',
}: DataTableProps<TData>) {
  const table = useReactTable({ data, columns, getCoreRowModel: getCoreRowModel() });
  const pageCount = Math.max(1, Math.ceil(total / pageSize));

  return (
    <div className="space-y-4">
      <Table>
        <THead>
          {table.getHeaderGroups().map((hg) => (
            <Tr key={hg.id}>
              {hg.headers.map((h) => (
                <Th key={h.id}>
                  {h.isPlaceholder ? null : flexRender(h.column.columnDef.header, h.getContext())}
                </Th>
              ))}
            </Tr>
          ))}
        </THead>
        <TBody>
          {table.getRowModel().rows.length === 0 ? (
            <Tr>
              <Td colSpan={columns.length} className="py-10 text-center text-bee-brown">
                {emptyMessage}
              </Td>
            </Tr>
          ) : (
            table.getRowModel().rows.map((row) => (
              <Tr
                key={row.id}
                className={onRowClick ? 'cursor-pointer' : undefined}
                onClick={onRowClick ? () => onRowClick(row.original) : undefined}
              >
                {row.getVisibleCells().map((cell) => (
                  <Td key={cell.id}>{flexRender(cell.column.columnDef.cell, cell.getContext())}</Td>
                ))}
              </Tr>
            ))
          )}
        </TBody>
      </Table>

      <div className="flex items-center justify-between text-base text-bee-brown">
        <span>
          전체 {total}건 · {page}/{pageCount} 페이지
        </span>
        <div className="flex gap-2">
          <Button
            variant="outline"
            size="sm"
            disabled={page <= 1}
            onClick={() => onPageChange(page - 1)}
          >
            이전
          </Button>
          <Button
            variant="outline"
            size="sm"
            disabled={page >= pageCount}
            onClick={() => onPageChange(page + 1)}
          >
            다음
          </Button>
        </div>
      </div>
    </div>
  );
}
