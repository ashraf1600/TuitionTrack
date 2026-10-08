# TuitionTrack — Render Deployment Guide (DB + Backend + Frontend)

This guide walks you through deploying the complete TuitionTrack stack directly on **[Render](https://render.com/)**:
1. **Render PostgreSQL Database** (`tuitiontrack-db`)
2. **Django REST API Backend** (`tuitiontrack-api`)
3. **React + Vite Web Frontend** (`tuitiontrack-web`)

---

## 💡 About Render's PostgreSQL Database

When hosting the database on Render:
- **Private Networking**: The Django backend communicates with the PostgreSQL database over Render's high-speed private internal network (no external internet latency).
- **Free Tier Note**: Render offers a **Free tier** for PostgreSQL databases (1 GB storage), which **expires after 30 days**. This is great for demos, testing, and evaluation.
- **Permanent Database**: If you need the database to run permanently without the 30-day expiration, you can upgrade the database on Render to the **Starter plan** ($7/mo), OR you can point `DATABASE_URL` to a free permanent provider like [Supabase](https://supabase.com) or [Neon](https://neon.tech).

---

## 🚀 Deployment Options

You can deploy using either:
1. **[Method 1: Render Blueprint (Recommended — 100% Automated)](#method-1-deploy-using-render-blueprint-recommended)**
2. **[Method 2: Manual Dashboard Setup](#method-2-manual-dashboard-setup)**

---

## Method 1: Deploy Using Render Blueprint (Recommended)

TuitionTrack includes a pre-configured [render.yaml](file:///d:/Django_The_Last_Hope_Phitron/TuitionTrack/render.yaml) blueprint that automatically provisions the **PostgreSQL Database**, **Django Backend**, and **React Frontend** all together and connects them automatically.

### Step 1: Push your code to GitHub
```bash
git add .
git commit -m "Configure Render for DB, Frontend, and Backend"
git push origin <your-branch>
```

### Step 2: Launch the Blueprint in Render
1. Log in to [dashboard.render.com](https://dashboard.render.com/).
2. Click **New +** → **Blueprint**.
3. Connect your **TuitionTrack** repository.
4. Render will inspect `render.yaml` and show the 3 resources it will create:
   - `tuitiontrack-db` (PostgreSQL Database)
   - `tuitiontrack-api` (Django Web Service)
   - `tuitiontrack-web` (React Static Site)
5. Review the pre-configured parameters:
   - `DATABASE_URL` is **automatically wired** to `tuitiontrack-db` via Render's internal network.
   - `FRONTEND_URL` defaults to `https://tuitiontrack-web.onrender.com`.
   - `VITE_API_URL` defaults to `https://tuitiontrack-api.onrender.com`.
6. Click **Apply**.
   - Render will provision the PostgreSQL database.
   - Render will build and deploy the Django backend (running migrations automatically).
   - Render will build and deploy the React frontend.

---

## Method 2: Manual Dashboard Setup

If you prefer to configure each component individually in the Render dashboard:

### Step 1: Create the Render PostgreSQL Database
1. Click **New +** → **PostgreSQL**.
2. Configure settings:
   - **Name**: `tuitiontrack-db`
   - **Database**: `tuitiontrack`
   - **User**: `tuitiontrack`
   - **Region**: `Singapore` (or choose the region closest to your users)
   - **Plan**: `Free` (or `Starter` for permanent storage)
3. Click **Create Database**.
4. Once created, stay on the database page and find **Internal Database URL** under the **Connections** panel. Copy this URL (it starts with `postgres://...` or `postgresql://...`).

---

### Step 2: Deploy Django Backend (`tuitiontrack-api`)
1. Click **New +** → **Web Service**.
2. Connect your GitHub repository.
3. Configure the service settings:
   - **Name**: `tuitiontrack-api`
   - **Region**: `Singapore` *(must match your database region)*
   - **Root Directory**: `backend`
   - **Runtime**: `Python 3`
   - **Build Command**: `bash build.sh`
   - **Start Command**: `gunicorn config.wsgi:application --bind 0.0.0.0:$PORT --workers 2 --timeout 60`
   - **Plan**: `Free`
4. Expand **Advanced** and set:
   - **Health Check Path**: `/api/v1/meta/`
5. Under **Environment Variables**, add:
   | Key | Value | Notes |
   |---|---|---|
   | `PYTHON_VERSION` | `3.11.11` | Ensures Python 3.11 runtime |
   | `DEBUG` | `False` | Production mode |
   | `SECRET_KEY` | *(Click "Generate")* | Or any secure 50+ character random string |
   | `DATABASE_URL` | *(Paste Internal Database URL from Step 1)* | Render internal connection string |
   | `DISPLAY_TIME_ZONE` | `Asia/Dhaka` | Timezone for notifications/exam schedule |
   | `REFRESH_TOKEN_LIFETIME_DAYS` | `30` | JWT refresh duration |
   | `FRONTEND_URL` | `https://tuitiontrack-web.onrender.com` | Deployed frontend origin |
6. Click **Create Web Service**.

---

### Step 3: Deploy React Frontend (`tuitiontrack-web`)
1. Click **New +** → **Static Site**.
2. Connect your GitHub repository.
3. Configure the settings:
   - **Name**: `tuitiontrack-web`
   - **Root Directory**: `frontend`
   - **Build Command**: `rm -f package-lock.json && npm install --include=optional && npm run build`
   - **Publish Directory**: `dist`
4. Under **Redirects/Rewrites**:
   - **Type**: `Rewrite`
   - **Source**: `/*`
   - **Destination**: `/index.html`
   *(Crucial: ensures React Router client-side routes like `/dashboard` work when refreshed)*
5. Under **Environment Variables**, add:
   | Key | Value |
   |---|---|
   | `NODE_VERSION` | `22.14.0` |
   | `VITE_API_URL` | `https://tuitiontrack-api.onrender.com` *(or your actual backend service URL)* |
6. Click **Create Static Site**.

---

## 👤 Creating the Django Superuser / Admin

On Render's Free tier, SSH terminal access is disabled. To create an admin account, choose any of these simple approaches:

### Option A: Set Environment Variables on `tuitiontrack-api`
In your backend service's **Environment** tab on Render, add:
- `DJANGO_SUPERUSER_USERNAME` = `admin`
- `DJANGO_SUPERUSER_PASSWORD` = `YourSecurePassword123`
- `DJANGO_SUPERUSER_EMAIL` = `admin@example.com`

During the next deploy (or click **Manual Deploy** → **Deploy latest commit**), `build.sh` automatically runs `createsuperuser` without failing.

### Option B: Run locally against the remote database
From your local PC terminal, you can run migrations or createsuperuser pointing to your live cloud database:
```bash
cd backend
python manage.py createsuperuser --database default
# When DATABASE_URL in your local .env is set to your Supabase/cloud database
```

Once created, log in to the admin panel at:
`https://tuitiontrack-api.onrender.com/admin/`

---

## 🖼️ File Uploads & Media Storage (Optional)

On Render's free tier, the server disk is ephemeral (wiped on every new deploy/restart).
For persistent uploads (question paper photos, student answer sheets):

1. In Supabase: **Storage** → Create a **Public bucket** named `tuitiontrack-media`.
2. In Supabase: **Project Settings** → **Storage** → Generate **S3 Access Keys**.
3. In Render backend service **Environment Variables**, add:
   - `S3_BUCKET`: `tuitiontrack-media`
   - `S3_REGION`: `ap-southeast-1`
   - `S3_ENDPOINT_URL`: `https://<project-ref>.storage.supabase.co/storage/v1/s3`
   - `S3_PUBLIC_DOMAIN`: `<project-ref>.supabase.co/storage/v1/object/public/tuitiontrack-media`
   - `S3_ACCESS_KEY_ID`: `<access-key>`
   - `S3_SECRET_ACCESS_KEY`: `<secret-key>`

If these are not set, TuitionTrack automatically uses local media storage.

---

## 📱 Connecting the Flutter Mobile App

Once deployed, point your Flutter mobile app to your Render backend:
In `mobile/lib/`:
Set your API base URL to:
```dart
https://tuitiontrack-api.onrender.com
```

---

## 🔍 Verification Checklist

- [x] `backend/build.sh` runs `collectstatic`, `migrate`, and optional `createsuperuser`
- [x] WhiteNoise configured for instant, zero-configuration admin static asset serving
- [x] `render.yaml` configured with free plan, Singapore region, and health check
- [x] `frontend/vite.config.js` and `frontend/src/api/client.js` support dynamic backend origins
- [x] CORS and CSRF configurations pre-allow all `*.onrender.com` subdomains
- [x] Client-side SPA routing rewrite (`/* -> /index.html`) configured
