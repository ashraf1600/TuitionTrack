"""Tests for Authentication app"""
from django.urls import reverse
from django.contrib.auth import get_user_model
from rest_framework import status
from rest_framework.test import APITestCase

User = get_user_model()


class AuthenticationTests(APITestCase):
    def setUp(self):
        self.register_url = reverse('tutor_register')
        self.token_url = reverse('token_obtain_pair')
        self.token_refresh_url = reverse('token_refresh')
        self.me_url = reverse('user_me')

    def test_tutor_registration_success(self):
        data = {
            'username': 'newtutor',
            'email': 'newtutor@example.com',
            'first_name': 'New',
            'last_name': 'Tutor',
            'phone': '+8801711111111',
            'password': 'password123',
            'password_confirm': 'password123',
        }
        response = self.client.post(self.register_url, data, format='json')
        self.assertEqual(response.status_code, status.HTTP_201_CREATED)
        self.assertTrue(User.objects.filter(username='newtutor').exists())
        user = User.objects.get(username='newtutor')
        self.assertEqual(user.role, User.Role.TUTOR)

    def test_tutor_registration_password_mismatch(self):
        data = {
            'username': 'mismatchtutor',
            'email': 'mismatch@example.com',
            'password': 'password123',
            'password_confirm': 'differentpassword',
        }
        response = self.client.post(self.register_url, data, format='json')
        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn('password_confirm', response.data)

    def test_jwt_login_returns_custom_claims_and_user_profile(self):
        tutor = User.objects.create_user(
            username='logintutor',
            password='testpassword123',
            email='logintutor@example.com',
            first_name='Login',
            last_name='Tutor',
            role=User.Role.TUTOR,
        )
        response = self.client.post(self.token_url, {
            'username': 'logintutor',
            'password': 'testpassword123',
        }, format='json')
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertIn('access', response.data)
        self.assertIn('refresh', response.data)
        self.assertIn('user', response.data)
        self.assertEqual(response.data['user']['role'], 'TUTOR')
        self.assertEqual(response.data['user']['username'], 'logintutor')

    def test_me_endpoint_requires_auth(self):
        response = self.client.get(self.me_url)
        self.assertEqual(response.status_code, status.HTTP_401_UNAUTHORIZED)

    def test_me_endpoint_returns_authenticated_user(self):
        user = User.objects.create_user(
            username='meuser',
            password='testpassword123',
            email='meuser@example.com',
            first_name='Me',
            last_name='User',
            role=User.Role.TUTOR,
        )
        self.client.force_authenticate(user=user)
        response = self.client.get(self.me_url)
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(response.data['username'], 'meuser')
        self.assertEqual(response.data['role'], 'TUTOR')
