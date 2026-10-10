import { describe, expect, it } from 'vitest';
import { parseQuestions, parseWrittenQuestions } from '../utils/mcqParser';
import { correctIndex, questionProblems } from '../utils/mcqRules';

const brief = (result) => result.questions.map((q) => [q.question, q.options.filter(Boolean), q.correct_answer]);

describe('parseQuestions', () => {
  it('reads ChatGPT-style questions with maths, answers and explanations', () => {
    const result = parseQuestions(String.raw`**1. If \(P(x)=x^3-3x^2+5x-7\), then \(P(1)\) is—**

A) \(-4\)
B) \(-3\)
C) \(-2\)
D) 0

**Answer:** A
**Explanation:** \(P(1)=1-3+5-7=-4\).

**2. The roots of \(x^2 - 5x + 6 = 0\) are**
A. 2 and 3
B. 1 and 6
C. -2 and -3
D. 5 and 6
Answer: A`);
    expect(brief(result)).toEqual([
      [String.raw`If \(P(x)=x^3-3x^2+5x-7\), then \(P(1)\) is—`, [String.raw`\(-4\)`, String.raw`\(-3\)`, String.raw`\(-2\)`, '0'], 0],
      [String.raw`The roots of \(x^2 - 5x + 6 = 0\) are`, ['2 and 3', '1 and 6', '-2 and -3', '5 and 6'], 0],
    ]);
    expect(result.questions[0].explanation).toBe(String.raw`\(P(1)=1-3+5-7=-4\).`);
    expect(result.issues).toEqual([]);
  });

  it('reads options on one line and an answer key at the end', () => {
    const result = parseQuestions(`1. What is the value of $x^2 + y^2$ when x = 3, y = 4?
A) 10  B) 20  C) 25  D) 40
2) H₂O is the formula of
(a) water (b) salt (c) sugar (d) acid

Answer Key:
1. C
2. A`);
    expect(brief(result)).toEqual([
      ['What is the value of $x^2 + y^2$ when x = 3, y = 4?', ['10', '20', '25', '40'], 2],
      ['H₂O is the formula of', ['water', 'salt', 'sugar', 'acid'], 0],
    ]);
  });

  it('returns nothing for empty input', () => {
    expect(parseQuestions('   ')).toEqual({ questions: [], issues: [] });
  });
});

describe('parseWrittenQuestions', () => {
  it('splits numbered questions and reads their marks', () => {
    const items = parseWrittenQuestions('1. Define force. [5]\n2. State Newton\'s laws (10 marks)');
    expect(items.map((i) => [i.label, i.marks])).toEqual([['Q1', 5], ['Q2', 10]]);
  });
});

describe('MCQ publishing rules', () => {
  it('accepts the answer as an index, a digit string or a letter', () => {
    expect(correctIndex({ correct_answer: 2 })).toBe(2);
    expect(correctIndex({ correct_answer: '1' })).toBe(1);
    expect(correctIndex({ correct_answer: 'b' })).toBe(1);
    expect(correctIndex({ correct_answer: '' })).toBeNull();
  });

  it('lists what still blocks a question', () => {
    expect(questionProblems({ question: 'Q', options: ['a', 'b'], correct_answer: 0 })).toEqual([]);
    expect(questionProblems({ question: '', options: ['a', ''], correct_answer: null })).toEqual([
      'Add the question text or a picture',
      'Add at least two options',
      'Choose the correct answer',
    ]);
    expect(questionProblems({ question: 'Q', options: ['a', 'b'], correct_answer: 3 })).toEqual(['Choose the correct answer']);
  });
});
