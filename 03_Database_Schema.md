# Database Schema (Django ORM Models)

Database: **PostgreSQL**.  
All models inherit from `TimeStampedModel` (`created_at`, `updated_at`) and use `UUIDField` as their primary keys to prevent sequential ID guessing (IDOR / BOLA).

---

## 1. Abstract Base Models

```python
import uuid
from django.db import models

class TimeStampedModel(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    created_at = models.DateTimeField(auto_now_add=True, db_index=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        abstract = True
```

---

## 2. User Model (Custom User extending AbstractUser)

Inherits from `AbstractUser` and `TimeStampedModel`:
- `id`: UUIDField (PK)
- `email`: EmailField (Unique for tutors; optional or unique for students)
- `role`: CharField (Choices: `TUTOR`, `STUDENT`, max_length=10, db_index=True)
- `phone`: CharField (max_length=20, blank=True)
- `tutor`: ForeignKey('self', null=True, blank=True, on_delete=models.CASCADE, related_name='students')
  *(Null for Tutors. Required for Students, establishing tenancy sandbox).*

---

## 3. StudentProfile Model

Maintains academic and financial configuration:
- `id`: UUIDField (PK)
- `user`: OneToOneField(User, on_delete=models.CASCADE, related_name='student_profile')
- `grade_level`: CharField (max_length=50, blank=True)
- `parent_name`: CharField (max_length=100, blank=True)
- `parent_phone`: CharField (max_length=20, blank=True)
- `tuition_fee`: DecimalField (max_digits=10, decimal_places=2, default=0.00)
- `cycle_length`: PositiveIntegerField (default=12, validators=[MinValueValidator(1)])
- `institution`: CharField (max_length=150, blank=True)

---

## 4. Cycle Model

Tracks dynamic class attendance and acts as an immutable financial cycle:
- `id`: UUIDField (PK)
- `tutor`: ForeignKey(User, on_delete=models.CASCADE, related_name='tutor_cycles', db_index=True)
- `student`: ForeignKey(User, on_delete=models.CASCADE, related_name='student_cycles', db_index=True)
- `cycle_number`: PositiveIntegerField (default=1)
- `fee_snapshot`: DecimalField (max_digits=10, decimal_places=2) *(Snapshot of tuition fee at cycle creation)*
- `total_classes`: PositiveIntegerField (validators=[MinValueValidator(1)]) *(Snapshot of cycle length at cycle creation)*
- `classes_data`: JSONField (default=list)  
  *Format:*
  ```json
  [
    {"classNo": 1, "completed": true, "date": "2026-10-06T10:00:00Z"},
    {"classNo": 2, "completed": false, "date": null}
  ]
  ```
- `status`: CharField (Choices: `ACTIVE`, `ARCHIVED`, default=`ACTIVE`, db_index=True)
- `notes`: TextField (blank=True)

### Constraints & Indexes:
```python
class Meta:
    constraints = [
        models.UniqueConstraint(
            fields=['student'],
            condition=models.Q(status='ACTIVE'),
            name='unique_active_cycle_per_student'
        )
    ]
    indexes = [
        models.Index(fields=['tutor', 'status']),
        models.Index(fields=['student', 'status']),
    ]
```

---

## 5. Exam Model

Stores exam configurations, schedules, and sanitized rich content:
- `id`: UUIDField (PK)
- `tutor`: ForeignKey(User, on_delete=models.CASCADE, related_name='created_exams', db_index=True)
- `student`: ForeignKey(User, on_delete=models.CASCADE, related_name='assigned_exams', db_index=True)
- `title`: CharField (max_length=255)
- `content_html`: TextField *(Sanitized rich text containing ChatGPT markdown/HTML and KaTeX/LaTeX math strings)*
- `total_marks`: DecimalField (max_digits=6, decimal_places=2, default=100.00)
- `start_time`: DateTimeField (db_index=True)
- `end_time`: DateTimeField (db_index=True)
- `duration_minutes`: PositiveIntegerField (null=True, blank=True)
- `grace_period_minutes`: PositiveIntegerField (default=5) *(Network latency window for CQ image uploads)*
- `is_published`: BooleanField (default=True)

---

## 6. ExamSubmission Model

Tracks student answer submissions and tutor grading:
- `id`: UUIDField (PK)
- `exam`: ForeignKey(Exam, on_delete=models.CASCADE, related_name='submissions', db_index=True)
- `student`: ForeignKey(User, on_delete=models.CASCADE, related_name='exam_submissions', db_index=True)
- `submitted_at`: DateTimeField (null=True, blank=True)
- `answers_data`: JSONField (default=dict) *(MCQ answers or typed solutions)*
- `image_urls`: JSONField (default=list) *(URLs/paths of uploaded CQ written answer sheets)*
- `status`: CharField (Choices: `SUBMITTED`, `DELAYED`, `MISSED`, default=`SUBMITTED`)
- `obtained_marks`: DecimalField (max_digits=6, decimal_places=2, null=True, blank=True)
- `tutor_feedback`: TextField (blank=True)
- `is_graded`: BooleanField (default=False, db_index=True)
- `graded_at`: DateTimeField (null=True, blank=True)

### Constraints:
```python
class Meta:
    constraints = [
        models.UniqueConstraint(
            fields=['exam', 'student'],
            name='unique_student_submission_per_exam'
        )
    ]
```