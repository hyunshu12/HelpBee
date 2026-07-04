/** TanStack Query 키 규칙 (admin CLAUDE.md §5). */
export const queryKeys = {
  metrics: () => ['metrics'] as const,
  usersList: (params: { page: number; pageSize: number; search?: string; role?: string; status?: string }) =>
    ['users', 'list', params] as const,
  userDetail: (id: string) => ['users', 'detail', id] as const,
  auditLogs: (params: { entity?: string; action?: string }) => ['audit-logs', 'list', params] as const,
  dual: (imageId: string) => ['analyses', 'dual', imageId] as const,
};
