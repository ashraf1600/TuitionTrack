# TuitionTrack সেটআপ গাইড

লাইভ চ্যাট, পুশ নোটিফিকেশন, Google লগইন, ছবি রাখার জায়গা আর ফ্রি ডাটাবেস — কোনটা কোথায় সেট করতে হবে, ধাপে ধাপে।
বাটন আর মেনুর নাম ইংরেজিতে রাখা হয়েছে, কারণ কনসোলগুলোতে সেভাবেই লেখা থাকে।

App এর package name (সব জায়গায় লাগবে): **`app.tuitiontrack.tuitiontrack`**

---

## ১. লাইভ চ্যাট চালু করা (Render)

PR merge করার পর Render এ backend নতুন করে deploy হবে। দুটো জিনিস মিলিয়ে নিন:

1. **Render → tuitiontrack-api → Settings → Start Command** এ এটা থাকতে হবে:
   ```
   uvicorn config.asgi:application --host 0.0.0.0 --port $PORT --workers 1 --proxy-headers --forwarded-allow-ips '*'
   ```
   Service যদি Blueprint (render.yaml) থেকে বানানো হয়ে থাকে, তাহলে এটা নিজে থেকেই বসে যাবে। হাতে বানানো হলে এখানে নিজে বসিয়ে দিন।
2. **Environment** এ `DB_CONN_MAX_AGE` = `0` দিন।
3. **Neon এর pooled connection string ব্যবহার করুন:** Neon → Connect এ "Connection pooling" চালু করে যে লিংক আসে (host এ `-pooler` থাকে), সেটাই `DATABASE_URL` এ বসান। uvicorn প্রতিটা request এ নতুন connection খোলে, pooler সেটা সস্তা রাখে।

**কীভাবে বুঝবেন কাজ করছে:** দুইটা ফোনে (একটা টিচার, একটা স্টুডেন্ট) চ্যাট খুলে মেসেজ পাঠান। সাথে সাথে আসবে, আর লেখার সময় নামের নিচে "লিখছে…" দেখাবে।

> Render free plan এ ১৫ মিনিট কোনো request না এলে সার্ভার ঘুমিয়ে পড়ে। জেগে উঠতে প্রায় এক মিনিট লাগে। App খোলা থাকলে লাইভ কানেকশনের ping সার্ভারকে জাগিয়ে রাখে।

---

## ২. App বন্ধ থাকলেও নোটিফিকেশন (Firebase Cloud Messaging)

FCM পুরোপুরি ফ্রি। Key না দিলেও app চলবে, শুধু তখন খবর আসবে ১৫ মিনিট পরপর ব্যাকগ্রাউন্ড চেকে।

### ২.১ Firebase project আর Android app
1. https://console.firebase.google.com → **Add project**। Google লগইনের জন্য যে Google Cloud project আছে, চাইলে সেটাই বেছে নিতে পারেন।
2. Project এর ভেতরে **Add app → Android** → package name: `app.tuitiontrack.tuitiontrack` → **Register app**।
3. `google-services.json` ডাউনলোড করুন। এই ফাইল repo তে রাখার দরকার নেই, শুধু এর ভেতরের ৪টা মান লাগবে:

| GitHub variable | `google-services.json` এ কোথায় |
|---|---|
| `FIREBASE_API_KEY` | `client[0].api_key[0].current_key` |
| `FIREBASE_APP_ID` | `client[0].client_info.mobilesdk_app_id` |
| `FIREBASE_SENDER_ID` | `project_info.project_number` |
| `FIREBASE_PROJECT_ID` | `project_info.project_id` |

4. GitHub → repo → **Settings → Secrets and variables → Actions → Variables** ট্যাবে এই ৪টা **Variable** বানান। এগুলো গোপন তথ্য না, তাই Secret না বানালেও চলে।
5. নতুন version tag দিন (যেমন `v1.7.0`)। এরপর যে APK বানানো হবে তাতে push চালু থাকবে।

