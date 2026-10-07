/// Smart question parser (the same rules as the website's `mcqParser.js`).
///
/// Turns text pasted from ChatGPT, a website or a document into structured
/// questions. It is forgiving about layout and never touches maths: every
/// formula (`$…$`, `$$…$$`, `\(…\)`, `\[…\]`) is lifted out before any pattern
/// matching and put back untouched afterwards, so an "A)" or "1." inside a
/// formula can never be mistaken for an option or a question number.
library;

const _banglaDigits = '০১২৩৪৫৬৭৮৯';
const _letterIndex = <String, int>{
  'A': 0, 'B': 1, 'C': 2, 'D': 3, 'E': 4,
  'ক': 0, 'খ': 1, 'গ': 2, 'ঘ': 3, 'ঙ': 4,
};
const _opt = 'A-Ea-eক-ঙ';
const _num = r'[\d০-৯]{1,3}';

final _questionStart = RegExp(
  r'^(?:(?:Q(?:uestion)?|প্রশ্ন)\s*[.:#-]?\s*(' +
      _num +
      r')\s*[.):\-–।]?|(' +
      _num +
      r')\s*[.):।](?![\d০-৯]))\s*(.*)$',
  caseSensitive: false,
);
final _optionStart = RegExp('^(?:\\(([$_opt])\\)|\\[([$_opt])\\]|([$_opt])\\s*[).:])\\s*(.*)\$');
final _answerLine = RegExp(
  r'^(?:the\s+)?(?:correct\s+answer|correct\s+option|right\s+answer|answer|ans|সঠিক\s*উত্তর|উত্তর)\s*(?:(?:is|হলো|হল)\s*[:=\-–]?|[:=\-–.])\s*(.+)$',
  caseSensitive: false,
);
final _trailingAnswer = RegExp('\\s+(?:answer|ans|উত্তর)\\s*[:=\\-–]\\s*\\(?([$_opt])\\)?\\s*\$', caseSensitive: false);
final _explanationLine = RegExp(
  r'^(?:explanation|solution|reason|rationale|hint|ব্যাখ্যা|সমাধান)\s*[:\-–]\s*(.*)$',
  caseSensitive: false,
);
final _answerKeyHeader = RegExp(
  r'^(?:answer\s*key|answers|correct\s+answers|উত্তরমালা|উত্তরসমূহ)\s*[:\-–]?\s*(.*)$',
  caseSensitive: false,
);
final _keyRow = RegExp('^(?:$_num\\s*[.):\\-–=]?\\s*\\(?[$_opt]\\)?[\\s,;|]*)+\$');
final _keyPair = RegExp('(\\d{1,3})\\s*[.):\\-–=]?\\s*\\(?([$_opt])\\)?(?![A-Za-z])');
final _correctMark = RegExp(
  r'\s*(?:✓|✔|✅|☑|\((?:correct|right|সঠিক)(?:\s+answer)?\)|\[(?:correct|right)\]|(?:←|<-+)\s*correct(?:\s+answer)?)\s*',
  caseSensitive: false,
);
final _marksWordTag = RegExp(
  r'\s+[\[(]\s*(\d+(?:\.\d+)?)\s*(?:marks?|pts?|points?|নম্বর)\s*[\])]\s*$',
  caseSensitive: false,
);
final _marksBareTag = RegExp(r'\s+\[\s*(\d+(?:\.\d+)?)\s*\]\s*$');
final _marksDashTag = RegExp(r'\s*[—–-]\s*(\d+(?:\.\d+)?)\s*(?:marks?|নম্বর)\s*$', caseSensitive: false);
final _answerLetter = RegExp('^\\(?([$_opt])\\)?(?:[).:\\s]|\$)');
final _boldLine = RegExp(r'^(\*\*|__).+\1[.:]?$');
final _boldOption = RegExp('^(?:\\(?[$_opt]\\)|\\[[$_opt]\\]|[$_opt]\\s*[).:])\\s*(\\*\\*|__)[^*_]+\\1\$');

int _idSeed = 0;
String newQuestionId() => 'mcq-${DateTime.now().microsecondsSinceEpoch}-${_idSeed++}';

String _toAsciiDigits(String value) =>
    value.replaceAllMapped(RegExp('[০-৯]'), (m) => _banglaDigits.indexOf(m[0]!).toString());

int _toNumber(String value) => int.parse(_toAsciiDigits(value));

