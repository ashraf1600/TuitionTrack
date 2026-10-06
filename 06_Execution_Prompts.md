# Phased Execution Prompts & Implementation Roadmap

This document outlines the phased implementation plan for **TuitionTrack SaaS**. Each phase contains strict scope boundaries, deliverables, and acceptance criteria.

---

## Phase 1: Backend Foundation & Database Models
**Goal:** Initialize the Django REST Framework project, configure PostgreSQL/SQLite, setup abstract base classes, implement the complete database schema with UUIDs, and establish multi-tenant data structures.

### Deliverables:
1. **Django Project Initialization:**
   - Create project `tuitiontrack_backend` and apps: `authentication`, `students`, `cycles`, `analytics`, `exams`.
   - Setup environment configuration (`python-dotenv` or `django-environ`).
   - Configure DRF with JSON renderer and SimpleJWT settings.
2. **Models & Migrations:**
   - Implement `TimeStampedModel` with UUID primary keys.
   - Implement `CustomUser` (`role`, `tutor` self-referential foreign key).
   - Implement `StudentProfile` with `tuition_fee` and `cycle_length`.
   - Implement `Cycle` model with `fee_snapshot`, `total_classes`, `classes_data` JSON, status, and partial unique active constraint.
   - Implement `Exam` with `content_html`, `total_marks`, `start_time`, `end_time`, `grace_period_minutes`.
   - Implement `ExamSubmission` with `answers_data`, `image_urls`, `obtained_marks`, grading fields, and unique constraint.
3. **Admin Configuration:**
   - Register all models with informative list displays, search fields, and filters for debugging.

---

## Phase 2: Authentication, Tenancy & Student Provisioning API
**Goal:** Implement JWT-based auth, role permissions (`IsTutor`, `IsStudent`), and student onboarding endpoints.

### Deliverables:
1. **SimpleJWT Authentication Endpoints:**
   - `POST /api/v1/auth/token/` (custom claims for `role`, `user_id`, `tutor_id`).
   - `POST /api/v1/auth/token/refresh/`.
   - `POST /api/v1/auth/register/` (Tutor registration).
   - `GET /api/v1/auth/me/`.
2. **Student Management Endpoints:**
   - `GET /api/v1/students/` (Tutor lists their students).
   - `POST /api/v1/students/` (Tutor creates a student: creates user, creates `StudentProfile`, atomically initializes Cycle #1).
   - `GET /api/v1/students/<id>/` & `PATCH /api/v1/students/<id>/`.
3. **Multi-Tenancy Guard:**
   - Base `TenantScopedViewSet` that guarantees tutors only see and modify their own students.

---

## Phase 3: Dynamic Cycle Engine & Gamified Wallet Analytics
**Goal:** Build the dynamic class attendance engine and the wallet revenue computation API.

### Deliverables:
1. **Cycle Operations API:**
   - `GET /api/v1/cycles/?student_id=<id>` (Fetches active cycle + history).
   - `PATCH /api/v1/cycles/<id>/toggle_class/`:
     - Toggles `completed: true/false` for a specific `classNo`.
     - Sets/clears timestamp.
     - Validates that `classNo` is between 1 and `total_classes`.
   - `POST /api/v1/cycles/<id>/reset/`:
     - Archives the current cycle (`status = 'ARCHIVED'`).
     - Atomically creates the next active cycle (`cycle_number += 1`) snapshotting current profile fees.
2. **Wallet Analytics API:**
   - `GET /api/v1/analytics/wallet/`:
     - Computes real-time `earned` and `pending` revenue across active cycles.
     - Computes lifetime historical revenue from archived cycles.
     - Returns formatted payload for Recharts donut visualization.

---

## Phase 4: Smart Exam Engine, HTML Sanitization & Email Alerts
**Goal:** Build the rich-text exam authoring, backend XSS sanitization, dynamic status evaluation, student submission, and grading workflow.

### Deliverables:
1. **Sanitization Engine:**
   - Implement `sanitize_exam_html(raw_html)` using `nh3` (or `bleach`).
   - Allow safe tags, tables, images, and LaTeX/KaTeX containers while stripping scripts, iframes, and dangerous handlers.
2. **Exam Lifecycle API:**
   - `POST /api/v1/exams/`: Sanitizes HTML, creates exam, dispatches student alert email via `django.core.mail`.
   - `GET /api/v1/exams/`: Returns list with dynamically calculated server-time status (`Scheduled`, `Running`, `Submitted`, `Delayed`, `Missed`).
   - `GET /api/v1/exams/<id>/`: Detail view with sanitized content.
3. **Submission & Grading:**
   - `POST /api/v1/exams/<id>/submit/`: Validates submission against server UTC time + grace period; prevents duplicate submissions.
   - `POST /api/v1/media/upload/`: Multipart image upload endpoint for CQ answer sheets.
   - `PATCH /api/v1/submissions/<id>/grade/`: Tutor assigns marks and textual feedback.

---

## Phase 5: React Frontend Application (Vite + Tailwind)
**Goal:** Deliver a modern, high-polish React SPA with rich-text math editing, animated wallet charts, and mobile-friendly exam taking.

### Deliverables:
1. **App Shell & State:**
   - Vite + React + Tailwind setup with dark/light mode foundations.
   - Auth state with JWT persistence, route guards (`TutorRoute`, `StudentRoute`).
2. **Tutor Dashboard:**
   - **Wallet Widget:** Animated `Recharts` Donut Chart with live stats.
   - **Student Roster:** Add student modal, student cards with progress indicators.
   - **Dynamic Cycle Grid:** Interactive checkbox grid (8/12/16 classes) with instant optimistic toggle updates and "Start New Cycle" modal.
3. **Advanced Exam Authoring (TipTap + KaTeX):**
   - TipTap WYSIWYG editor supporting Markdown paste from ChatGPT, KaTeX math rendering, and image embeds.
4. **Student Portal & Exam Taker:**
   - Mobile-first responsive exam taking interface with live countdown timer.
   - MCQ selection and mobile camera CQ photo upload UI.
   - Results & grading report cards.