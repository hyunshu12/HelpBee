import { render, screen } from '@testing-library/react';
import { describe, expect, it } from 'vitest';
import { Table, TBody, Td, Th, THead, Tr } from './Table';

describe('Table', () => {
  it('renders header and body cells with token styling', () => {
    render(
      <Table>
        <THead>
          <Tr>
            <Th>이메일</Th>
          </Tr>
        </THead>
        <TBody>
          <Tr>
            <Td>test@helpbee.io</Td>
          </Tr>
        </TBody>
      </Table>,
    );
    const head = screen.getByText('이메일');
    expect(head.tagName).toBe('TH');
    expect(head.className).toContain('text-bee-brown');
    expect(screen.getByText('test@helpbee.io').tagName).toBe('TD');
  });
});
