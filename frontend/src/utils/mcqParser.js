/**
 * Smart question parser
 *
 * Turns text pasted from ChatGPT, a website or a document into structured
 * questions. It is deliberately forgiving about layout, and it never touches
 * maths: every formula ($…$, $$…$$, \(…\), \[…\]) is lifted out before any
 * pattern matching and put back untouched afterwards, so an "A)" or "1."
 * inside a formula can never be mistaken for an option or a question number.
 *
 * Understood layouts (English and Bangla):
 *   1. Question …     Q1: …     Question 1) …     ১. …     **1.** …     ### Question 1
 *   A) x   B. x   (C) x   [D] x   a) x   ক) x      — one per line or all on one line
 *   Answer: B    Ans: (b)    Correct answer: B) 20    উত্তর: খ    ✅ / (correct) / a bold option
 *   Explanation: …   Solution: …   ব্যাখ্যা: …
 *   A trailing "Answer Key: 1. B  2. C …" block
 */

const BANGLA_DIGITS = '০১২৩৪৫৬৭৮৯';
const LETTER_INDEX = {
  A: 0, B: 1, C: 2, D: 3, E: 4,
  'ক': 0, 'খ': 1, 'গ': 2, 'ঘ': 3, 'ঙ': 4,
};
const OPT = 'A-Ea-eক-ঙ';
const NUM = '[\\d০-৯]{1,3}';

const QUESTION_START = new RegExp(
  `^(?:(?:Q(?:uestion)?|প্রশ্ন)\\s*[.:#-]?\\s*(${NUM})\\s*[.):\\-–।]?|(${NUM})\\s*[.):।](?![\\d০-৯]))\\s*(.*)$`,
  'i'
);
const OPTION_START = new RegExp(`^(?:\\(([${OPT}])\\)|\\[([${OPT}])\\]|([${OPT}])\\s*[).:])\\s*(.*)$`);
const ANSWER_LINE = /^(?:the\s+)?(?:correct\s+answer|correct\s+option|right\s+answer|answer|ans|সঠিক\s*উত্তর|উত্তর)\s*(?:(?:is|হলো|হল)\s*[:=\-–]?|[:=\-–.])\s*(.+)$/i;
const TRAILING_ANSWER = new RegExp(`\\s+(?:answer|ans|উত্তর)\\s*[:=\\-–]\\s*\\(?([${OPT}])\\)?\\s*$`, 'i');
const EXPLANATION_LINE = /^(?:explanation|solution|reason|rationale|hint|ব্যাখ্যা|সমাধান)\s*[:\-–]\s*(.*)$/i;
const ANSWER_KEY_HEADER = /^(?:answer\s*key|answers|correct\s+answers|উত্তরমালা|উত্তরসমূহ)\s*[:\-–]?\s*(.*)$/i;
const KEY_ROW = new RegExp(`^(?:${NUM}\\s*[.):\\-–=]?\\s*\\(?[${OPT}]\\)?[\\s,;|]*)+$`);
const CORRECT_MARK = /\s*(?:✓|✔|✅|☑|\((?:correct|right|সঠিক)(?:\s+answer)?\)|\[(?:correct|right)\]|(?:←|<-+)\s*correct(?:\s+answer)?)\s*/gi;
const MARKS_WORD_TAG = /\s+[[(]\s*(\d+(?:\.\d+)?)\s*(?:marks?|pts?|points?|নম্বর)\s*[\])]\s*$/i;
const MARKS_BARE_TAG = /\s+\[\s*(\d+(?:\.\d+)?)\s*\]\s*$/;
const MARKS_DASH_TAG = /\s*[—–-]\s*(\d+(?:\.\d+)?)\s*(?:marks?|নম্বর)\s*$/i;

let idSeed = 0;
const newId = () => `mcq-${Date.now()}-${(idSeed += 1)}-${Math.random().toString(36).slice(2, 7)}`;

