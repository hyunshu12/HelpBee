'use client';

import { Button } from '@helpbee/ui';
import { useState } from 'react';

/**
 * 2단계 인라인 확인 (packages/ui에 Dialog 없음 — MVP). 클릭 → "정말?" [확인][취소].
 */
export function ConfirmAction({
  label,
  confirmLabel = '확인',
  onConfirm,
  disabled,
  variant = 'primary',
}: {
  label: string;
  confirmLabel?: string;
  onConfirm: () => void;
  disabled?: boolean;
  variant?: 'primary' | 'outline';
}) {
  const [armed, setArmed] = useState(false);

  if (!armed) {
    return (
      <Button variant={variant} size="sm" disabled={disabled} onClick={() => setArmed(true)}>
        {label}
      </Button>
    );
  }

  return (
    <span className="inline-flex items-center gap-2">
      <span className="text-sm text-bee-brown">정말 진행할까요?</span>
      <Button
        variant="primary"
        size="sm"
        disabled={disabled}
        onClick={() => {
          setArmed(false);
          onConfirm();
        }}
      >
        {confirmLabel}
      </Button>
      <Button variant="ghost" size="sm" onClick={() => setArmed(false)}>
        취소
      </Button>
    </span>
  );
}
