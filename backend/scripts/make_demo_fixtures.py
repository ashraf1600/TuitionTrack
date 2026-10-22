"""
Builds a realistic demo world and saves what the API answers, as JSON
fixtures for the mobile app's screenshot tests (mobile/test/fixtures/).

    cd backend
    DEBUG=True DATABASE_URL=sqlite:////tmp/demo.sqlite3 DB_SSL=False \
        python manage.py migrate --noinput
    DEBUG=True DATABASE_URL=sqlite:////tmp/demo.sqlite3 DB_SSL=False \
        python scripts/make_demo_fixtures.py ../mobile/test/fixtures

Every date in the fixtures is relative to `captured_at` (saved in meta.json);
the screenshot test shifts them to "now" so "Due in 3 h" stays true.
Run it against an empty, throwaway database: it creates users.
"""
import json
import os
import sys
from datetime import time, timedelta
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'config.settings')

import django  # noqa: E402

django.setup()

from django.contrib.auth import get_user_model  # noqa: E402
from django.utils import timezone  # noqa: E402
from rest_framework.test import APIClient  # noqa: E402

from apps.cycles.models import AttendanceCycle  # noqa: E402
from apps.exams.models import Exam, ExamSubmission  # noqa: E402
from apps.students.models import ConnectionRequest, Homework, StudentProfile, Tuition  # noqa: E402
from apps.students.services import enroll_student  # noqa: E402

User = get_user_model()
DAYS = ('Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday')


def local_now():
    import zoneinfo
    return timezone.now().astimezone(zoneinfo.ZoneInfo('Asia/Dhaka'))


def slot(offset_days, hour, minute=0, length=90):
    """A weekly routine slot `offset_days` from today (Dhaka time)."""
    day = (local_now() + timedelta(days=offset_days)).weekday()
    start = time(hour, minute)
    end_minutes = hour * 60 + minute + length
    return {'day': DAYS[day], 'start_time': start.strftime('%H:%M'),
            'end_time': f'{end_minutes // 60:02d}:{end_minutes % 60:02d}'}


