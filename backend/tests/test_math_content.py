"""
Maths and science in questions: what the tutor types or pastes (LaTeX with
$…$ / \\(…\\) / $$…$$, escaped backslashes, bare LaTeX, Bangla) is stored and
handed to students unchanged, so the apps can typeset it when they show it.
"""
from datetime import timedelta

from django.contrib.auth import get_user_model
from django.urls import reverse
from django.utils import timezone
from rest_framework import status
from rest_framework.test import APITestCase

from apps.students.models import Tuition
from apps.students.services import enroll_student

User = get_user_model()

# The CQ from ChatGPT, as the website's editor stores it (one paragraph per line).
CQ_HTML = (
    '<p><strong>প্রশ্ন ১। সূচক ও লগারিদম</strong></p>'
    '<p><strong>উদ্দীপক:</strong></p>'
    r'<p>$$a=2^3\times 2^{-2},\qquad b=\log_2 8$$</p>'
    '<p>ক. সূচক কাকে বলে? (১)</p>'
    r'<p>খ. $a^m\times a^n=a^{m+n}$ ব্যাখ্যা করো। (২)</p>'
    r'<p>গ. $a$-এর মান নির্ণয় করো। (৩)</p>'
    r'<p>ঘ. $a^b+b^a$-এর মান নির্ণয় করো। (৪)</p>'
    r'<p>$$\begin{bmatrix}1&amp;2\\3&amp;4\end{bmatrix}$$</p>'
)

QUESTIONS = [
    r'Speed of light is 3.0 \times 10^{8} m/s. Which is \(9.11 \times 10^{-31}\)?',
    r'If a=2^3\\times 2^{-2}, then a =',
    r'\sqrt{x^2+y^2} যখন x=3, y=4',
    'Which gas do plants take in? (no maths) < & >',
]


class MathContentTests(APITestCase):
    def setUp(self):
        self.tutor = User.objects.create_user(username='m_tutor', password='x', role=User.Role.TUTOR)
        self.student = User.objects.create_user(username='m_s1', password='x', role=User.Role.STUDENT, tutor=self.tutor)
        self.group = Tuition.objects.create(tutor=self.tutor, title='Group', total_fee=1000, cycle_length=4)
        enroll_student(self.group, self.student)

    def test_formulas_reach_students_exactly_as_written(self):
        now = timezone.now()
        self.client.force_authenticate(user=self.tutor)
        resp = self.client.post(reverse('exam-list'), {
            'title': 'সূচক ও লগারিদম', 'exam_type': 'HYBRID', 'tuition_id': str(self.group.id), 'total_marks': '20',
            'start_time': (now - timedelta(minutes=5)).isoformat(),
            'end_time': (now + timedelta(hours=1)).isoformat(),
            'content_html': CQ_HTML,
            'mcq_data': [
                {'question': q, 'options': [r'\(2\)', '4', r'$\log_2 8$', r'\frac{1}{2}'], 'correct_answer': 0, 'points': 1}
                for q in QUESTIONS
            ],
        }, format='json')
        self.assertEqual(resp.status_code, status.HTTP_201_CREATED, resp.data)
        exam_id = resp.data['exam']['id']

        self.client.force_authenticate(user=self.student)
        detail = self.client.get(reverse('exam-detail', kwargs={'pk': exam_id}))
        self.assertEqual(detail.status_code, status.HTTP_200_OK)

        # The written paper: every formula and the Bangla text survive the HTML sanitiser.
        html = detail.data['content_html']
        for piece in (r'$$a=2^3\times 2^{-2},\qquad b=\log_2 8$$', r'$a^m\times a^n=a^{m+n}$',
                      r'\begin{bmatrix}1', r'\\3', r'\end{bmatrix}', 'প্রশ্ন ১। সূচক ও লগারিদম', '(৪)'):
            self.assertIn(piece, html)

        # MCQs: stored as plain text, byte for byte, including doubled backslashes.
        questions = detail.data['mcq_data']
        self.assertEqual([q['question'] for q in questions], QUESTIONS)
        self.assertEqual(questions[0]['options'], [r'\(2\)', '4', r'$\log_2 8$', r'\frac{1}{2}'])

    def test_a_script_tag_in_the_paper_is_removed(self):
        now = timezone.now()
        self.client.force_authenticate(user=self.tutor)
        resp = self.client.post(reverse('exam-list'), {
            'title': 'T', 'exam_type': 'CQ', 'tuition_id': str(self.group.id), 'total_marks': '10',
            'start_time': (now - timedelta(minutes=5)).isoformat(),
            'end_time': (now + timedelta(hours=1)).isoformat(),
            'content_html': r'<p>$x^2$</p><script>alert(1)</script><img src=x onerror="alert(1)">',
        }, format='json')
        self.assertEqual(resp.status_code, status.HTTP_201_CREATED, resp.data)
        html = resp.data['exam']['content_html']
        self.assertIn('$x^2$', html)
        self.assertNotIn('<script', html)
        self.assertNotIn('onerror', html)
