import 'package:flutter_test/flutter_test.dart';
import 'package:tuitiontrack/core/mcq_parser.dart';

List<List<Object?>> brief(ParsedQuestions r) => r.questions
    .map((q) => [q['question'], (q['options'] as List).where((o) => '$o'.isNotEmpty).toList(), q['correct_answer']])
    .toList();

void main() {
  test('ChatGPT layout with \\( \\) maths, answers and explanations', () {
    final r = parseQuestions(r'''
**1. If \(P(x)=x^3-3x^2+5x-7\), then \(P(1)\) is—**

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
Answer: A
''');
    expect(brief(r), [
      [r'If \(P(x)=x^3-3x^2+5x-7\), then \(P(1)\) is—', [r'\(-4\)', r'\(-3\)', r'\(-2\)', '0'], 0],
      [r'The roots of \(x^2 - 5x + 6 = 0\) are', ['2 and 3', '1 and 6', '-2 and -3', '5 and 6'], 0],
    ]);
    expect(r.questions[0]['explanation'], r'\(P(1)=1-3+5-7=-4\).');
    expect(r.issues, isEmpty);
  });

  test('options on one line, dollar maths and an answer key at the end', () {
    final r = parseQuestions(r'''
1. What is the value of $x^2 + y^2$ when x = 3, y = 4?
A) 10  B) 20  C) 25  D) 40
2) H₂O is the formula of
(a) water (b) salt (c) sugar (d) acid
3. The SI unit of force is: A) Joule B) Newton C) Watt D) Pascal

Answer Key:
1. C
2. A
3. B
''');
    expect(brief(r), [
      [r'What is the value of $x^2 + y^2$ when x = 3, y = 4?', ['10', '20', '25', '40'], 2],
      ['H₂O is the formula of', ['water', 'salt', 'sugar', 'acid'], 0],
      ['The SI unit of force is:', ['Joule', 'Newton', 'Watt', 'Pascal'], 1],
    ]);
  });

  test('maths is never split', () {
    final r = parseQuestions(r'''
Q1: Evaluate $$\int_0^1 (A) x\,dx + B) $$ where the constant is 2. x
A) $\frac{1}{2}$
B) $1. 5$
C) \[ \sum_{i=1}^{n} i \]
D) none ✅
''');
    expect(brief(r), [
      [
        r'Evaluate $$\int_0^1 (A) x\,dx + B) $$ where the constant is 2. x',
        [r'$\frac{1}{2}$', r'$1. 5$', r'\[ \sum_{i=1}^{n} i \]', 'none'],
        3,
      ],
    ]);
  });

  test('Bangla numbering, options and answers', () {
    final r = parseQuestions('''
১. বাংলাদেশের রাজধানী কোনটি?
ক) ঢাকা
খ) খুলনা
গ) রাজশাহী
ঘ) সিলেট
উত্তর: ক

২. ২ + ২ = ?
ক) ৩ খ) ৪ গ) ৫ ঘ) ৬
উত্তর: খ
''');
    expect(brief(r), [
      ['বাংলাদেশের রাজধানী কোনটি?', ['ঢাকা', 'খুলনা', 'রাজশাহী', 'সিলেট'], 0],
      ['২ + ২ = ?', ['৩', '৪', '৫', '৬'], 1],
    ]);
  });

  test('bold answer, bullets, marks tag, missing answer', () {
    final r = parseQuestions('''
### Question 1
Which planet is known as the
Red Planet? [2 marks]
- A. Venus
- **B. Mars**
- C. Jupiter
- D. Saturn

Question 2: Water boils at
- A) 90°C
- B) 100°C
- C) 110°C
- D) 120°C
Correct answer: B) 100°C

3. No answer given here
A) one
B) two
C) three
D) four
''');
    expect(brief(r), [
      ['Which planet is known as the\nRed Planet?', ['Venus', 'Mars', 'Jupiter', 'Saturn'], 1],
      ['Water boils at', ['90°C', '100°C', '110°C', '120°C'], 1],
      ['No answer given here', ['one', 'two', 'three', 'four'], null],
    ]);
    expect(r.questions[0]['points'], 2);
    expect(r.issues, ['Question 3: no answer was given — choose the correct option.']);
  });

  test('chatter, escapes, decimals, f(2), text answer, bare key row', () {
    final r = parseQuestions(r'''Sure! Here are 3 MCQs on motion:

---

1\. A car moves at
2.5 m/s. Find the value of f(2)
A. 5
B. 10
C. 15
D. 20

2. Which one speeds up a reaction?
A) An inhibitor
B) A catalyst
C) Water
D) Salt
Answer: A catalyst

3. E = mc² was given by
A) Newton
B) Einstein (correct)
C) Bohr
D) Tesla

1-A, 2-B, 3-B

Let me know if you want more questions!''');
    expect(brief(r), [
      ['A car moves at\n2.5 m/s. Find the value of f(2)', ['5', '10', '15', '20'], 0],
      ['Which one speeds up a reaction?', ['An inhibitor', 'A catalyst', 'Water', 'Salt'], 1],
      ['E = mc² was given by', ['Newton', 'Einstein', 'Bohr', 'Tesla'], 1],
    ]);
    expect(r.questions[0]['points'], 1);
    expect(r.issues, isEmpty);
  });

  test('un-numbered questions, bold-only option, one-line question', () {
    var r = parseQuestions('''
What is 5 × 6?
A) 11
B) 30
C) 56
D) 65
Answer: 30

Which is a prime number?
A) 4
B) 6
C) 7
D) 9
Ans: (c)
''');
    expect(brief(r), [
      ['What is 5 × 6?', ['11', '30', '56', '65'], 1],
      ['Which is a prime number?', ['4', '6', '7', '9'], 2],
    ]);

    r = parseQuestions('1. Pick\nA) 3\nB) 4\nC) **5**\nD) 6\n\n2. All bold\nA) **x**\nB) **y**');
    expect(r.questions.map((q) => q['correct_answer']).toList(), [2, null]);

    r = parseQuestions(r'1) Simplify \(\frac{x^2-1}{x-1}\)   A) \(x+1\)   B) \(x-1\)   C) \(x\)   D) 1   Answer: A');
    expect(brief(r), [
      [r'Simplify \(\frac{x^2-1}{x-1}\)', [r'\(x+1\)', r'\(x-1\)', r'\(x\)', '1'], 0],
    ]);
  });

  test('twenty questions stay twenty', () {
    final text = List.generate(
      20,
      (i) => '${i + 1}. Question number ${i + 1} about \$a_$i^2\$?\nA) w$i\nB) x$i\nC) y$i\nD) z$i\nAnswer: ${'ABCD'[i % 4]}\n',
    ).join('\n');
    final r = parseQuestions(text);
    expect(r.questions.length, 20);
    expect(r.questions[19]['correct_answer'], 3);
    expect(r.questions[19]['question'], r'Question number 20 about $a_19^2$?');
    expect(r.issues, isEmpty);
    expect(parseQuestions('   ').questions, isEmpty);
  });

  test('written questions', () {
    final w = parseWrittenQuestions(r'''
1. A particle moves with velocity \(v(t) = 3t^2 - 4t\).
   (a) Find the acceleration at t = 2 s.
   (b) Find the displacement in the first 3 s. [10]

2. Evaluate $$\int_0^\pi \sin^2 x\,dx$$ (5 marks)
''');
    expect(w.map((q) => [q.label, q.text, q.marks]).toList(), [
      ['Q1', 'A particle moves with velocity \\(v(t) = 3t^2 - 4t\\).\n(a) Find the acceleration at t = 2 s.\n(b) Find the displacement in the first 3 s.', 10],
      ['Q2', r'Evaluate $$\int_0^\pi \sin^2 x\,dx$$', 5],
    ]);
    final single = parseWrittenQuestions(r'Prove that $\sqrt{2}$ is irrational.');
    expect(single.single.label, 'Q1');
    expect(single.single.marks, isNull);
  });

  test('question problems', () {
    expect(questionProblems({'question': 'q', 'options': ['a', 'b'], 'correct_answer': 0}), isEmpty);
    expect(questionProblems({'question': '', 'image_url': '/media/x.png', 'options': ['a', 'b'], 'correct_answer': 'B'}), isEmpty);
    expect(questionProblems({'question': '', 'options': ['a', ''], 'correct_answer': null}),
        ['Add the question text or a picture', 'Add at least two options', 'Choose the correct answer']);
    expect(questionProblems({'question': 'q', 'options': ['a', 'b', ''], 'correct_answer': 2}),
        ['Fill in or remove the empty option', 'Choose the correct answer']);
  });
}
