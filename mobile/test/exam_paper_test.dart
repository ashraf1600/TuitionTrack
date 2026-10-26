import 'package:flutter_test/flutter_test.dart';
import 'package:tuitiontrack/core/i18n.dart';
import 'package:tuitiontrack/screens/student/exam_take_screen.dart' show isAnswerLink;
import 'package:tuitiontrack/screens/tutor/cq_builder.dart';

void main() {
  setUp(() => setAppLanguage('en'));

  group('creative question builder', () {
    test('a new CQ has the four standard parts worth 1 + 2 + 3 + 4', () {
      final q = blankCq();
      expect(q['parts'], hasLength(4));
      expect(cqMarks(q), 10);
      expect(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$').hasMatch(q['id'] as String), isTrue);
    });

    test('Bangla papers use ক খ গ ঘ', () {
      setAppLanguage('bn');
      final q = blankCq();
      expect([for (final p in q['parts'] as List) (p as Map)['label']], ['ক', 'খ', 'গ', 'ঘ']);
    });

    test('scheme is one row per CQ, sharing its id, and the paper text keeps every part', () {
      final cq = [
        {
          'id': 'a1',
          'stem': 'A ball is dropped.',
          'image_url': '',
          'parts': [
            {'label': 'a', 'text': 'Define g.', 'marks': 1},
            {'label': 'b', 'text': 'Find v.', 'marks': 4},
          ],
        },
      ];
      expect(cqScheme(cq), [
        {'id': 'a1', 'label': 'CQ 1', 'marks': 5},
      ]);
      expect(cqTotal(cq), 5);
      final text = cqToPlainText(cq);
      expect(text, contains('1. A ball is dropped.'));
      expect(text, contains('a. Define g. [1]'));
      expect(text, contains('b. Find v. [4]'));
    });

    test('an empty part is reported before publishing', () {
      final q = blankCq()..['stem'] = 'Stem';
      final problems = cqProblems([q]);
      expect(problems, isNotEmpty);
      expect(problems.first, contains('CQ 1'));
      expect(cqProblems([]), isEmpty);
    });
  });

  group('answer link', () {
    test('only full web links are accepted', () {
      expect(isAnswerLink('https://drive.google.com/file/d/abc/view'), isTrue);
      expect(isAnswerLink('  http://example.com/sheet.pdf '), isTrue);
      expect(isAnswerLink('drive.google.com/abc'), isFalse);
      expect(isAnswerLink('javascript:alert(1)'), isFalse);
      expect(isAnswerLink('https://localhost'), isFalse);
      expect(isAnswerLink(''), isFalse);
    });
  });
}