const toAsciiDigits = (value) => value.replace(/[০-৯]/g, (d) => BANGLA_DIGITS.indexOf(d));
const toNumber = (value) => Number(toAsciiDigits(value));

/** Replace every maths segment with a placeholder so structural regexes cannot see inside it. */
function maskMath(text) {
  const store = [];
  const stash = (match) => {
    store.push(match);
    return `\u0001${store.length - 1}\u0002`;
  };
  const masked = text
    .replace(/\$\$[\s\S]+?\$\$/g, stash)
    .replace(/\\\[[\s\S]+?\\\]/g, stash)
    .replace(/\\\([\s\S]+?\\\)/g, stash)
    .replace(/\$(?!\s)[^$\n]+?\$/g, stash);
  // eslint-disable-next-line no-control-regex
  const restore = (value) => value.replace(/\u0001(\d+)\u0002/g, (_, i) => store[Number(i)]);
  return { masked, restore };
}

function letterToIndex(letter) {
  if (!letter) return null;
  const key = /[a-e]/.test(letter) ? letter.toUpperCase() : letter;
  return key in LETTER_INDEX ? LETTER_INDEX[key] : null;
}

/** Strip list bullets, headings, quotes and bold markers; report whether the whole line was bold. */
function cleanLine(raw) {
  let line = raw.replace(/[ \t]/g, ' ').replace(/[​-‍﻿]/g, '').trim();
  line = line.replace(/^(?:#{1,6}\s+|>\s*)+/, '');
  line = line.replace(/^[-*•●▪◦]\s+(?=\S)/, '');
  line = line.replace(/^(\d+)\\([.)])/, '$1$2'); // markdown-escaped "1\."
  // Bold from end to end, or an option whose whole text is bold: "C) **5**".
  const bold =
    /^(\*\*|__).+\1[.:]?$/.test(line) ||
    new RegExp(`^(?:\\(?[${OPT}]\\)|\\[[${OPT}]\\]|[${OPT}]\\s*[).:])\\s*(\\*\\*|__)[^*_]+\\1$`).test(line);
  // Remove emphasis markers only; a lone * (multiplication) is left alone.
  line = line.replace(/\*\*|__/g, '').trim();
  return { line, bold };
}

const OPTION_LETTERS = [['A', 'a', 'ক'], ['B', 'b', 'খ'], ['C', 'c', 'গ'], ['D', 'd', 'ঘ'], ['E', 'e', 'ঙ']];

/**
 * Split "10  B) 20  C) 30  D) 40" (the text after a first option marker) into
 * its parts. Markers must appear in order, which keeps ordinary prose from
 * being split.
 */
function splitInlineOptions(text, firstIndex) {
  const parts = [];
  let rest = text;
  let index = firstIndex;
  for (;;) {
    const next = OPTION_LETTERS[index + 1];
    if (!next) break;
    const any = next.join('|');
    const found = new RegExp(`\\s+(?:\\((?:${any})\\)|\\[(?:${any})\\]|(?:${any})[).])\\s*`).exec(rest);
    if (!found) break;
    parts.push(rest.slice(0, found.index));
    rest = rest.slice(found.index + found[0].length);
    index += 1;
  }
  parts.push(rest);
  return parts;
}

/** A question line that carries its options inline: "What is x?  A) 1  B) 2  C) 3  D) 4". */
function splitQuestionWithInlineOptions(text) {
  const first = /\s+(?:\((?:A|a|ক)\)|\[(?:A|a|ক)\]|(?:A|ক)[).])\s*/.exec(text);
  if (!first) return null;
  const options = splitInlineOptions(text.slice(first.index + first[0].length), 0);
  if (options.length < 2) return null;
  return { question: text.slice(0, first.index), options };
}

/**
 * Parse pasted text into MCQs.
 * @returns {{questions: Array, issues: string[]}} `issues` are plain-language notes for the tutor.
 */
