"""
Cycles roll over by themselves when the last class is marked, payment is
recorded by the tutor (cash) and never blocks tracking, and students see a
"payment pending" reminder per finished cycle — without amounts.
"""
from django.contrib.auth import get_user_model
from django.urls import reverse
from rest_framework import status
from rest_framework.test import APITestCase

from apps.cycles.models import AttendanceCycle

User = get_user_model()


class CyclePaymentTests(APITestCase):
    def setUp(self):
        self.tutor = User.objects.create_user(username='p_tutor', password='x', role=User.Role.TUTOR, first_name='Ashraful')
        self.other = User.objects.create_user(username='p_other', password='x', role=User.Role.TUTOR)
        self.student = User.objects.create_user(username='p_student', password='x', role=User.Role.STUDENT, tutor=self.tutor)
        self.client.force_authenticate(self.tutor)
        resp = self.client.post(reverse('tuition-list'), {
            'title': 'Physics', 'subject': 'Physics', 'cycle_length': 3, 'total_fee': '3000.00',
            'student_ids': [str(self.student.id)],
        }, format='json')
        self.assertEqual(resp.status_code, status.HTTP_201_CREATED, resp.data)
        self.tuition_id = resp.data['id']

    def mark(self, n, completed=True):
        return self.client.patch(reverse('tuition-mark-class', kwargs={'pk': self.tuition_id}),
                                 {'class_no': n, 'completed': completed}, format='json')

    def finish_cycle(self):
        for n in (1, 2, 3):
            resp = self.mark(n)
            self.assertEqual(resp.status_code, status.HTTP_200_OK, resp.data)
        return resp

    def test_last_class_starts_the_next_cycle_and_leaves_payment_pending(self):
        resp = self.finish_cycle()
        self.assertEqual(resp.data['completed_cycle_number'], 1)
        self.assertEqual(resp.data['cycle']['cycle_number'], 2)
        self.assertEqual(resp.data['cycle']['completed_classes'], 0)
        old = AttendanceCycle.objects.get(tuition_id=self.tuition_id, cycle_number=1)
        self.assertEqual(old.status, 'ARCHIVED')
        self.assertEqual(old.payment_status, 'PENDING')
        # Tracking goes on in the new cycle although cycle #1 is unpaid.
        self.assertEqual(self.mark(1).status_code, status.HTTP_200_OK)

        detail = self.client.get(reverse('tuition-detail', kwargs={'pk': self.tuition_id})).data
        self.assertEqual([p['cycle_number'] for p in detail['pending_payments']], [1])
        self.assertEqual(detail['pending_payments'][0]['amount'], 3000.0)
        wallet = self.client.get(reverse('wallet-analytics')).data
        self.assertEqual(wallet['unpaid_cycles'], 1)
        self.assertEqual(wallet['unpaid_total'], 3000.0)

    def test_student_sees_pending_until_tutor_marks_paid_and_never_the_amount(self):
        self.finish_cycle()
        cycle = AttendanceCycle.objects.get(tuition_id=self.tuition_id, cycle_number=1)

        self.client.force_authenticate(self.student)
        mine = self.client.get(reverse('tuition-list')).data
        rows = mine['results'] if isinstance(mine, dict) else mine
        self.assertEqual(rows[0]['pending_payments'][0]['cycle_number'], 1)
        self.assertNotIn('amount', rows[0]['pending_payments'][0])
        self.assertEqual(rows[0]['tutor_id'], str(self.tutor.id))
        history = self.client.get(reverse('attendance-cycle-list'), {'tuition_id': self.tuition_id}).data
        history = history['results'] if isinstance(history, dict) else history
        self.assertTrue(all('earned_revenue' not in c and 'payment_note' not in c for c in history))
        # Students cannot record payments.
        self.assertEqual(
            self.client.post(reverse('attendance-cycle-payment', kwargs={'pk': cycle.id}), {'paid': True}, format='json').status_code,
            status.HTTP_403_FORBIDDEN,
        )

        self.client.force_authenticate(self.tutor)
        paid = self.client.post(reverse('attendance-cycle-payment', kwargs={'pk': cycle.id}), {'paid': True, 'note': 'Cash'}, format='json')
        self.assertEqual(paid.status_code, status.HTTP_200_OK, paid.data)
        self.assertEqual(paid.data['cycle']['payment_status'], 'PAID')
        self.assertIsNotNone(paid.data['cycle']['paid_at'])

        self.client.force_authenticate(self.student)
        mine = self.client.get(reverse('tuition-list')).data
        rows = mine['results'] if isinstance(mine, dict) else mine
        self.assertEqual(rows[0]['pending_payments'], [])

    def test_payment_needs_a_true_or_false_and_stays_with_the_owner(self):
        self.finish_cycle()
        cycle = AttendanceCycle.objects.get(tuition_id=self.tuition_id, cycle_number=1)
        url = reverse('attendance-cycle-payment', kwargs={'pk': cycle.id})
        self.assertEqual(self.client.post(url, {'paid': 'yes'}, format='json').status_code, status.HTTP_400_BAD_REQUEST)
        self.client.force_authenticate(self.other)
        self.assertEqual(self.client.post(url, {'paid': True}, format='json').status_code, status.HTTP_404_NOT_FOUND)

    def test_reopen_undoes_a_roll_over_only_while_the_new_cycle_is_empty(self):
        self.finish_cycle()
        old = AttendanceCycle.objects.get(tuition_id=self.tuition_id, cycle_number=1)
        url = reverse('attendance-cycle-reopen', kwargs={'pk': old.id})

        self.mark(1)  # cycle #2 now has a class
        self.assertEqual(self.client.post(url).status_code, status.HTTP_400_BAD_REQUEST)
        self.mark(1, completed=False)

        resp = self.client.post(url)
        self.assertEqual(resp.status_code, status.HTTP_200_OK, resp.data)
        self.assertEqual(resp.data['cycle']['cycle_number'], 1)
        self.assertEqual(AttendanceCycle.objects.filter(tuition_id=self.tuition_id).count(), 1)
        self.assertEqual(AttendanceCycle.objects.get(tuition_id=self.tuition_id).status, 'ACTIVE')
        # Undo the mistaken last class; marking it again rolls over again.
        self.mark(3, completed=False)
        self.assertEqual(self.mark(3).data['completed_cycle_number'], 1)

    def test_student_sees_tutors_who_added_them_without_a_request(self):
        self.client.force_authenticate(self.student)
        tutors = self.client.get(reverse('my-tutors')).data
        self.assertEqual([t['id'] for t in tutors], [str(self.tutor.id)])
        detail = self.client.get(reverse('tutor-detail-for-student', kwargs={'tutor_id': self.tutor.id}))
        self.assertEqual(detail.status_code, status.HTTP_200_OK)
        stranger = self.client.get(reverse('tutor-detail-for-student', kwargs={'tutor_id': self.other.id}))
        self.assertEqual(stranger.status_code, status.HTTP_404_NOT_FOUND)
