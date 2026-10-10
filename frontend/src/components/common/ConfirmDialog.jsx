import React from 'react';
import { createRoot } from 'react-dom/client';
import ConfirmView from './ConfirmView';

/**
 * Professional replacement for window.confirm().
 *
 * Usage:
 *   import { confirmAction } from '../common/ConfirmDialog';
 *   if (!(await confirmAction({ title, message, confirmLabel, danger }))) return;
 *
 * Dark dialog on a dimmed backdrop — readable on both the light student
 * pages and the dark tutor console. Escape / backdrop click cancels.
 */
export function confirmAction({
  title = 'Are you sure?',
  message = '',
  confirmLabel = 'Confirm',
  cancelLabel = 'Cancel',
  danger = false,
} = {}) {
  return new Promise((resolve) => {
    const container = document.createElement('div');
    document.body.appendChild(container);
    const root = createRoot(container);

    const settle = (value) => {
      root.unmount();
      container.remove();
      resolve(value);
    };

    root.render(
      <ConfirmView
        title={title}
        message={message}
        confirmLabel={confirmLabel}
        cancelLabel={cancelLabel}
        danger={danger}
        onConfirm={() => settle(true)}
        onCancel={() => settle(false)}
      />
    );
  });
}
