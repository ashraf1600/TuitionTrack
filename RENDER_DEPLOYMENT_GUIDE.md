# TuitionTrack — Render Deployment Guide

This guide walks you through deploying both the **Django REST API** (`backend`) and the **React + Vite Web App** (`frontend`) to **[Render](https://render.com/)**.

---

## 🚀 Deployment Options

You can deploy using either:
1. **[Method 1: Render Blueprint (Recommended — 2 minutes)](#method-1-deploy-using-render-blueprint-recommended)**
2. **[Method 2: Manual Dashboard Setup](#method-2-manual-dashboard-setup)**

---

## 🗄️ Step 0: Get a Free PostgreSQL Database

Render free tier web services do not have persistent local storage, so an external or managed PostgreSQL database is required.

### Recommended: Supabase (Free & Never Expires)
1. Go to [supabase.com](https://supabase.com) and create a project (choose the **Singapore** region for lowest latency to Bangladesh/South Asia).
2. Go to **Project Settings** → **Database** → **Connection string**.
3. Under **Connection pooling**, choose **Session pooler** (port `5432` or `6543`, IPv4 compatible).
4. Copy your URI. It looks like:
   ```
   postgresql://postgres.[project-ref]:[YOUR-PASSWORD]@aws-0-ap-southeast-1.pooler.supabase.com:5432/postgres
   ```
*(Alternative: You can also use [Neon.tech](https://neon.tech/) or create a Render PostgreSQL instance).*

---

## Method 1: Deploy Using Render Blueprint (Recommended)

TuitionTrack includes a pre-configured [render.yaml](file:///d:/Django_The_Last_Hope_Phitron/TuitionTrack/render.yaml) blueprint that sets up both services automatically.

1. **Push your code to GitHub**:
   ```bash
   git add .
   git commit -m "Ready project for Render deployment"
   git push origin <your-branch>
   ```

2. **Open Render**:
   - Log in to [dashboard.render.com](https://dashboard.render.com/).
   - Click **New +** → **Blueprint**.
   - Connect your **TuitionTrack** repository.

3. **Configure the Parameters**:
   Render will inspect `render.yaml` and prompt you for:
   - **`DATABASE_URL`**: Paste your Supabase or Neon PostgreSQL connection string.
   - **`FRONTEND_URL`**: Defaults to `https://tuitiontrack-web.onrender.com`.
   - **`VITE_API_URL`**: Defaults to `https://tuitiontrack-api.onrender.com`.

4. **Click "Apply"**:
   - Render will build and deploy both:
     - `tuitiontrack-api` (Django Backend Web Service)
     - `tuitiontrack-web` (React Single Page Static Site)

---

## Method 2: Manual Dashboard Setup

If you prefer to configure each service individually in the Render UI:

### Part A: Deploy Django Backend (`tuitiontrack-api`)
1. Click **New +** → **Web Service**.
2. Connect your GitHub repository.
3. Configure the service settings:
   - **Name**: `tuitiontrack-api`
   - **Region**: `Singapore` (or match your database region)
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
   | `SECRET_KEY` | *(Click "Generate")* | Or any secure 50+ char random string |
   | `DATABASE_URL` | `postgresql://...` | Your Supabase/Neon connection string |
   | `DISPLAY_TIME_ZONE` | `Asia/Dhaka` | Timezone for notifications/exam schedule |
   | `REFRESH_TOKEN_LIFETIME_DAYS` | `30` | JWT refresh duration |
   | `FRONTEND_URL` | `https://tuitiontrack-web.onrender.com` | Deployed frontend origin |
6. Click **Create Web Service**.

---

### Part B: Deploy React Frontend (`tuitiontrack-web`)
1. Click **New +** → **Static Site**.
2. Connect your GitHub repository.
3. Configure the settings:
   - **Name**: `tuitiontrack-web`
   - **Root Directory**: `frontend`
   - **Build Command**: `npm install && npm run build`
   - **Publish Directory**: `dist`
4. Under **Redirects/Rewrites**:
   - **Type**: `Rewrite`
   - **Source**: `/*`
   - **Destination**: `/index.html`
   *(This ensures React Router routes like `/dashboard` work when refreshed)*
5. Under **Environment Variables**, add:
   | Key | Value |
   |---|---|
   | `NODE_VERSION` | `20.18.0` |
   | `VITE_API_URL` | `https://tuitiontrack-api.onrender.com` *(use your backend URL)* |
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
