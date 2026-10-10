// Offline tests for the app <-> API contract changed in the audit branch:
// homework personal copies / file submissions and how a typed server address
// is turned into a URL.
import 'package:flutter_test/flutter_test.dart';

import 'package:tuitiontrack/core/api.dart';
import 'package:tuitiontrack/core/connect.dart';

void main() {
  group('HomeworkItem.fromJson', () {
    test('reads the submitted file and counts it as submitted', () {
      final hw = HomeworkItem.fromJson({
        'id': 'copy-1',
        'title': 'Chapter 1',
        'due_date': '2030-01-01T10:00:00Z',
        'student_id': 'stu-1',
        'student_name': 'Rafi',
        'tuition_id': null,
        'group_source_id': 'group-1',
        'submitted_online_url': '',
        'submission_file_url': 'https://api.example.com/media/homework/2030/01/a.pdf',
        'is_submitted': false,
        'is_evaluated': false,
      });
      expect(hw.submissionFileUrl, 'https://api.example.com/media/homework/2030/01/a.pdf');
      expect(hw.isSubmitted, isTrue);
      expect(hw.isSharedGroupTask, isFalse);
    });

    test('a group task has a tuition and no student', () {
      final hw = HomeworkItem.fromJson({
        'id': 'group-1',
        'title': 'Chapter 1',
        'due_date': '2030-01-01T10:00:00Z',
        'tuition_id': 'tuition-1',
        'student_id': null,
        'is_group': true,
      });
      expect(hw.isSharedGroupTask, isTrue);
      expect(hw.submissionFileUrl, '');
    });
  });

  group('server address', () {
    ApiClient client(String url) => ApiClient(baseUrl: url, tokens: MemoryTokenStore());

    test('a bare host name gets https', () {
      expect(client('tuitiontrack-api.onrender.com').baseUrl, 'https://tuitiontrack-api.onrender.com');
    });

    test('this computer or the local network gets http', () {
      expect(client('192.168.0.10:8000').baseUrl, 'http://192.168.0.10:8000');
      expect(client('10.0.2.2:8000/').baseUrl, 'http://10.0.2.2:8000');
      expect(client('localhost:8000').baseUrl, 'http://localhost:8000');
    });

    test('an explicit scheme is kept and trailing slashes dropped', () {
      expect(client('http://example.com//').baseUrl, 'http://example.com');
      expect(client(' https://example.com/ ').baseUrl, 'https://example.com');
    });
  });
}