### ২.২ সার্ভারকে পাঠানোর অনুমতি
1. Firebase → ⚙️ **Project settings → Service accounts → Generate new private key** → একটা JSON ফাইল নামবে।
2. ফাইলটা base64 এ বদলান:
   - Windows PowerShell: `[Convert]::ToBase64String([IO.File]::ReadAllBytes("key.json")) | Set-Clipboard`
   - Linux/Mac: `base64 -w0 key.json`
3. Render → tuitiontrack-api → **Environment** → `FCM_SERVICE_ACCOUNT` = (কপি করা লেখাটা) → Save।

⚠️ এই key দিয়ে আপনার project থেকে যে কেউ নোটিফিকেশন পাঠাতে পারবে। তাই এটা কাউকে দেবেন না, আর GitHub এ রাখবেন না।

**কীভাবে বুঝবেন কাজ করছে:** নতুন APK ইনস্টল করুন। স্টুডেন্টের ফোনে app বন্ধ করে টিচারের ফোন থেকে মেসেজ পাঠান। কয়েক সেকেন্ডের মধ্যে নোটিফিকেশন আসবে, শিরোনামে থাকবে "Ashraf Sir"।

> কিছু ফোন (Xiaomi, Realme, Oppo, Vivo) ব্যাটারি বাঁচাতে বন্ধ app এর নোটিফিকেশন আটকে দেয়। স্টুডেন্টদের বলুন Settings → Apps → TuitionTrack → **Autostart চালু** আর **Battery → No restrictions** করে নিতে।

---

## ৩. Google দিয়ে লগইন (Android)

কোড আগে থেকেই আছে। Android এ Google লগইন কাজ করার শর্ত হলো: APK যে key দিয়ে sign করা, সেই key এর SHA-1 Google Cloud এ নিবন্ধিত থাকতে হবে।

1. **একটা স্থায়ী release keystore বানান** (একবারই করতে হবে, আর ফাইলটা নিরাপদে রাখুন। হারালে পুরোনো app এর উপর আপডেট আর বসানো যাবে না):
   ```
   keytool -genkey -v -keystore tuitiontrack.jks -keyalg RSA -keysize 2048 -validity 10000 -alias tuitiontrack
   ```
2. GitHub → **Settings → Secrets and variables → Actions → Secrets** এ এগুলো বানান:
   `ANDROID_KEYSTORE_BASE64` (jks ফাইলের base64), `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS` (`tuitiontrack`), `ANDROID_KEY_PASSWORD`।
3. SHA-1 বের করুন: `keytool -list -v -keystore tuitiontrack.jks -alias tuitiontrack`। অথবা APK build এর log এ "SHA-1 to register with Google" লাইনে পাবেন।
4. https://console.cloud.google.com → **APIs & Services → Credentials → Create credentials → OAuth client ID → Android**
   - Package name: `app.tuitiontrack.tuitiontrack`
   - SHA-1: উপরের মানটা
5. আগের **Web application** client টা রেখে দিন। এর Client ID ই Render এর `GOOGLE_CLIENT_ID`; app আর website দুটোই এটা ব্যবহার করে।
6. **OAuth consent screen → Publish app** চাপুন। "Testing" অবস্থায় থাকলে শুধু test user রা লগইন করতে পারে।
7. নতুন tag দিয়ে APK বানান, তারপর ইনস্টল করে "Continue with Google" চেষ্টা করুন।

> ⚠️ Keystore secret না থাকলে CI প্রতিবার নতুন debug key দিয়ে sign করে। তখন Google লগইন কাজ করবে না, আর পুরোনো app এর উপর নতুন APK বসবে না। এটাই প্রথমে ঠিক করুন।

---

## ৪. প্রোফাইল ছবি আর অন্যান্য ফাইল

Render এর ডিস্ক প্রতি deploy এ মুছে যায়। তাই ছবি (প্রোফাইল ছবি, চ্যাটের ছবি, প্রশ্নের ছবি) রাখতে হবে বাইরের কোনো S3-compatible স্টোরেজে। কোড এখনই যেকোনো S3 সার্ভিসের সাথে কাজ করে, শুধু Render এর Environment এ মানগুলো বসাতে হবে।

