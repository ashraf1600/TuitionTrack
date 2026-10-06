// Tiny toast store: call notify() from anywhere, <Toaster /> renders the stack.
// Replaces blocking browser alert() boxes.

let nextId = 1;
let toasts = [];
const listeners = new Set();

const emit = () => listeners.forEach((fn) => fn(toasts));

export function subscribe(fn) {
  listeners.add(fn);
  fn(toasts);
  return () => listeners.delete(fn);
}

export function dismiss(id) {
  toasts = toasts.filter((t) => t.id !== id);
  emit();
}

const looksLikeError = (message) => /fail|error|cannot|could not|unable|invalid|denied|not found/i.test(message);

/**
 * Show a short message. `type` is 'success' | 'error' | 'info'; when omitted it
 * is guessed from the wording so old alert() call sites keep working.
 */
export function notify(message, type) {
  const text = String(message ?? '');
  const kind = type || (looksLikeError(text) ? 'error' : 'success');
  const id = nextId++;
  toasts = [...toasts.slice(-3), { id, text, kind }];
  emit();
  setTimeout(() => dismiss(id), kind === 'error' ? 7000 : 4000);
  return id;
}

notify.success = (message) => notify(message, 'success');
notify.error = (message) => notify(message, 'error');
notify.info = (message) => notify(message, 'info');