def build():
    now = timezone.now()
    in_ = lambda **kw: now + timedelta(**kw)  # noqa: E731

    ashraf = User.objects.create_user(username='ashraf', password='Demo12345!x', role=User.Role.TUTOR,
                                      first_name='Ashraful', last_name='Islam', email='ashraf@example.com')
    nusrat = User.objects.create_user(username='nusrat', password='Demo12345!x', role=User.Role.TUTOR,
                                      first_name='Nusrat', last_name='Jahan', email='nusrat@example.com')
    tanvir = User.objects.create_user(username='tanvir', password='Demo12345!x', role=User.Role.TUTOR,
                                      first_name='Tanvir', last_name='Hasan')
    rafi = User.objects.create_user(username='rafi', password='Demo12345!x', role=User.Role.STUDENT,
                                    first_name='Rafi', last_name='Ahmed', email='rafi@example.com', tutor=ashraf)
    StudentProfile.objects.create(user=rafi, grade_level='Class 10', institution='Chittagong Collegiate School')
    classmates = []
    for first in ('Mitu', 'Sakib', 'Orpa', 'Fahim'):
        mate = User.objects.create_user(username=first.lower(), password='Demo12345!x', role=User.Role.STUDENT,
                                        first_name=first, tutor=ashraf)
        StudentProfile.objects.create(user=mate)
        classmates.append(mate)

    # Two hours from now and later this week, so "Next class" has something to say.
    now_local = local_now()
    soon_h = min(now_local.hour + 2, 21)
    physics = Tuition.objects.create(tutor=ashraf, title='SSC Physics Batch A', subject='Physics', cycle_length=12,
                                     total_fee=12000, routine=[slot(0, soon_h), slot(2, 17), slot(4, 17)])
    math = Tuition.objects.create(tutor=ashraf, title='Higher Math Weekend', subject='Higher Math', cycle_length=8,
                                  total_fee=6000, routine=[slot(1, 10), slot(5, 10)])
    chem = Tuition.objects.create(tutor=nusrat, title='Chemistry Class 10', subject='Chemistry', cycle_length=12,
                                  total_fee=9000, routine=[slot(1, 18, 30), slot(3, 18, 30)])
    for tuition in (physics, math, chem):
        enroll_student(tuition, rafi)
    for mate in classmates:
        enroll_student(physics, mate)

    topics = ['Motion', 'Velocity', 'Acceleration', 'Newton\'s laws', 'Friction', 'Work', 'Energy', 'Power',
              'Pressure', 'Density', 'Heat', 'Waves']
    def mark(tuition, numbers, when, topic):
        cycle = AttendanceCycle.ensure_active(tuition)
        for n in numbers:
            cycle.mark_class(n, True, date=when(n), topic=topic(n))
        cycle.save()
        return cycle

    mark(physics, range(1, 8), lambda n: in_(days=-(16 - n * 2)), lambda n: topics[n - 1])
    mark(math, range(1, 4), lambda n: in_(days=-(9 - n * 3)), lambda n: f'Chapter {n}')
    # Chemistry: last cycle finished and not paid yet, the new one is under way.
    finished = mark(chem, range(1, 13), lambda n: in_(days=-(40 - n * 2)), lambda n: f'Lesson {n}')
    finished.roll_over()
    mark(chem, range(1, 4), lambda n: in_(days=-(8 - n * 2)), lambda n: f'Lesson {12 + n}')

    mcq = [{'id': f'q{i}', 'question': f'Question {i}', 'options': ['A', 'B', 'C', 'D'], 'correct_answer': i % 4, 'points': 1}
           for i in range(1, 26)]
    Exam.objects.create(tutor=ashraf, tuition=physics, title='Weekly MCQ: Motion & Force', exam_type='MCQ',
                        total_marks=25, start_time=in_(minutes=-20), end_time=in_(minutes=40), duration_minutes=30,
                        mcq_data=mcq, is_published=True)
    Exam.objects.create(tutor=nusrat, tuition=chem, title='Chapter 4 Test: Periodic Table', exam_type='HYBRID',
                        total_marks=40, start_time=in_(days=1, hours=3), end_time=in_(days=1, hours=4),
                        duration_minutes=60, mcq_data=mcq[:15],
                        written_scheme=[{'id': 'w1', 'label': 'CQ 1', 'marks': 10}, {'id': 'w2', 'label': 'CQ 2', 'marks': 15}],
                        is_published=True)
    Exam.objects.create(tutor=ashraf, tuition=math, title='Assignment: Trigonometry set', category='ASSIGNMENT',
                        exam_type='CQ', total_marks=20, start_time=in_(days=-1), end_time=in_(days=2),
                        written_scheme=[{'id': 'w1', 'label': 'Set A', 'marks': 20}], is_published=True)
    graded = [
        ('Monthly Test: Kinematics', physics, ashraf, 25, 21, -6),
        ('Class Test: Acids & Bases', chem, nusrat, 20, 13, -12),
        ('Weekly MCQ: Vectors', physics, ashraf, 20, 15, -19),
        ('Class Test: Mole Concept', chem, nusrat, 20, 11, -26),
    ]
    for title, tuition, tutor, total, got, days in graded:
        exam = Exam.objects.create(tutor=tutor, tuition=tuition, title=title, exam_type='MCQ', total_marks=total,
                                   start_time=in_(days=days, hours=-1), end_time=in_(days=days), duration_minutes=30,
                                   mcq_data=mcq[:total], is_published=True, is_results_published=True,
                                   result_publish_mode='MANUAL')
        ExamSubmission.objects.create(exam=exam, student=rafi, submitted_at=in_(days=days, minutes=-10),
                                      answers_data={}, status='SUBMITTED', mcq_score=got, obtained_marks=got,
                                      is_graded=True, graded_at=in_(days=days + 1),
                                      tutor_feedback='Good work — revise the formulas once more.' if got > 15 else '')
        for i, mate in enumerate(classmates):
            ExamSubmission.objects.create(exam=exam, student=mate, submitted_at=in_(days=days, minutes=-12),
                                          answers_data={}, status='SUBMITTED', mcq_score=max(0, got - 3 + i * 2),
                                          obtained_marks=max(0, min(total, got - 3 + i * 2)), is_graded=True,
                                          graded_at=in_(days=days + 1))

    hw = [
        dict(tutor=ashraf, tuition=physics, title='Solve exercise 3.2 (all)', due_date=in_(hours=5),
             description='Write the answers in your copy and upload a photo.'),
        dict(tutor=nusrat, tuition=chem, title='Balance 10 chemical equations', due_date=in_(days=2, hours=4),
             description='From the worksheet given in class.'),
        dict(tutor=ashraf, tuition=math, title='Trigonometric identities — practice sheet', due_date=in_(days=4)),
        dict(tutor=ashraf, tuition=physics, title='Draw velocity–time graphs', due_date=in_(days=-1, hours=-2)),
        dict(tutor=nusrat, tuition=chem, title='Read chapter 3 and write a summary', due_date=in_(days=-3),
             submitted_online_url='https://drive.google.com/file/d/demo/view', submitted_at=in_(days=-3, hours=-5)),
        dict(tutor=ashraf, tuition=physics, title='Newton\'s laws — 15 short questions', due_date=in_(days=-6),
             submitted_online_url='https://drive.google.com/file/d/demo2/view', submitted_at=in_(days=-6, hours=-3),
             is_evaluated=True, evaluated_at=in_(days=-5), tutor_feedback='Excellent! Neat diagrams.'),
    ]
    for item in hw:
        Homework.objects.create(student=rafi, **item)

    ConnectionRequest.objects.create(student=rafi, tutor=tanvir, message='Assalamu alaikum Sir, I want to join your English batch.')
    return ashraf, rafi


