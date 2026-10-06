# UI/UX & Frontend Guidelines (React + Tailwind)

## 1. Design System & Principles
- **Framework & CSS:** React.js (Vite) + Tailwind CSS.
- **Visual Aesthetic:** Modern, high-trust SaaS interface. Dark slate foundation (`slate-900`/`slate-800`), crisp white cards, Indigo primary accents (`indigo-600`), and Emerald success accents (`emerald-500`).
- **Typography:** Inter or Outfit from Google Fonts. High legibility with distinct mathematical formula rendering.
- **Responsiveness:** 100% mobile-first responsiveness. Mobile view is paramount for students taking photos and uploading CQ answer scripts from mobile cameras.

---

## 2. Rich Text Editor Implementation (CRITICAL)
- **Editor Core:** **TipTap** (headless WYSIWYG) integrated with Tailwind Typography (`prose prose-slate`).
- **Pasting from ChatGPT:** Must retain formatting seamlessly when tutors paste Markdown or HTML outputs from ChatGPT (preserving headers, bolding, lists, code snippets, and markdown tables).
- **Scientific/Math Equations:**
  - Integrated with **KaTeX** (via TipTap Math Extension / KaTeX CSS).
  - Automatically parses `$inline_math$` and `$$block_math$$` into rendered mathematical formulas.
- **Inline Media:** Allows uploading and embedding diagrams and formulas directly in the editor.
- **Client-Side Defense:** All rendered rich text is wrapped with `DOMPurify.sanitize()` prior to mounting in student views.

---

## 3. Key Dashboard Components

### 3.1 Gamified Tuition Wallet Widget
- **Visualization:** `Recharts` Donut Chart featuring smooth entry animations and tooltips.
- **Slices:**
  - `Earned`: Emerald `#10B981` (classes completed $\times$ rate).
  - `Pending`: Indigo `#6366F1` (remaining classes $\times$ rate).
- **Stat Cards:** Display "Total Active Students", "Earned This Cycle", and "Projected Cycle Total" with clean subtle borders (`border-slate-200 dark:border-slate-800`).

### 3.2 Dynamic Checkbox Grid
- **Adaptive Layout:** Responsive grid adapting to 8, 12, 16, or custom class lengths (`grid-cols-4 sm:grid-cols-6 lg:grid-cols-8`).
- **Interactive States:**
  - *Uncompleted:* Subtle outline with class number (`#1`, `#2`).
  - *Completed:* Filled emerald background with checkmark icon and completed date tooltip.
  - *Hover & Focus:* Micro-animations with subtle scale-up on tap/hover.
- **Action Toolbar:** "Start New Cycle" button with confirmation modal when all boxes are checked.

### 3.3 Dynamic Exam Status Badges
- **Status Badges:**
  - `Scheduled`: Slate gray pill (`bg-slate-100 text-slate-700 dark:bg-slate-800 dark:text-slate-300`).
  - `Running`: Pulsing emerald badge (`bg-emerald-100 text-emerald-800 dark:bg-emerald-950 dark:text-emerald-300 animate-pulse`).
  - `Submitted`: Indigo badge (`bg-indigo-100 text-indigo-700 dark:bg-indigo-950 dark:text-indigo-300`).
  - `Delayed`: Amber badge (`bg-amber-100 text-amber-800 dark:bg-amber-950 dark:text-amber-300`).
  - `Missed`: Rose/red badge (`bg-rose-100 text-rose-800 dark:bg-rose-950 dark:text-rose-300`).
- **Live Countdown Timer:** Prominent real-time countdown clock in student exam taking view linked to server UTC finish time.