/// Replaces every maths segment with a placeholder so structural patterns cannot see inside it.
class _Masked {
  _Masked(String text) {
    String stash(Match m) {
      _store.add(m[0]!);
      return '\u0001${_store.length - 1}\u0002';
    }

    masked = text
        .replaceAllMapped(RegExp(r'\$\$[\s\S]+?\$\$'), stash)
        .replaceAllMapped(RegExp(r'\\\[[\s\S]+?\\\]'), stash)
        .replaceAllMapped(RegExp(r'\\\([\s\S]+?\\\)'), stash)
        .replaceAllMapped(RegExp(r'\$(?!\s)[^$\n]+?\$'), stash);
  }

  final List<String> _store = [];
  late final String masked;

  String restore(String value) =>
      value.replaceAllMapped(RegExp('\u0001(\\d+)\u0002'), (m) => _store[int.parse(m[1]!)]);
}

int? _letterToIndex(String? letter) {
  if (letter == null || letter.isEmpty) return null;
  final key = RegExp('[a-e]').hasMatch(letter) ? letter.toUpperCase() : letter;
  return _letterIndex[key];
}

class _Line {
  _Line(this.text, this.bold);
  final String text;
  final bool bold;
}

/// Strips list bullets, headings, quotes and bold markers; reports whether the line was bold.
_Line _cleanLine(String raw) {
  var line = raw.replaceAll(RegExp('[ \t]'), ' ').replaceAll(RegExp('[​-‍﻿]'), '').trim();
  line = line.replaceFirst(RegExp(r'^(?:#{1,6}\s+|>\s*)+'), '');
  line = line.replaceFirst(RegExp(r'^[-*•●▪◦]\s+(?=\S)'), '');
  line = line.replaceFirstMapped(RegExp(r'^(\d+)\\([.)])'), (m) => '${m[1]}${m[2]}'); // markdown-escaped "1\."
  // Bold from end to end, or an option whose whole text is bold: "C) **5**".
  final bold = _boldLine.hasMatch(line) || _boldOption.hasMatch(line);
  // Remove emphasis markers only; a lone * (multiplication) is left alone.
  line = line.replaceAll(RegExp(r'\*\*|__'), '').trim();
  return _Line(line, bold);
}

const _optionLetters = [
  ['A', 'a', 'ক'],
  ['B', 'b', 'খ'],
  ['C', 'c', 'গ'],
  ['D', 'd', 'ঘ'],
  ['E', 'e', 'ঙ'],
];

/// Splits "10  B) 20  C) 30  D) 40" (the text after a first option marker) into
/// its parts. Markers must appear in order, which keeps ordinary prose intact.
List<String> _splitInlineOptions(String text, int firstIndex) {
  final parts = <String>[];
  var rest = text;
  var index = firstIndex;
  while (index + 1 < _optionLetters.length) {
    final any = _optionLetters[index + 1].join('|');
    final found = RegExp('\\s+(?:\\((?:$any)\\)|\\[(?:$any)\\]|(?:$any)[).])\\s*').firstMatch(rest);
    if (found == null) break;
    parts.add(rest.substring(0, found.start));
    rest = rest.substring(found.end);
    index += 1;
  }
  parts.add(rest);
  return parts;
}

final _inlineFirst = RegExp(r'\s+(?:\((?:A|a|ক)\)|\[(?:A|a|ক)\]|(?:A|ক)[).])\s*');

class _Draft {
  _Draft(this.number);
  final int? number;
  final List<String> text = [];
  final List<String> options = [];
  final List<int> boldOptions = [];
  int? answer;
  String answerText = '';
  final List<String> explanation = [];
}

class ParsedQuestions {
  ParsedQuestions(this.questions, this.issues);
  final List<Map<String, dynamic>> questions;

  /// Plain-language notes for the tutor about questions that need a check.
  final List<String> issues;
}

