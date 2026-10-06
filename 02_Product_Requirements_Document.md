# Product Requirements Document (PRD)

## 1. User Roles & Personas

- **Tutor (Tenant Admin):**
  - Self-registers and logs in.
  - Provisions and manages student accounts under their tenancy.
  - Configures tuition fee and cycle length per student.
  - Marks completed classes in real-time or unchecks accidental clicks.
  - Archives completed or early-terminated cycles to start new cycles.
  - Monitors wallet analytics (earned vs. pending income, total earnings).
  - Drafts and schedules exams using the Advanced Rich Text Editor.
  - Grades submissions, awards scores, and provides textual feedback on student CQ answer uploads.

- **Student (End User):**
  - Authenticates using credentials created by their tutor.
  - Scoped strictly to their tutor's portal.
  - Views current active cycle progress, class attendance logs, and completed count.
  - Receives email alerts when new exams are scheduled.
  - Takes time-bound exams during the active window, inputs MCQ answers, and uploads CQ answer sheets.
  - Views exam results, scores, and tutor feedback once graded.

---

## 2. Core Features & Business Logic

### 2.1 Dynamic Cycle Tracking
- **Configuration:** When creating or editing a student, tutors define a `tuition_fee` (e.g., 5000 BDT) and `cycle_length` (e.g., 8, 12, 16 classes; minimum 1).
- **Cycle Snapshotting:** When an active cycle is created, it snapshots `fee_snapshot` and `total_classes`. Future profile fee updates do not retroactively alter active or archived cycles.
- **Dynamic Checkbox Grid:**
  - Frontend renders a reactive grid matching `total_classes`.
  - Tutors toggle class checkboxes. Marking a class as complete records `completed: true` and the ISO timestamp. Unchecking resets `completed: false` and clears the timestamp.
  - Completed count is calculated as the sum of all checked classes.
- **Cycle Reset / Renewal:**
  - When all classes are complete (or if early renewal is required), the tutor clicks "Start New Cycle".
  - The current cycle transitions from `ACTIVE` to `ARCHIVED`.
  - A new `ACTIVE` cycle is atomically generated with incremented `cycle_number` and fresh snapshots.
  - Strict database rule: Exactly **one** active cycle per student.

### 2.2 Gamified Tuition Wallet
- **Real-Time Earnings Calculation:**
  $$\text{Per Class Rate} = \frac{\text{fee\_snapshot}}{\text{total\_classes}}$$
  $$\text{Earned Revenue} = \text{Per Class Rate} \times \text{completed\_classes}$$
  $$\text{Pending Revenue} = \text{fee\_snapshot} - \text{Earned Revenue}$$
- **Dashboard Visualization:**
  - Animated `Recharts` Donut/Pie Chart displaying **Earned** vs. **Pending** balance across the tutor's active roster.
  - Aggregate metrics: Total active students, total earned this month, and historical lifetime earnings from archived cycles.

### 2.3 Smart Exam Module & Advanced Editor
- **Rich Text & Formula Authoring:**
  - Tutors author questions using TipTap/TinyMCE with full LaTeX/KaTeX equation support.
  - Flawless copy-pasting from ChatGPT preserving tables, bullet points, code blocks, bold text, and math equations ($...$ and $$...$$).
  - Inline image insertion for diagrams and geometry problems.
  - Automatic backend sanitization (`nh3`/`bleach`) before database persistence to eliminate stored XSS.
- **Server-Authoritative Time Engine & Dynamic States:**
  - Status is evaluated against server UTC time (`now = timezone.now()`):
    1. **`Scheduled`:** $now < start\_time$ and no submission exists.
    2. **`Running`:** $start\_time \le now \le end\_time$ and no submission exists.
    3. **`Submitted`:** Student successfully submitted before or at $end\_time$.
    4. **`Delayed`:** Student submitted during the configurable grace period ($end\_time < now \le end\_time + grace\_period$).
    5. **`Missed`:** $now > end\_time + grace\_period$ and no submission was recorded.
- **Submissions & Image Uploads:**
  - Students can select MCQ options or upload high-resolution CQ answer photos directly from mobile devices.
  - 5-minute network latency grace period for photo uploads.
- **Grading & Results:**
  - Tutors review submitted CQ images and MCQ answers, input `obtained_marks` out of `total_marks`, and add feedback notes.
  - Once marked `is_graded = true`, students can view their breakdown and score badge.
- **Automated Notifications:**
  - Upon exam publishing, an automated notification email with the exam title, schedule, and syllabus link is sent to the student's email via `django.core.mail`.