export function parseQuestions(rawText) {
  if (!rawText || !rawText.trim()) return { questions: [], issues: [] };

  const { masked, restore } = maskMath(rawText.replace(/\r\n?/g, '\n').replace(/```[a-z]*\n?/gi, ''));

  const drafts = [];
  const answerKey = new Map(); // question number -> option index
  let current = null;
  let section = 'none'; // question | options | answer | explanation
  let keyMode = false;
  let sawBlank = false;

  const addOption = (text, bold) => {
    let value = text;
    const trailing = TRAILING_ANSWER.exec(value);
    if (trailing) {
      current.answer = letterToIndex(trailing[1]);
      value = value.slice(0, trailing.index);
    }
    const marked = value.search(CORRECT_MARK) >= 0;
    current.options.push(value.replace(CORRECT_MARK, ' ').trim());
    if (marked) current.answer = current.options.length - 1;
    if (bold) current.boldOptions.push(current.options.length - 1);
    section = 'options';
  };

  const addQuestionText = (text) => {
    const inline = splitQuestionWithInlineOptions(text);
    if (inline) {
      if (inline.question.trim()) current.text.push(inline.question.trim());
      inline.options.forEach((opt) => addOption(opt, false));
    } else {
      current.text.push(text);
    }
  };

  const startQuestion = (number, text) => {
    current = { number, text: [], options: [], boldOptions: [], answer: null, answerText: '', explanation: [] };
    drafts.push(current);
    section = 'question';
    if (text) addQuestionText(text);
  };

  const readKeyPairs = (line) => {
    const pair = new RegExp(`(\\d{1,3})\\s*[.):\\-–=]?\\s*\\(?([${OPT}])\\)?(?![A-Za-z])`, 'g');
    const ascii = toAsciiDigits(line);
    let m;
    let found = false;
    while ((m = pair.exec(ascii)) !== null) {
      answerKey.set(Number(m[1]), letterToIndex(m[2]));
      found = true;
    }
    return found;
  };

  for (const raw of masked.split('\n')) {
    const { line, bold } = cleanLine(raw);
    if (!line || /^[-=_*]{3,}$/.test(line)) {
      sawBlank = true;
      continue;
    }

    const header = ANSWER_KEY_HEADER.exec(line);
    if (header && (!header[1] || KEY_ROW.test(header[1]))) {
      keyMode = true;
      if (header[1]) readKeyPairs(header[1]);
      continue;
    }
    if (keyMode) {
      if (readKeyPairs(line)) continue;
      keyMode = false;
    }
    // "1. B  2. C  3. A" or a lone "3. B" row, with no heading above it.
    if (drafts.length && KEY_ROW.test(line) && readKeyPairs(line)) {
      sawBlank = false;
      continue;
    }

    const answer = current && ANSWER_LINE.exec(line);
    if (answer) {
      const value = answer[1].trim();
      const letter = new RegExp(`^\\(?([${OPT}])\\)?(?:[).:\\s]|$)`).exec(value);
      if (letter) current.answer = letterToIndex(letter[1]);
      current.answerText = value;
      section = 'answer';
      sawBlank = false;
      continue;
    }

    const explanation = current && EXPLANATION_LINE.exec(line);
    if (explanation) {
      if (explanation[1]) current.explanation.push(explanation[1]);
      section = 'explanation';
      sawBlank = false;
      continue;
    }

    const question = QUESTION_START.exec(line);
    if (question) {
      startQuestion(toNumber(question[1] || question[2]), question[3].trim());
      sawBlank = false;
      continue;
    }

    const option = current && OPTION_START.exec(line);
    if (option) {
      const letter = option[1] || option[2] || option[3];
      const index = letterToIndex(letter);
      // A lower-case "a." only counts where that option is the one expected next.
      if (index === current.options.length || !/[a-e]/.test(letter)) {
        const parts = splitInlineOptions(option[4], index);
        parts.forEach((part) => addOption(part, bold && parts.length === 1));
        sawBlank = false;
        continue;
      }
    }

    // Plain text: an un-numbered question after a blank line, or a continuation.
    if (!current || (sawBlank && current.options.length >= 2 && section !== 'question')) {
      startQuestion(null, line.replace(/^(?:question|প্রশ্ন)\s*[:\-–]\s*/i, ''));
    } else if (section === 'options' && current.options.length) {
      current.options[current.options.length - 1] += ` ${line}`;
    } else if (section === 'explanation' || section === 'answer') {
      current.explanation.push(line);
    } else {
      addQuestionText(line);
    }
    sawBlank = false;
  }

  // Un-numbered text with no options is an intro or sign-off line, not a question.
  const kept = drafts.filter((d) => d.options.length > 0 || (d.number !== null && d.text.join('').trim()));

  const issues = [];
  const questions = kept.map((q, i) => {
    let questionText = q.text.join('\n').trim();
    let points = 1;
    const marks = MARKS_WORD_TAG.exec(questionText);
    if (marks) {
      points = Number(marks[1]) || 1;
      questionText = questionText.slice(0, marks.index).trim();
    }

    const options = q.options.map((o) => restore(o).trim());

    let correct = null;
    if (q.answerText) {
      // "Answer: 30" or "Answer: A catalyst" — the answer written out in full wins over a letter guess.
      const wanted = restore(q.answerText).replace(/[.\s]+$/, '').toLowerCase();
      const hit = options.findIndex((o) => o && o.toLowerCase() === wanted);
      if (hit >= 0) correct = hit;
    }
    if (correct === null && q.answer !== null) correct = q.answer;
    if (correct === null && q.number !== null && answerKey.has(q.number)) correct = answerKey.get(q.number);
    if (correct === null && q.boldOptions.length === 1) correct = q.boldOptions[0];
    if (correct !== null && correct >= options.length) correct = null;

    const label = `Question ${i + 1}`;
    if (options.length < 2) issues.push(`${label}: could not find the options — please type them in.`);
    else if (correct === null) issues.push(`${label}: no answer was given — choose the correct option.`);

    while (options.length < 4) options.push('');

    return {
      id: newId(),
      question: restore(questionText),
      options,
      correct_answer: correct,
      explanation: restore(q.explanation.join(' ')).trim(),
      points,
      marks: points,
      image_url: '',
    };
  });

  return { questions, issues };
}

/** Backwards-compatible wrapper: just the questions. */
export function parseRawMCQText(rawText) {
  return parseQuestions(rawText).questions;
}

/**
 * Parse pasted written (creative) questions: numbered questions, optionally
 * with marks such as "[10]", "(10 marks)" or "— 10 marks". Text with no
 * numbering is treated as one question. Maths is preserved exactly.
 * @returns {Array<{label: string, text: string, marks: number|null}>}
 */
export function parseWrittenQuestions(rawText) {
  if (!rawText || !rawText.trim()) return [];
  const { masked, restore } = maskMath(rawText.replace(/\r\n?/g, '\n').replace(/```[a-z]*\n?/gi, ''));

  const items = [];
  let current = null;
  for (const raw of masked.split('\n')) {
    const { line } = cleanLine(raw);
    if (!line) {
      if (current) current.lines.push('');
      continue;
    }
    const start = QUESTION_START.exec(line);
    if (start) {
      current = { number: toNumber(start[1] || start[2]), lines: [start[3]] };
      items.push(current);
    } else if (current) {
      current.lines.push(line);
    } else {
      current = { number: null, lines: [line] };
      items.push(current);
    }
  }

  return items
    .map((item, i) => {
      let text = item.lines.join('\n').replace(/\n{3,}/g, '\n\n').trim();
      let marks = null;
      const tag = MARKS_WORD_TAG.exec(text) || MARKS_BARE_TAG.exec(text) || MARKS_DASH_TAG.exec(text);
      if (tag) {
        marks = Number(tag[1]);
        text = text.slice(0, tag.index).trim();
      }
      return { label: `Q${item.number ?? i + 1}`, text: restore(text), marks };
    })
    .filter((item) => item.text);
}