/// Parses pasted text into multiple-choice questions.
ParsedQuestions parseQuestions(String rawText) {
  if (rawText.trim().isEmpty) return ParsedQuestions([], []);

  final masked = _Masked(
    rawText.replaceAll(RegExp(r'\r\n?'), '\n').replaceAll(RegExp(r'```[a-z]*\n?', caseSensitive: false), ''),
  );

  final drafts = <_Draft>[];
  final answerKey = <int, int?>{};
  _Draft? current;
  var section = 'none'; // question | options | answer | explanation
  var keyMode = false;
  var sawBlank = false;

  void addOption(String text, bool bold) {
    var value = text;
    final trailing = _trailingAnswer.firstMatch(value);
    if (trailing != null) {
      current!.answer = _letterToIndex(trailing[1]);
      value = value.substring(0, trailing.start);
    }
    final marked = _correctMark.hasMatch(value);
    current!.options.add(value.replaceAll(_correctMark, ' ').trim());
    if (marked) current!.answer = current!.options.length - 1;
    if (bold) current!.boldOptions.add(current!.options.length - 1);
    section = 'options';
  }

  void addQuestionText(String text) {
    final first = _inlineFirst.firstMatch(text);
    if (first != null) {
      final options = _splitInlineOptions(text.substring(first.end), 0);
      if (options.length >= 2) {
        final question = text.substring(0, first.start).trim();
        if (question.isNotEmpty) current!.text.add(question);
        for (final option in options) {
          addOption(option, false);
        }
        return;
      }
    }
    current!.text.add(text);
  }

  void startQuestion(int? number, String text) {
    current = _Draft(number);
    drafts.add(current!);
    section = 'question';
    if (text.isNotEmpty) addQuestionText(text);
  }

  bool readKeyPairs(String line) {
    var found = false;
    for (final m in _keyPair.allMatches(_toAsciiDigits(line))) {
      answerKey[int.parse(m[1]!)] = _letterToIndex(m[2]);
      found = true;
    }
    return found;
  }

  for (final raw in masked.masked.split('\n')) {
    final cleaned = _cleanLine(raw);
    final line = cleaned.text;
    if (line.isEmpty || RegExp(r'^[-=_*]{3,}$').hasMatch(line)) {
      sawBlank = true;
      continue;
    }

    final header = _answerKeyHeader.firstMatch(line);
    if (header != null && (header[1]!.isEmpty || _keyRow.hasMatch(header[1]!))) {
      keyMode = true;
      if (header[1]!.isNotEmpty) readKeyPairs(header[1]!);
      continue;
    }
    if (keyMode) {
      if (readKeyPairs(line)) continue;
      keyMode = false;
    }
    // "1. B  2. C  3. A" or a lone "3. B" row, with no heading above it.
    if (drafts.isNotEmpty && _keyRow.hasMatch(line) && readKeyPairs(line)) {
      sawBlank = false;
      continue;
    }

    final answer = current == null ? null : _answerLine.firstMatch(line);
    if (answer != null) {
      final value = answer[1]!.trim();
      final letter = _answerLetter.firstMatch(value);
      if (letter != null) current!.answer = _letterToIndex(letter[1]);
      current!.answerText = value;
      section = 'answer';
      sawBlank = false;
      continue;
    }

    final explanation = current == null ? null : _explanationLine.firstMatch(line);
    if (explanation != null) {
      if (explanation[1]!.isNotEmpty) current!.explanation.add(explanation[1]!);
      section = 'explanation';
      sawBlank = false;
      continue;
    }

    final question = _questionStart.firstMatch(line);
    if (question != null) {
      startQuestion(_toNumber(question[1] ?? question[2]!), question[3]!.trim());
      sawBlank = false;
      continue;
    }

    final option = current == null ? null : _optionStart.firstMatch(line);
    if (option != null) {
      final letter = option[1] ?? option[2] ?? option[3]!;
      final index = _letterToIndex(letter)!;
      // A lower-case "a." only counts where that option is the one expected next.
      if (index == current!.options.length || !RegExp('[a-e]').hasMatch(letter)) {
        final parts = _splitInlineOptions(option[4]!, index);
        for (final part in parts) {
          addOption(part, cleaned.bold && parts.length == 1);
        }
        sawBlank = false;
        continue;
      }
    }

    // Plain text: an un-numbered question after a blank line, or a continuation.
    if (current == null || (sawBlank && current!.options.length >= 2 && section != 'question')) {
      startQuestion(null, line.replaceFirst(RegExp(r'^(?:question|প্রশ্ন)\s*[:\-–]\s*', caseSensitive: false), ''));
    } else if (section == 'options' && current!.options.isNotEmpty) {
      current!.options[current!.options.length - 1] += ' $line';
    } else if (section == 'explanation' || section == 'answer') {
      current!.explanation.add(line);
    } else {
      addQuestionText(line);
    }
    sawBlank = false;
  }

  // Un-numbered text with no options is an intro or sign-off line, not a question.
  final kept = drafts.where((d) => d.options.isNotEmpty || (d.number != null && d.text.join().trim().isNotEmpty)).toList();

  final issues = <String>[];
  final questions = <Map<String, dynamic>>[];
  for (var i = 0; i < kept.length; i++) {
    final q = kept[i];
    var questionText = q.text.join('\n').trim();
    num points = 1;
    final marks = _marksWordTag.firstMatch(questionText);
    if (marks != null) {
      final parsed = num.tryParse(marks[1]!) ?? 1;
      points = parsed > 0 ? parsed : 1;
      questionText = questionText.substring(0, marks.start).trim();
    }

    final options = q.options.map((o) => masked.restore(o).trim()).toList();

    int? correct;
    if (q.answerText.isNotEmpty) {
      // "Answer: 30" or "Answer: A catalyst" — the answer written out in full wins over a letter guess.
      final wanted = masked.restore(q.answerText).replaceFirst(RegExp(r'[.\s]+$'), '').toLowerCase();
      final hit = options.indexWhere((o) => o.isNotEmpty && o.toLowerCase() == wanted);
      if (hit >= 0) correct = hit;
    }
    correct ??= q.answer;
    if (correct == null && q.number != null && answerKey.containsKey(q.number)) correct = answerKey[q.number];
    if (correct == null && q.boldOptions.length == 1) correct = q.boldOptions.first;
    if (correct != null && correct >= options.length) correct = null;

    final label = 'Question ${i + 1}';
    if (options.length < 2) {
      issues.add('$label: could not find the options — please type them in.');
    } else if (correct == null) {
      issues.add('$label: no answer was given — choose the correct option.');
    }

    while (options.length < 4) {
      options.add('');
    }

    questions.add({
      'id': newQuestionId(),
      'question': masked.restore(questionText),
      'options': options,
      'correct_answer': correct,
      'explanation': masked.restore(q.explanation.join(' ')).trim(),
      'points': points,
      'marks': points,
      'image_url': '',
    });
  }

  return ParsedQuestions(questions, issues);
}

