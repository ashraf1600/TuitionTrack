import '../core/json.dart';

/// "Ashraf" -> "Ashraf Sir". Backend already sends display_name; this guards
/// older payloads that only carry a raw first name / username.
String formatTutorName(String raw) {
  final t = raw.trim();
  if (t.isEmpty) return t;
  return t.endsWith('Sir') ? t : '$t Sir';
}

class ConnectedTutor {
  ConnectedTutor({required this.id, required this.displayName, required this.username, this.photo});
  final String id;
  final String displayName;
  final String username;
  final String? photo;

  factory ConnectedTutor.fromJson(Json j) => ConnectedTutor(
        id: j.str('id'),
        displayName: formatTutorName(j.str('display_name').isNotEmpty
            ? j.str('display_name')
            : j.str('tutor_display_name').isNotEmpty
                ? j.str('tutor_display_name')
                : j.str('username')),
        username: j.str('username'),
        photo: j.str('profile_picture').isNotEmpty
            ? j.str('profile_picture')
            : (j.str('profile_picture_url').isNotEmpty ? j.str('profile_picture_url') : null),
      );
}

class RoutineSlot {
  RoutineSlot({required this.day, required this.start, required this.end, required this.subject});
  final String day;
  final String start;
  final String end;
  final String subject;

  factory RoutineSlot.fromJson(Json j) => RoutineSlot(
        day: j.str('day_of_week').isNotEmpty ? j.str('day_of_week') : j.str('day'),
        start: j.str('start_time').isNotEmpty ? j.str('start_time') : j.str('time'),
        end: j.str('end_time'),
        subject: j.str('subject'),
      );
}

class ScheduledClass {
  ScheduledClass({required this.at, required this.topic});
  final DateTime at;
  final String topic;

  factory ScheduledClass.fromJson(Json j) {
    final dt = j.date('scheduled_at') ?? DateTime.now();
    return ScheduledClass(at: dt, topic: j.str('topic'));
  }
}

/// Strips formatting, uppercases, and validates a tutor invite code.
///
/// Returns the normalised code (4–8 uppercase alphanumerics) or `null` when the
/// input cannot possibly be a usable code. Both the [Repo.connectByCode] call
/// and the student "Connect with invite code" screen go through this single
/// helper so a 6-letter code, a code surrounded by spaces, or a mixed-case code
/// all behave the same.
String? normalizeInviteCode(String raw) {
  final cleaned = raw.trim().toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
  if (cleaned.length < 4 || cleaned.length > 8) return null;
  return cleaned;
}

class HomeworkItem {
  HomeworkItem({
    required this.id,
    required this.title,
    required this.description,
    required this.dueDate,
    required this.tutorDisplay,
    required this.submittedUrl,
    required this.feedback,
    required this.isEvaluated,
    required this.isSubmitted,
    this.sourceLabel = '',
    this.tuitionId = '',
    this.tuitionTitle = '',
    required this.studentId,
    required this.studentName,
  });
  final String id;
  final String title;
  final String description;
  final DateTime dueDate;
  final String tutorDisplay;
  final String submittedUrl;
  final String feedback;
  final bool isEvaluated;
  final bool isSubmitted;
  /// Where it came from, e.g. "Class 4 · Oct 9". Display only.
  final String sourceLabel;
  final String tuitionId;
  final String tuitionTitle;
  final String studentId;
  final String studentName;

  /// True for a group-shared row (one task, whole group) as opposed to a
  /// per-student copy that is reviewed and marked done individually.
  bool get isSharedGroupTask => tuitionId.isNotEmpty && studentId.isEmpty;

  factory HomeworkItem.fromJson(Json j) => HomeworkItem(
        id: j.str('id'),
        title: j.str('title'),
        description: j.str('description'),
        dueDate: j.date('due_date') ?? DateTime.now().add(const Duration(days: 7)),
        tutorDisplay: formatTutorName(j.str('tutor_display_name')),
        submittedUrl: j.str('submitted_online_url'),
        feedback: j.str('tutor_feedback'),
        isEvaluated: j.flag('is_evaluated'),
        isSubmitted: j.flag('is_submitted') || j.str('submitted_online_url').isNotEmpty,
        sourceLabel: j.str('source_label'),
        tuitionId: j.str('tuition_id'),
        tuitionTitle: j.str('tuition_title'),
        studentId: j.str('student_id'),
        studentName: j.str('student_name'),
      );
}
