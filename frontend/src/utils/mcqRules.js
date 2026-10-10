/**
 * Rules a multiple-choice question must meet before it can be published.
 * Shared by the question builder and the exam form (and covered by tests).
 */

export const LETTERS = ['A', 'B', 'C', 'D', 'E'];

/** The correct option as an index, whether it was stored as 1, "1" or "B". Null when unset. */
export const correctIndex = (q) => {
  if (typeof q.correct_answer === 'number') return q.correct_answer;
  if (typeof q.correct_answer === 'string' && q.correct_answer.trim()) {
    const value = q.correct_answer.trim().toUpperCase();
    if (LETTERS.includes(value)) return LETTERS.indexOf(value);
    if (/^\d+$/.test(value)) return Number(value);
  }
  return null;
};

/** What still stops this question from being published, in the tutor's words. */
export function questionProblems(q) {
  const problems = [];
  const options = q.options || [];
  if (!String(q.question || '').trim() && !q.image_url) problems.push('Add the question text or a picture');
  if (options.filter((o) => String(o).trim()).length < 2) problems.push('Add at least two options');
  else if (options.some((o) => !String(o).trim())) problems.push('Fill in or remove the empty option');
  const correct = correctIndex(q);
  if (correct === null || correct >= options.length || !String(options[correct] ?? '').trim()) {
    problems.push('Choose the correct answer');
  }
  return problems;
}