**এখনই যাচাই করুন:** app থেকে প্রোফাইল ছবি দিন। তারপর Render এ **Manual Deploy → Clear build cache & deploy** চালান। ছবি তারপরও দেখা গেলে স্টোরেজ ঠিক আছে; হারিয়ে গেলে নিচের ধাপগুলো করুন।

### প্রস্তাব: Cloudflare R2 (১০ GB ফ্রি, ডাউনলোডে কোনো খরচ নেই)
1. Cloudflare → **R2 → Create bucket** → নাম `tuitiontrack-media`।
2. Bucket → **Settings → Public access → R2.dev subdomain → Allow** → যে ঠিকানা দেয় (`pub-xxxx.r2.dev`) সেটা কপি করুন।
3. **R2 → Manage API tokens → Create API token** → অনুমতি দিন **Object Read & Write**, শুধু এই bucket এর জন্য → Access Key ID আর Secret কপি করুন।
4. Render → Environment এ বসান:

| Key | মান |
|---|---|
| `S3_BUCKET` | `tuitiontrack-media` |
| `S3_REGION` | `auto` |
| `S3_ENDPOINT_URL` | `https://<account-id>.r2.cloudflarestorage.com` |
| `S3_PUBLIC_DOMAIN` | `pub-xxxx.r2.dev` |
| `S3_ACCESS_KEY_ID` / `S3_SECRET_ACCESS_KEY` | ধাপ ৩ এর মান |

Supabase Storage ও চলে (render.yaml এ তার উদাহরণ আছে), কিন্তু সেখানে ফ্রি জায়গা মাত্র ১ GB, আর ৭ দিন কেউ ব্যবহার না করলে project pause হয়ে যায়।

---

## ৫. কোন ফ্রি ডাটাবেস সবচেয়ে ভালো?

| সার্ভিস | ফ্রিতে কী পাবেন | সমস্যা | রায় |
|---|---|---|---|
| **Neon** (এখন যেটা চলছে) | প্রতি project এ ১ GB, মাসে ১০০ CU-hour, ৫ মিনিট কাজ না থাকলে নিজে থেকে ঘুমায় | ঘুম ভাঙতে প্রথম request এ একটু দেরি হয়; ব্যাকআপ শুধু ৬ ঘণ্টা পর্যন্ত | ✅ **এটাতেই থাকুন** |
| Supabase | ৫০০ MB DB + ১ GB ফাইল | ৭ দিন ব্যবহার না হলে pause; ব্যাকআপ নেই | চলে, তবে Neon এর চেয়ে কম সুবিধাজনক |
| Render Postgres (free) | ১ GB | **৩০ দিন পর মেয়াদ শেষ**, তারপর data মুছে যায় | ❌ ব্যবহার করবেন না (পুরোনো `tuitiontrack-db` মুছে দিতে পারেন) |

**সবচেয়ে ভালো ফ্রি জোড়া:** Neon (ডাটাবেস) + Cloudflare R2 (ফাইল) + Render free (API) + Firebase (push)।

**নিয়মিত ব্যাকআপ রাখুন**, কারণ ফ্রি প্ল্যানে লম্বা সময়ের ব্যাকআপ নেই। সপ্তাহে একবার:
```
pg_dump "<DATABASE_URL>" -Fc -f tuitiontrack-YYYY-MM-DD.dump
```
ফাইলটা Google Drive এ রেখে দিন।

**পরের মাসে VPS নিলে:** একই কোড VPS এ uvicorn দিয়ে চালানো যাবে। ডাটাবেস আর ফাইল চাইলে Neon/R2 তেই রাখতে পারেন, সেটাই সহজ। VPS এ Postgres বসালে নিজের দায়িত্বে প্রতিদিন ব্যাকআপ নিতে হবে। একাধিক process চালালে Redis বসিয়ে `REDIS_URL` দিতে হবে, যাতে লাইভ মেসেজ সব process এ পৌঁছায়।
