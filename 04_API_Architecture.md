# API Architecture (Django REST Framework)

All protected endpoints require `Authorization: Bearer <access_token>`. All payloads use JSON except file upload endpoints (`multipart/form-data`).

---

## 1. Authentication & Tenant Management

- `POST /api/v1/auth/token/`
  - Body: `{ "username": "...", "password": "..." }`
  - Response: `{ "access": "...", "refresh": "...", "user": { "id": "...", "role": "TUTOR|STUDENT", "name": "..." } }`
- `POST /api/v1/auth/token/refresh/`
  - Refreshes access token via simplejwt.
- `POST /api/v1/auth/register/`
  - Tutor self-registration.
- `GET /api/v1/auth/me/`
  - Returns logged-in user profile, role, and tenant metadata.
- `GET /api/v1/students/`
  - (Tutor only) List all students belonging to the authenticated tutor.
- `POST /api/v1/students/`
  - (Tutor only) Provisions a new student account + `StudentProfile` and automatically initializes Cycle #1.
  - Body: `{ "username": "...", "password": "...", "name": "...", "email": "...", "tuition_fee": 5000, "cycle_length": 12, "grade_level": "Grade 10" }`
- `GET /api/v1/students/<id>/` & `PATCH /api/v1/students/<id>/`
  - View or update student details.

---

## 2. Dynamic Cycles (`/api/v1/cycles/`)

- `GET /api/v1/cycles/?student_id=<uuid>`
  - Scoped query returning the active cycle and archived cycle history for a student.
- `GET /api/v1/cycles/<id>/`
  - Detail view of a specific cycle with `classes_data` and completion metrics.
- `PATCH /api/v1/cycles/<id>/toggle_class/`
  - Checks or unchecks a class box.
  - Body: `{ "class_no": 3, "completed": true }` (or `false` to undo).
  - Automatically records/clears the completion timestamp and recomputes stats.
- `POST /api/v1/cycles/<id>/reset/`
  - Archives the specified cycle (`status = 'ARCHIVED'`).
  - Atomically provisions a new cycle with incremented `cycle_number` and fresh snapshots from `StudentProfile`.

---

## 3. Wallet Analytics (`/api/v1/analytics/`)

- `GET /api/v1/analytics/wallet/`
  - (Tutor only) Dynamically computes financial breakdown across all active student cycles:
  - Response:
    ```json
    {
      "total_students": 5,
      "total_earned": 14500.00,
      "total_pending": 10500.00,
      "lifetime_archived_earnings": 85000.00,
      "chart_data": [
        { "name": "Earned", "value": 14500.00, "color": "#10B981" },
        { "name": "Pending", "value": 10500.00, "color": "#6366F1" }
      ],
      "student_breakdowns": [
        {
          "student_id": "...",
          "student_name": "Rahim",
          "completed_classes": 6,
          "total_classes": 12,
          "earned": 2500.00,
          "pending": 2500.00
        }
      ]
    }
    ```

---

## 4. Exams & Submissions (`/api/v1/exams/`)

- `POST /api/v1/exams/`
  - (Tutor only) Schedules a new exam.
  - Input `content_html` is automatically sanitized on the backend (`nh3`/`bleach`).
  - Triggers asynchronous/background student notification email via `django.core.mail`.
- `GET /api/v1/exams/`
  - Returns exams scoped to user role. For tutors: all authored exams. For students: all assigned exams.
  - Includes dynamically evaluated `dynamic_status`: `Scheduled`, `Running`, `Submitted`, `Delayed`, `Missed`.
- `GET /api/v1/exams/<id>/`
  - Retrieves exam details, questions HTML, and existing submission (if any).
- `POST /api/v1/exams/<id>/submit/`
  - (Student only) Validates against server UTC time + grace period.
  - Body: `{ "answers_data": { "q1": "A", "q2": "D" }, "image_urls": ["/media/exams/cq1.jpg"] }`
  - Automatically tags `status` as `SUBMITTED` (on-time) or `DELAYED` (grace period). Rejects with `400` if window closed.
- `PATCH /api/v1/submissions/<id>/grade/`
  - (Tutor only) Records marks and textual feedback.
  - Body: `{ "obtained_marks": 85.50, "tutor_feedback": "Great derivation in CQ 2." }`
  - Sets `is_graded = true` and `graded_at = timezone.now()`.

---

## 5. Media Upload (`/api/v1/media/`)

- `POST /api/v1/media/upload/`
  - Handles `multipart/form-data` image uploads for exam questions and student CQ scripts.
  - Validates file extension, MIME type, and size limit (e.g., max 10MB per image).
  - Returns `{ "file_url": "/media/uploads/..." }`.