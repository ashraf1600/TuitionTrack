/**
 * Smart MCQ Parser Utility
 * Converts unformatted / raw text copied from ChatGPT, websites, or textbooks
 * into structured MCQ objects with 4 options, correct answer, and explanation.
 */

export function parseRawMCQText(rawText) {
  if (!rawText || !rawText.trim()) return [];

  const text = rawText.trim();
  // Split into chunks by question number indicators e.g. "1.", "2)", "Q1:", "Question 1."
  const questionBlocks = text.split(/(?=(?:^\s*(?:\d+[\.\)]|Q\s*\d+[:\.]|Question\s*\d+[:\.])))/m);

  const parsedQuestions = [];
  let idCounter = 1;
  const letterMap = { A: 0, B: 1, C: 2, D: 3 };

  for (const block of questionBlocks) {
    const trimmed = block.trim();
    if (!trimmed) continue;

    // 1. Extract Question Text
    // Remove leading number (e.g., "1.", "Q1:")
    let cleanedBlock = trimmed.replace(/^\s*(?:\d+[\.\)]|Q\s*\d+[:\.]|Question\s*\d+[:\.])\s*/i, '');

    // 2. Extract Answer and Explanation if present
    let correctAnswer = null;
    const ansMatch = cleanedBlock.match(/(?:Answer|Ans|Correct(?:\s*Answer)?)\s*[:\-–]\s*\(?([A-Da-d])\)?/i);
    if (ansMatch) {
      const letter = ansMatch[1].toUpperCase();
      if (letter in letterMap) {
        correctAnswer = letterMap[letter];
      }
    }

    let explanation = '';
    const expMatch = cleanedBlock.match(/(?:Explanation|Explain|Note|Solution)\s*[:\-–]\s*([^\n\r]+)/i);
    if (expMatch) {
      explanation = expMatch[1].trim();
    }

    // 3. Extract Options A, B, C, D
    const optionRegex = /(?:^|\s|\n)(?:\(?([A-Da-d])[\)\.]|\[([A-Da-d])\])\s*([^\n\r]+)/g;

    let match;
    const foundOptions = { A: '', B: '', C: '', D: '' };

    while ((match = optionRegex.exec(cleanedBlock)) !== null) {
      const optLetter = (match[1] || match[2]).toUpperCase();
      let optText = match[3].trim();

      // Clean off trailing answer tag if on the same line
      optText = optText.replace(/(?:Answer|Ans|Correct)\s*[:\-–].*$/i, '').trim();

      foundOptions[optLetter] = optText;
    }

    // If options were matched, determine the question prompt (everything before first option)
    let questionPrompt = cleanedBlock;
    const firstOptIndex = cleanedBlock.search(/(?:^|\s|\n)(?:\(?([A-Da-d])[\)\.]|\[([A-Da-d])\])/);
    if (firstOptIndex !== -1) {
      questionPrompt = cleanedBlock.slice(0, firstOptIndex).trim();
    }

    const optionsArray = [
      foundOptions.A || 'Option A',
      foundOptions.B || 'Option B',
      foundOptions.C || 'Option C',
      foundOptions.D || 'Option D',
    ];

    const uniqueId = `mcq-${Date.now()}-${Math.random().toString(36).substr(2, 6)}-${idCounter++}`;

    parsedQuestions.push({
      id: uniqueId,
      question: questionPrompt || `Question ${idCounter - 1}`,
      options: optionsArray,
      correct_answer: correctAnswer,
      points: 1,
      marks: 1,
      explanation: explanation || '',
    });
  }

  return parsedQuestions;
}
