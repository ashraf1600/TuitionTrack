// Date helpers that work in the user's own timezone.
// (`toISOString().slice(0, 10)` gives the UTC date, which is yesterday for the
// first hours of the day in Bangladesh.)

const pad = (n) => String(n).padStart(2, '0');

/** A Date (or ISO string) as a local `YYYY-MM-DD`, for <input type="date">. */
export function toDateInputValue(value = new Date()) {
  const d = value instanceof Date ? value : new Date(value);
  if (Number.isNaN(d.getTime())) return toDateInputValue(new Date());
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
}

/** A `YYYY-MM-DD` picked by the user as an ISO timestamp at local noon, so it shows as the same day everywhere nearby. */
export function dateInputToIso(dateStr) {
  if (!dateStr) return new Date().toISOString();
  const d = new Date(`${dateStr}T12:00:00`);
  return Number.isNaN(d.getTime()) ? new Date().toISOString() : d.toISOString();
}

export function formatShortDate(value) {
  if (!value) return '';
  const d = new Date(value);
  if (Number.isNaN(d.getTime())) return '';
  return d.toLocaleDateString(undefined, { month: 'short', day: 'numeric' });
}

export function formatLongDate(value) {
  if (!value) return '';
  const d = new Date(value);
  if (Number.isNaN(d.getTime())) return '';
  return d.toLocaleDateString(undefined, { weekday: 'short', day: 'numeric', month: 'short', year: 'numeric' });
}

export const formatTaka = (amount) => `৳${Number(amount || 0).toLocaleString(undefined, { maximumFractionDigits: 2 })}`;
