import { describe, expect, it } from 'vitest';
import { dateInputToIso, toDateInputValue, toDateTimeInputValue } from '../utils/dates';

describe('date helpers', () => {
  it('formats local dates for date inputs', () => {
    expect(toDateInputValue(new Date(2026, 0, 5, 23, 59))).toBe('2026-01-05');
    expect(toDateTimeInputValue(new Date(2026, 9, 9, 7, 5))).toBe('2026-10-09T07:05');
  });

  it('falls back to today for unreadable values instead of "NaN-NaN-NaN"', () => {
    expect(toDateInputValue('not a date')).toMatch(/^\d{4}-\d{2}-\d{2}$/);
  });

  it('turns a date input into an ISO time on that local day', () => {
    const iso = dateInputToIso('2026-10-09');
    expect(toDateInputValue(new Date(iso))).toBe('2026-10-09');
  });
});