def dump(client, path, out, name):
    resp = client.get(path)
    assert resp.status_code == 200, (path, resp.status_code, resp.content[:300])
    (out / f'{name}.json').write_text(json.dumps(resp.json(), ensure_ascii=False, indent=1))
    return resp.json()


def main(out_dir):
    out = Path(out_dir)
    student_dir = out / 'student'
    tutor_dir = out / 'tutor'
    student_dir.mkdir(parents=True, exist_ok=True)
    tutor_dir.mkdir(parents=True, exist_ok=True)
    tutor, student = build()

    client = APIClient()
    client.force_authenticate(user=student)
    for path, name in [
        ('/api/v1/auth/me/', 'me'), ('/api/v1/my-tutors/', 'my_tutors'), ('/api/v1/tuitions/', 'tuitions'),
        ('/api/v1/connections/', 'connections'), ('/api/v1/exams/', 'exams'), ('/api/v1/homework/', 'homework'),
        ('/api/v1/notifications/', 'notifications'), ('/api/v1/meta/', 'meta'), ('/api/v1/routines/', 'routines'),
        ('/api/v1/schedules/?upcoming=true', 'schedules'),
    ]:
        dump(client, path, student_dir, name)
    dump(client, f'/api/v1/my-tutors/{tutor.id}/', student_dir, 'tutor_detail')
    graded = Exam.objects.filter(title='Monthly Test: Kinematics').first()
    dump(client, f'/api/v1/exams/{graded.id}/result/', student_dir, 'exam_result')
    dump(client, f'/api/v1/exams/{graded.id}/leaderboard/', student_dir, 'leaderboard')

    client.force_authenticate(user=tutor)
    for path, name in [
        ('/api/v1/auth/me/', 'me'), ('/api/v1/tuitions/', 'tuitions'), ('/api/v1/students/', 'students'),
        ('/api/v1/exams/', 'exams'), ('/api/v1/homework/', 'homework'), ('/api/v1/connections/', 'connections'),
        ('/api/v1/analytics/wallet/', 'wallet'), ('/api/v1/notifications/', 'notifications'),
    ]:
        dump(client, path, tutor_dir, name)

    (out / 'meta.json').write_text(json.dumps({
        'captured_at': timezone.now().isoformat(),
        'student_id': str(student.id), 'tutor_id': str(tutor.id),
        'tutor_detail_id': str(tutor.id), 'result_exam_id': str(graded.id),
    }, indent=1))
    print('fixtures written to', out.resolve())


if __name__ == '__main__':
    main(sys.argv[1] if len(sys.argv) > 1 else 'fixtures')
