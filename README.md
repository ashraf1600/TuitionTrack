# TuitionTrack SaaS

A **multi-tenant SaaS platform** engineered for independent tutors — combining dynamic class cycle tracking, gamified wallet analytics, and a smart time-bound exam engine with rich-text mathematical formula support.

---

## Tech Stack

| Layer | Technology |
|---|---|
| Backend | Python 3.11, Django 5.x, Django REST Framework |
| Auth | JWT (`djangorestframework-simplejwt`) |
| Database | PostgreSQL |
| HTML Sanitization | `nh3` / `bleach` |
| Frontend | React.js (Vite) + Tailwind CSS |
| Rich Text Editor | TipTap + KaTeX (Math equations) |
| Charts | Recharts |
| Email | Django core mail (SMTP) |

---

## Core Features

- 🏫 **Multi-Tenant Architecture** — Strict per-tutor data isolation at the ORM and API levels
- 📋 **Dynamic Cycle Tracking** — Configurable class grids (8/12/16 classes), togglable checkboxes, cycle archiving
- 💰 **Gamified Wallet Analytics** — Real-time earned vs. pending revenue donut chart
- 📝 **Smart Exam Engine** — Schedule exams, rich-text + LaTeX question editing, time-bound submissions with grace period
- 🔐 **Security-First** — UUID PKs, stored XSS prevention (backend nh3 + frontend DOMPurify), role-based access control

---

## Project Structure

```
TuitionTrack/
├── backend/                  # Django DRF project
│   ├── authentication/       # Custom user model, JWT auth
│   ├── students/             # StudentProfile management
│   ├── cycles/               # Dynamic cycle engine
│   ├── analytics/            # Wallet analytics endpoints
│   └── exams/                # Exam module, sanitization, grading
├── frontend/                 # React Vite application
│   └── src/
│       ├── components/
│       ├── pages/
│       └── hooks/
└── docs/                     # Specification documents
    ├── 01_Project_Overview_and_Stack.md
    ├── 02_Product_Requirements_Document.md
    ├── 03_Database_Schema.md
    ├── 04_API_Architecture.md
    ├── 05_UI_UX_Guidelines.md
    └── 06_Execution_Prompts.md
```

---

## Development Phases

- **Phase 1** ✅ — Django project setup, custom user model, all database models
- **Phase 2** 🔄 — JWT auth, role permissions, student provisioning API
- **Phase 3** ⬜ — Cycle engine & wallet analytics
- **Phase 4** ⬜ — Exam engine, HTML sanitization, email alerts
- **Phase 5** ⬜ — React frontend (Vite, Tailwind, TipTap + KaTeX, Recharts)

---

## License
MIT