class WrittenQuestion {
  WrittenQuestion(this.label, this.text, this.marks);
  final String label;
  final String text;
  final num? marks;
}

/// Parses pasted written (creative) questions: numbered questions, optionally
/// with marks such as "[10]", "(10 marks)" or "— 10 marks". Text with no
/// numbering is treated as one question. Maths is preserved exactly.
List<WrittenQuestion> parseWrittenQuestions(String rawText) {
  if (rawText.trim().isEmpty) return [];
  final masked = _Masked(
    rawText.replaceAll(RegExp(r'\r\n?'), '\n').replaceAll(RegExp(r'```[a-z]*\n?', caseSensitive: false), ''),
  );

  final numbers = <int?>[];
  final blocks = <List<String>>[];
  for (final raw in masked.masked.split('\n')) {
    final line = _cleanLine(raw).text;
    if (line.isEmpty) {
      if (blocks.isNotEmpty) blocks.last.add('');
      continue;
    }
    final start = _questionStart.firstMatch(line);
    if (start != null) {
      numbers.add(_toNumber(start[1] ?? start[2]!));
      blocks.add([start[3]!]);
    } else if (blocks.isNotEmpty) {
      blocks.last.add(line);
    } else {
      numbers.add(null);
      blocks.add([line]);
    }
  }

  final result = <WrittenQuestion>[];
  for (var i = 0; i < blocks.length; i++) {
    var text = blocks[i].join('\n').replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
    num? marks;
    final tag = _marksWordTag.firstMatch(text) ?? _marksBareTag.firstMatch(text) ?? _marksDashTag.firstMatch(text);
    if (tag != null) {
      marks = num.tryParse(tag[1]!);
      text = text.substring(0, tag.start).trim();
    }
    if (text.isEmpty) continue;
    result.add(WrittenQuestion('Q${numbers[i] ?? i + 1}', masked.restore(text), marks));
  }
  return result;
}

/// What still stops a question from being published, in the tutor's words.
List<String> questionProblems(Map<String, dynamic> q) {
  final problems = <String>[];
  final options = ((q['options'] as List?) ?? const []).map((o) => '$o').toList();
  final hasText = '${q['question'] ?? ''}'.trim().isNotEmpty;
  final hasImage = '${q['image_url'] ?? ''}'.isNotEmpty;
  if (!hasText && !hasImage) problems.add('Add the question text or a picture');
  if (options.where((o) => o.trim().isNotEmpty).length < 2) {
    problems.add('Add at least two options');
  } else if (options.any((o) => o.trim().isEmpty)) {
    problems.add('Fill in or remove the empty option');
  }
  final correct = correctIndexOf(q);
  if (correct == null || correct >= options.length || options[correct].trim().isEmpty) {
    problems.add('Choose the correct answer');
  }
  return problems;
}

/// The correct option as an index, whatever form it was stored in (2, "2" or "C").
int? correctIndexOf(Map<String, dynamic> q) {
  final value = q['correct_answer'];
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String && value.trim().isNotEmpty) {
    final text = value.trim().toUpperCase();
    const letters = ['A', 'B', 'C', 'D', 'E'];
    if (letters.contains(text)) return letters.indexOf(text);
    return int.tryParse(text);
  }
  return null;
}
