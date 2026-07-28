# EduMate Pro

A cross-platform (Web · Android · iOS) **school management platform** connecting
**teachers, parents and school admin**, built with **Flutter** and **Firebase**.
Parents apply online for their children with a step-by-step enrollment form and
track progress; admin manages staff, learners, classes and payment approvals;
staff chat in-app, and parents can request a teacher chat that admin approves.

---

## Features

| Area | What's implemented |
|------|--------------------|
| **Roles** | School admin, Teacher, Parent — role-based navigation & route guards |
| **Auth** | **Firebase Phone Auth for everyone**: sign in with a cell number + SMS one-time code (country picker + segmented OTP input). New numbers become parent accounts; staff numbers (pre-added by admin) become teacher/admin accounts automatically on first sign-in |
| **Profiles** | Every authenticated user is presented with **Create a profile** (name + email + address) — for parents this unlocks *Apply for a child*, and the email receives school notifications |
| **Enrollment applications** | Modern, responsive **step-by-step wizard**: Learner details → Parent/guardian → Medical & emergency → Supporting documents (uploads) → Review & submit. Drafts auto-save per step and can be resumed |
| **Application tracking** | Status pipeline *Submitted → Under review → Accepted → Enrolled* (or *Rejected* with a reason), each change recorded on a visible timeline for the parent |
| **Enrollment** | Accepting + enrolling an application atomically creates the **learner record** and links it to the applying parent |
| **Admin management** | Add **teachers** (phone-number invites), add/edit **learners**, create **classes**, **assign learners to classes**, **link learners to parents** |
| **Payments** | Parents complete a **payment form** (purpose, method, amount, date, reference) and upload **proof of payment**; admin **approves/rejects** with a note |
| **Email notifications (SMTP)** | Cloud Functions + **nodemailer** send email to parents on every application status change and payment review, via a `mailQueue` collection with an audit trail |
| **In-app chat** | **Staff ↔ staff** chat works immediately. **Parents request a chat with a teacher**; the request (with reason + learner) goes to admin, and messaging unlocks only once **admin approves** |
| **Teacher flow** | My classes → class register of assigned learners; staff chat |
| **Theming** | User-configurable palette + light/dark, persisted locally |
| **Responsive** | Adapts across mobile / tablet / desktop; inline nav on wide screens, drawer on mobile |

## Project structure

```
lib/
  core/         constants (grades, languages, provinces), theme, responsive, SA ID validation
  models/       user & staff invites, classes/learners, applications, payments, chat
  services/     auth (phone OTP), firestore, storage
  state/        AuthController, ThemeController (Provider/ChangeNotifier)
  router/       go_router config + role-based redirect guards
  widgets/      responsive AppShell, phone auth form, upload button, shared UI
  screens/      common · auth · parent · teacher · admin · chat
functions/      Cloud Functions — SMTP email notifications (nodemailer)
firestore.rules / storage.rules   security rules
```

## Prerequisites

