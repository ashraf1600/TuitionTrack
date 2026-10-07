"""
API robustness sweep.

Walks every route under /api/v1/ with every kind of caller (signed out, the
owning tutor, another tutor, an enrolled student, an outsider student) and a
range of well-formed and malformed requests. Whatever a client sends, the API
must answer with a deliberate status code — never a 500 — and must not let a
signed-out caller into a protected route.
"""
import json
import re
from datetime import timedelta
from unittest import mock

from django.contrib.auth import get_user_model
from django.db import transaction
from django.urls import get_resolver
from django.utils import timezone
from rest_framework.test import APITestCase

from apps.cycles.models import AttendanceCycle, Cycle
from apps.exams.models import Exam, ExamSubmission
from apps.students.models import ConnectionRequest, StudentProfile, Tuition
from apps.students.services import enroll_student

User = get_user_model()

PUBLIC_ROUTES = (
    'auth/token/', 'auth/token/refresh/', 'auth/logout/', 'auth/register/', 'auth/register/student/',
    'auth/tutors/', 'auth/password-reset/', 'auth/password-reset/confirm/', 'meta/',
)

# Every body key the API reads anywhere, so each malformed value reaches real code.
KNOWN_KEYS = [
    'username', 'password', 'password_confirm', 'first_name', 'last_name', 'email', 'phone', 'identifier',
    'uid', 'token', 'refresh', 'new_password', 'current_password', 'grade_level', 'institution', 'address',
    'parent_name', 'parent_phone', 'message', 'selected_tutor_id', 'tutor_id', 'tutor_username', 'profile',
    'title', 'subject', 'description', 'cycle_length', 'total_fee', 'tuition_fee', 'routine', 'student_ids',
    'student_id', 'tuition_id', 'batch_id', 'class_no', 'classNo', 'completed', 'date', 'topic', 'notes',
    'category', 'exam_type', 'content_html', 'mcq_data', 'written_scheme', 'solution_html', 'solution_media_url',
    'total_marks', 'start_time', 'end_time', 'duration_minutes', 'grace_period_minutes', 'late_submission_until',
    'shuffle_questions', 'negative_marks_per_wrong', 'is_published', 'is_results_published', 'result_publish_mode',
    'publish_time', 'answers_data', 'text_answer', 'uploaded_images', 'image_urls', 'obtained_marks', 'cq_score',
    'cq_breakdown', 'tutor_feedback', 'publish', 'is_active', 'file',
]
BAD_VALUES = [None, '', 'x', -1, 10 ** 30, 1.5, True, [], {}, [[]], [None], {'a': {'b': []}}, 'NaN', '\x00', 'ক' * 3000,
              '2026-99-99T99:99', '00000000-0000-0000-0000-000000000000', '<script>alert(1)</script>']
BAD_QUERIES = [
    '', '?page=abc', '?page=999999', '?page_size=-1', '?page_size=abc', '?student_id=nope', '?tuition_id=nope',
    '?batch_id=nope', '?status=nope', '?search=%00%27%22', '?student_id=00000000-0000-0000-0000-000000000000',
]


def api_routes():
    """(route template, parameter names) for every pattern under api/v1/."""
    found = []

    def walk(patterns, prefix):
        for entry in patterns:
            route = prefix + str(entry.pattern)
            if hasattr(entry, 'url_patterns'):
                walk(entry.url_patterns, route)
            elif route.startswith('api/v1/'):
                found.append(route)

    walk(get_resolver().url_patterns, '')
    cleaned = set()
    for route in found:
        route = route.replace('^', '').replace('$', '').replace('\\.', '.').replace('\\Z', '')
        if 'format' in route or route.endswith('api/v1/'):
            continue  # DRF's ".json" suffix twins and router roots
        cleaned.add(route)
    return sorted(cleaned)


