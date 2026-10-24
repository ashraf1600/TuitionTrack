"""POST/DELETE /auth/me/photo/: a user sets or removes their own profile photo."""
import io
import shutil
import tempfile

from django.contrib.auth import get_user_model
from django.core.files.uploadedfile import SimpleUploadedFile
from django.test import override_settings
from django.urls import reverse
from PIL import Image
from rest_framework import status
from rest_framework.test import APITestCase

User = get_user_model()
MEDIA = tempfile.mkdtemp(prefix='tt-media-')


def png(name='me.png', size=(8, 8)):
    buffer = io.BytesIO()
    Image.new('RGB', size, (5, 150, 105)).save(buffer, format='PNG')
    return SimpleUploadedFile(name, buffer.getvalue(), content_type='image/png')


@override_settings(MEDIA_ROOT=MEDIA, STORAGES={
    'default': {'BACKEND': 'django.core.files.storage.FileSystemStorage'},
    'staticfiles': {'BACKEND': 'django.contrib.staticfiles.storage.StaticFilesStorage'},
})
class ProfilePhotoTests(APITestCase):
    @classmethod
    def tearDownClass(cls):
        super().tearDownClass()
        shutil.rmtree(MEDIA, ignore_errors=True)

    def setUp(self):
        self.tutor = User.objects.create_user(username='tutor', password='x', role=User.Role.TUTOR)
        self.url = reverse('user_me_photo')

    def test_sign_in_needed(self):
        self.assertEqual(self.client.post(self.url, {'photo': png()}, format='multipart').status_code, status.HTTP_401_UNAUTHORIZED)

    def test_set_replace_and_remove(self):
        self.client.force_authenticate(self.tutor)
        resp = self.client.post(self.url, {'photo': png()}, format='multipart')
        self.assertEqual(resp.status_code, status.HTTP_200_OK, resp.data)
        self.assertTrue(resp.data['profile_picture_url'])
        self.tutor.refresh_from_db()
        first = self.tutor.profile_picture.name
        self.assertTrue(self.tutor.profile_picture.storage.exists(first))

        resp = self.client.post(self.url, {'photo': png('new.png')}, format='multipart')
        self.assertEqual(resp.status_code, status.HTTP_200_OK)
        self.tutor.refresh_from_db()
        self.assertNotEqual(self.tutor.profile_picture.name, first)
        self.assertFalse(self.tutor.profile_picture.storage.exists(first), 'the replaced photo is deleted')

        resp = self.client.delete(self.url)
        self.assertEqual(resp.status_code, status.HTTP_200_OK)
        self.assertIsNone(resp.data['profile_picture_url'])

    def test_rejects_files_that_are_not_pictures(self):
        self.client.force_authenticate(self.tutor)
        fake = SimpleUploadedFile('x.png', b'<html>not a picture</html>', content_type='image/png')
        self.assertEqual(self.client.post(self.url, {'photo': fake}, format='multipart').status_code, status.HTTP_400_BAD_REQUEST)
        pdf = SimpleUploadedFile('x.pdf', b'%PDF-1.4\n%%EOF', content_type='application/pdf')
        self.assertEqual(self.client.post(self.url, {'photo': pdf}, format='multipart').status_code, status.HTTP_400_BAD_REQUEST)
        self.assertEqual(self.client.post(self.url, {}, format='multipart').status_code, status.HTTP_400_BAD_REQUEST)
        self.tutor.refresh_from_db()
        self.assertFalse(self.tutor.profile_picture)

    def test_profile_fields_still_work(self):
        # The existing PATCH /auth/me/ is unchanged.
        self.client.force_authenticate(self.tutor)
        resp = self.client.patch(reverse('user_me'), {'first_name': 'Ashraf'}, format='json')
        self.assertEqual(resp.status_code, status.HTTP_200_OK)
        self.assertEqual(resp.data['first_name'], 'Ashraf')

    def test_students_see_the_tutor_photo_in_search_and_requests(self):
        from apps.students.models import ConnectionRequest
        self.client.force_authenticate(self.tutor)
        self.client.post(self.url, {'photo': png()}, format='multipart')
        student = User.objects.create_user(username='stu', password='x', role=User.Role.STUDENT)
        ConnectionRequest.objects.create(student=student, tutor=self.tutor)

        self.client.force_authenticate(student)
        found = self.client.get(reverse('tutor_directory'), {'search': 'tutor'}).data
        rows = found['results'] if isinstance(found, dict) else found
        self.assertTrue(rows[0]['profile_picture_url'])

        mine = self.client.get('/api/v1/connections/').data
        rows = mine['results'] if isinstance(mine, dict) else mine
        self.assertTrue(rows[0]['tutor_profile_picture'])