- Flutter SDK **3.35+** (Dart 3.9+)
- A Firebase project
- The [FlutterFire CLI](https://firebase.flutter.dev/docs/cli/): `dart pub global activate flutterfire_cli`

## Firebase setup

1. Create a Firebase project in the [console](https://console.firebase.google.com/).
2. Enable the **Phone** Authentication provider (everyone signs in by phone).
3. Create **Cloud Firestore** and **Cloud Storage**.
4. Generate the real config:
   ```bash
   flutterfire configure
   ```
   This writes `lib/firebase_options.dart` plus `android/app/google-services.json`
   and the iOS plist. **`lib/firebase_options.dart` is git-ignored** (it's
   per-environment and must not be committed). A tracked template lives at
   `lib/firebase_options.dart.example` — to make the app compile before
   configuring, copy it first:
   ```bash
   cp lib/firebase_options.dart.example lib/firebase_options.dart
   ```
5. Deploy the security rules and indexes:
   ```bash
   firebase deploy --only firestore,storage
   ```
6. **Bootstrap the first School Admin:** sign in once in the app with the
   admin's phone number (this creates a parent account), then in Firestore edit
   `users/{uid}` → set `"role": "admin"`. From then on that admin adds further
   staff **inside the app** (Staff → *Add staff member*), which pre-provisions
   their phone number — no console needed again.

## Phone authentication (SMS) setup

Everyone signs in by phone (OTP). **A brand-new Firebase project will not send
SMS until you allow the destination region** — you'll otherwise see *"SMS
unable to be sent until this region enabled…"*. This is a Firebase Console
setting, not an app bug:

1. **Enable the Phone provider:** Firebase Console → **Authentication → Sign-in
   method → Phone → Enable**.
2. **Allow your SMS regions:** Authentication → **Settings → SMS region policy**
   → either *Allow all* or add the regions you serve (e.g. **South Africa /
   +27**).
3. **Add test phone numbers (recommended for development):** Authentication →
   Sign-in method → Phone → **Phone numbers for testing** — add a number + a
   fixed code so you can develop without real SMS or billing.
4. **Billing:** real SMS beyond the free test tier requires the **Blaze
   (pay-as-you-go)** plan.
5. **Platform prerequisites for real SMS:**
   - **Web:** add your domain under Authentication → Settings → **Authorized
     domains**; reCAPTCHA runs automatically.
   - **Android:** add your app's **SHA-1 & SHA-256** fingerprints in Project
     settings and enable **Play Integrity / SafetyNet**.
   - **iOS:** configure **APNs** and the app's URL scheme (see the FlutterFire
     phone-auth docs).

The app surfaces the region error with a clear message pointing here, so if OTP
isn't arriving, start with steps 1–2 above.

## SMTP email notifications (Cloud Functions)

Parent notifications (application status changes, payment approvals, admin
notices) are sent **over SMTP** by Cloud Functions in
[`functions/`](functions), so SMTP credentials never ship in the app:

```bash
cd functions && npm install && cd ..

# SMTP password is a secret:
firebase functions:secrets:set SMTP_PASSWORD

# Host/port/username/from are params — you're prompted on first deploy and the
# values are saved to functions/.env, e.g.:
#   SMTP_HOST=smtp.yourprovider.com
#   SMTP_PORT=587
#   SMTP_USERNAME=no-reply@yourschool.co.za
#   SMTP_FROM="EduMate Pro <no-reply@yourschool.co.za>"
firebase deploy --only functions
```

Any SMTP provider works (your school's mail host, SendGrid SMTP, Gmail/Workspace
with an app password, Mailgun, …). Port 465 is treated as SMTPS; 587 uses
STARTTLS.

**How it works:** every email is a doc in the `mailQueue` collection
(`{to, subject, text}`); the `processMailQueue` function sends it and stamps
the outcome (`sent` / `error`) on the doc, giving you an audit trail in
Firestore. The `onApplicationStatusChange` and `onPaymentReviewed` triggers
queue the parent-facing emails automatically.

> The app runs with the placeholder config but shows a "Firebase is not
> configured" screen until setup step 4 is done.

## Run

```bash
flutter pub get

flutter run -d chrome     # Web
flutter run -d android    # Android device/emulator
flutter run -d ios        # iOS simulator/device (macOS)
```

## Build

```bash
flutter build web
flutter build apk        # or: flutter build appbundle
flutter build ios        # macOS + Xcode
```

## Deploy the web app (Firebase Hosting)

Hosting is pre-configured in `firebase.json` (`public: build/web`, SPA rewrite).

```bash
npm install -g firebase-tools
firebase login
firebase use --add            # pick your project

flutter build web --release
firebase deploy --only hosting
# …or everything together:
firebase deploy --only hosting,firestore,storage,functions
```

The site goes live at `https://<project-id>.web.app`. **After deploying:** add
your hosting domain(s) under **Authentication → Settings → Authorized domains**
so phone sign-in works there.

## Test & analyze

```bash
flutter analyze
flutter test
```

## How the main flows fit together

1. **Parent journey:** sign in with phone → create profile → *Apply for a
   child* (5-step wizard, uploads, auto-saved drafts) → track the status
   timeline + receive emails → once enrolled, the child appears under *My
   children* → submit payments with proof → request a teacher chat.
2. **Admin journey:** dashboard badges show what needs attention → review
   applications (start review / accept / reject with reason / **enroll**,
   which creates the learner) → assign learners to classes and link parents →
   approve payments → approve parent-teacher chat requests → add staff by
   phone number.
3. **Teacher journey:** see assigned classes and their learner registers →
   staff chat → chat with parents once admin approves the request.

## Known gaps / next steps

Tracked in [`REQUIREMENTS.md`](REQUIREMENTS.md). Highlights: attendance and
report cards are out of scope for this iteration; payments are proof-of-payment
based (no card gateway); notifications are email-only (no push yet); and chat
has no unread badges/typing indicators.