class ApiRobustnessSweep(APITestCase):
    def setUp(self):
        now = timezone.now()
        self.tutor = User.objects.create_user(username='sw_tutor', password='x', role=User.Role.TUTOR, email='sw@example.com')
        self.other_tutor = User.objects.create_user(username='sw_other', password='x', role=User.Role.TUTOR)
        self.student = User.objects.create_user(username='sw_s1', password='x', role=User.Role.STUDENT, tutor=self.tutor)
        self.outsider = User.objects.create_user(username='sw_s2', password='x', role=User.Role.STUDENT)
        for user in (self.student, self.outsider):
            StudentProfile.objects.create(user=user)
        self.tuition = Tuition.objects.create(tutor=self.tutor, title='Sweep group', total_fee=1000, cycle_length=4)
        self.cycle = AttendanceCycle.ensure_active(self.tuition)
        enroll_student(self.tuition, self.student)
        self.legacy_cycle = Cycle.objects.create(
            tutor=self.tutor, student=self.student, cycle_number=1, fee_snapshot=100, total_classes=4,
            classes_data=Cycle.build_fresh_classes_data(4),
        )
        self.exam = Exam.objects.create(
            tutor=self.tutor, tuition=self.tuition, title='Sweep exam', exam_type='HYBRID', total_marks=10,
            start_time=now - timedelta(minutes=5), end_time=now + timedelta(hours=1), content_html='<p>Q</p>',
            mcq_data=[{'id': 'q1', 'question': 'q', 'options': ['a', 'b'], 'correct_answer': 0, 'points': 1}],
            written_scheme=[{'id': 'w1', 'label': 'Q1', 'marks': 5}],
        )
        self.submission = ExamSubmission.objects.create(
            exam=self.exam, student=self.student, submitted_at=now, answers_data={'q1': 0}, status='SUBMITTED',
        )
        self.connection = ConnectionRequest.objects.create(student=self.outsider, tutor=self.tutor)
        self.callers = {
            'signed out': None, 'tutor': self.tutor, 'other tutor': self.other_tutor,
            'student': self.student, 'outsider': self.outsider,
        }
        self.client.raise_request_exception = False

    def urls_for(self, route):
        """Concrete URLs for a route: with ids that exist, and with one that does not."""
        params = re.findall(r'<(?:\w+:)?(\w+)>|\(\?P<(\w+)>[^)]*\)', route)
        if not params:
            return ['/' + route]
        if 'students/' in route:
            real = [self.student.id, self.outsider.id]
        elif 'tuitions/' in route or 'batches/' in route:
            real = [self.tuition.id]
        elif 'attendance-cycles/' in route:
            real = [self.cycle.id]
        elif 'cycles/' in route:
            real = [self.legacy_cycle.id]
        elif 'exams/' in route:
            real = [self.exam.id]
        elif 'submissions/' in route:
            real = [self.submission.id]
        elif 'connections/' in route:
            real = [self.connection.id]
        else:
            self.fail(f'No fixture for route {route}')
        ids = [str(value) for value in real] + ['00000000-0000-0000-0000-000000000000']
        pattern = r'<(?:\w+:)?\w+>|\(\?P<\w+>[^)]*\)'
        return ['/' + re.sub(pattern, value, route) for value in ids]

    def call(self, method, url, body=None, raw=None):
        """One request inside a savepoint, so the fixtures survive whatever it does."""
        savepoint = transaction.savepoint()
        try:
            if raw is not None:
                return self.client.generic(method.upper(), url, raw, content_type='application/json')
            if body is None:
                return getattr(self.client, method)(url)
            return getattr(self.client, method)(url, body, format='json')
        finally:
            transaction.savepoint_rollback(savepoint)

    @mock.patch('rest_framework.views.APIView.throttle_classes', [])
    def test_no_request_can_crash_the_api(self):
        bodies = [{}, [], 'text', 7, None, {'unknown': 1}] + [dict.fromkeys(KNOWN_KEYS, value) for value in BAD_VALUES]
        crashes, exposed, checked = [], [], 0

        for route in api_routes():
            public = any(route == 'api/v1/' + p for p in PUBLIC_ROUTES)
            for url in self.urls_for(route):
                for who, user in self.callers.items():
                    self.client.force_authenticate(user=user)
                    requests = [('get', url + query, None, None) for query in BAD_QUERIES]
                    requests += [('delete', url, None, None), ('put', url, {}, None)]
                    for method in ('post', 'patch'):
                        requests += [(method, url, body, None) for body in bodies]
                        requests += [(method, url, None, raw) for raw in ('{not json', '', '[1,2', '"\\ud800"')]
                    for method, target, body, raw in requests:
                        response = self.call(method, target, body, raw)
                        checked += 1
                        if response.status_code >= 500:
                            shown = raw if raw is not None else json.dumps(body, default=str)[:160]
                            crashes.append(f'{response.status_code} {method.upper()} {target} as {who}: {shown}')
                        elif user is None and not public and response.status_code not in (401, 403, 404, 405):
                            exposed.append(f'{response.status_code} {method.upper()} {target}')

        self.assertGreater(checked, 5000)
        self.assertEqual(exposed, [], 'Protected routes answered a signed-out caller')
        self.assertFalse(crashes, f'{len(crashes)} request(s) crashed the server:\n' + '\n'.join(crashes[:60]))

    @mock.patch('rest_framework.views.APIView.throttle_classes', [])
    def test_every_error_has_the_same_shape(self):
        """Any 4xx carries a human `message` and a machine `code`, whatever produced it."""
        samples = [
            (None, 'get', '/api/v1/exams/', None),                                              # not signed in
            (self.student, 'post', '/api/v1/tuitions/', {'title': 'x'}),                        # wrong role
            (self.tutor, 'get', '/api/v1/exams/00000000-0000-0000-0000-000000000000/', None),   # not found
            (self.tutor, 'post', '/api/v1/exams/', {}),                                         # validation
            (self.tutor, 'put', f'/api/v1/exams/{self.exam.id}/', {}),                          # method
            (self.student, 'post', f'/api/v1/exams/{self.exam.id}/submit/', {}),                # hand-written error
            (None, 'post', '/api/v1/auth/token/', {'username': 'sw_tutor', 'password': 'wrong'}),
            (self.tutor, 'get', '/api/v1/no-such-route/', None),                                # outside any view
        ]
        for user, method, url, body in samples:
            self.client.force_authenticate(user=user)
            response = self.call(method, url, body)
            data = json.loads(response.content)
            self.assertGreaterEqual(response.status_code, 400, url)
            self.assertIsInstance(data, dict, url)
            self.assertTrue(data.get('message') and isinstance(data['message'], str), f'{url}: {data}')
            self.assertTrue(data.get('code') and isinstance(data['code'], str), f'{url}: {data}')
        # Field errors stay addressable by field name.
        self.client.force_authenticate(user=self.tutor)
        data = json.loads(self.call('post', '/api/v1/exams/', {}).content)
        self.assertEqual(data['code'], 'validation_error')
        self.assertIn('title', data['errors'])
        self.assertIn('title', data)  # the original top-level keys are still there for existing clients
