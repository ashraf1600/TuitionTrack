import { useEffect, useState } from 'react';

/**
 * The current time as a number, refreshed every `intervalMs`. Components read
 * this instead of calling Date.now() while rendering, so "due in 2 hours",
 * "today" and countdowns move on by themselves and renders stay pure.
 */
export function useNow(intervalMs = 60_000) {
  const [now, setNow] = useState(() => Date.now());
  useEffect(() => {
    const id = setInterval(() => setNow(Date.now()), intervalMs);
    return () => clearInterval(id);
  }, [intervalMs]);
  return now;
}
