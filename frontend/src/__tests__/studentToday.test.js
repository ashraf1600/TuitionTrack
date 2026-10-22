import { describe, expect, it } from 'vitest';
import { nextClass, sirName } from '../components/student/StudentToday';
import { shortGap } from '../components/common/DeadlineChip';

describe('student Today helpers', () => {
  it('names the tutor as "X Sir", never the tuition', () => {
    expect(sirName({ tutor_display_name: 'Ashraf Sir', title: 'Physics Batch A' })).toBe('Ashraf Sir');
    expect(sirName({ tutor_name: 'Ashraf Islam' })).toBe('Ashraf Sir');
    expect(sirName({})).toBe('');
  });

  it('finds the next class in the weekly routine', () => {
    // Thursday 22 Oct 2026, 10:00 local time
    const now = new Date(2026, 9, 22, 10, 0);
    const tuitions = [
      { id: 'a', routine: [{ day: 'Thursday', start_time: '09:00' }, { day: 'Friday', start_time: '17:00' }] },
      { id: 'b', routine: [{ day: 'Thursday', start_time: '18:30' }] },
    ];
    const next = nextClass(tuitions, now);
    expect(next.tuition.id).toBe('b');
    expect(next.at.getHours()).toBe(18);
    expect(next.at.getDate()).toBe(22);
  });

  it('short gaps for chips', () => {
    expect(shortGap(20 * 1000)).toBe('<1 min');
    expect(shortGap(25 * 60000)).toBe('25 min');
    expect(shortGap(3 * 3600000 + 600000)).toBe('3 h');
    expect(shortGap(3 * 86400000)).toBe('3 d');
  });
});
