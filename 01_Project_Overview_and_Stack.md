# Project Overview: TuitionTrack SaaS

## 1. Introduction
TuitionTrack is a multi-tenant SaaS platform engineered specifically for independent tutors. It empowers tutors to manage students, track dynamic class attendance and payment cycles, visualize real-time earned vs. pending revenue with gamified wallet analytics, and conduct secure, time-bound online examinations with rich-text and scientific equation support.

## 2. Core Architecture Principles
- **Multi-Tenancy & Data Isolation:** Strict logical isolation at the ORM and API levels. Tutors only have access to their own students, cycles, exams, and submissions via scoped queries (`tutor_id`). Students are securely scoped to their assigned tutor.
- **API-First Architecture:** Complete decoupling between the Django REST Framework backend and the React Vite single-page application.
- **Security-First Content Pipeline:** Stored XSS defense-in-depth using backend HTML sanitization (`nh3` / `bleach`) and frontend DOMPurify before rendering tutor-created exam questions.
- **Server-Authoritative Time:** All exam start, end, countdown, and dynamic state evaluations rely strictly on server UTC timestamps (`django.utils.timezone.now()`) to prevent client clock tampering.
- **Primary Keys:** UUIDv4 identifiers across all domain models to prevent sequential ID enumeration attacks (IDOR/BOLA).

## 3. Technology Stack

### Backend
- **Framework:** Python 3.11+, Django 5.x, Django REST Framework (DRF).
- **Authentication:** JWT via `djangorestframework-simplejwt` with role-based access control (`TUTOR`, `STUDENT`).
- **Database:** PostgreSQL (using Django ORM).
- **HTML Sanitization:** `nh3` (Python Ammonia binding) or `bleach` for strict tag/attribute whitelisting.
- **Email Service:** Django core mail (`django.core.mail`) via SMTP for automated student exam notifications.
- **Media Storage:** Django FileSystemStorage / Cloud Storage for CQ answer script image uploads.

### Frontend
- **Framework & Tooling:** React.js (Vite), React Router.
- **Styling:** Tailwind CSS (modern SaaS design system with Slate, Indigo, and Emerald palettes).
- **Rich Text Editor:** TipTap (Headless WYSIWYG) supporting Markdown-to-HTML parsing (direct copy-paste from ChatGPT), table formatting, and image embedding.
- **Scientific/Math Rendering:** KaTeX (`rehype-katex` / TipTap Math extension) for rendering LaTeX math formulas.
- **Client Sanitization:** `dompurify` for defensive client-side HTML sanitization.
- **Data Visualization:** `recharts` for animated pie/donut wallet analytics.
- **Icons:** `lucide-react`.