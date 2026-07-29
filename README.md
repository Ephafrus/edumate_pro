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
| **System log (audit trail)** | Every interaction is recorded to an **append-only** `activityLogs` trail — sign-ins, opening the enrollment application, submissions, status changes, attendance scans, payments, broadcasts, academics and admin actions. A **Super Admin reviews the whole platform's activity** in one filterable feed; nobody (including Super Admins) can edit or delete an entry |
| **Super Admin school oversight** | From the console, **sign in to any school** and run it exactly as its admin would — learners, classes, applications, payments, fees, settings. A persistent banner shows which school you are inside with a one-tap exit, and both entering and leaving are recorded in the system log |
| **User directory** | Super Admin sees **every account**, searches by name/phone/email, filters to people not yet in a school, and **assigns them to a school with a role** — the change reaches that person's app immediately, no re-login |
| **First-run setup** | The **first person to sign in on a fresh deployment automatically becomes Super Admin** (an atomic one-time claim), so a new install is usable straight away. Everyone after that is a **Parent** unless a Super Admin assigns them admin/principal or a school admin invites them as a teacher |
| **Multi-school platform** | A **Super Admin** sets schools up and assigns each school's **admins/principals**. Every school's data lives under `schools/{id}/…` and is fully isolated. Anyone assigned to **more than one school** (admin, principal or teacher) sees them all and switches with one tap from the app bar |
| **Roles** | Super Admin (platform) · School admin · Principal · Teacher · Parent — role-based navigation & route guards, enforced in security rules |
| **Subjects & academics** | Admin adds **subjects to a class** and assigns the teacher. Teachers create **assessments** and capture **marks per learner per subject** on a batch mark sheet |
| **Progress reports** | Per-subject averages, trend and symbols — a school-wide view for admin (class by class) and a **child-progress dashboard for parents** |
| **Lesson plans & homework** | Teachers publish **dated lesson plans** (day or date range) and set **homework with due dates** plus optional uploaded worksheets; parents see both on their child's page |
| **Search** | Role-scoped search: Super Admin finds schools; admins/principals find learners, classes, subjects, staff, parents and applications; teachers find their own classes, subjects and learners |
| **Auth** | **Firebase Phone Auth for everyone**: sign in with a cell number + SMS one-time code (country picker + segmented OTP input). New numbers become parent accounts; staff numbers (pre-added by admin) become teacher/admin accounts automatically on first sign-in |
| **Profiles** | Every authenticated user is presented with **Create a profile** (name + email + address) — for parents this unlocks *Apply for a child*, and the email receives school notifications |
| **Enrollment applications** | Modern, responsive **step-by-step wizard**: Learner details → Parent/guardian → Medical & emergency → Supporting documents (uploads) → Review & submit. Drafts auto-save per step and can be resumed |
| **Application tracking** | Status pipeline *Submitted → Under review → Accepted → Enrolled* (or *Rejected* with a reason), each change recorded on a visible timeline for the parent |
| **Enrollment** | Accepting + enrolling an application atomically creates the **learner record** and links it to the applying parent |
| **Admin management** | Add **teachers** (phone-number invites), add/edit **learners**, create **classes**, **assign learners to classes**, **link learners to parents** |
| **School users directory** | One page listing **everybody who joined the school**, grouped into **Staff**, **Parents** (with a child on the roll) and **Applicants** (joined but no enrolled child yet), with search, recent joins, role changes, deactivation and removal |
| **Teacher assignment** | Class teachers and subject teachers are picked from a single list of **active staff plus staff who have been invited but not yet signed in** — assign somebody the moment you add them, and the link completes itself on their first sign-in |
| **Application notes & messages** | The review team leaves **internal notes** on an application and **messages the applicant** directly; messages appear on the parent's application page and can be **emailed** at the same time |
| **Payments** | Parents complete a **payment form** (purpose, method, amount, date, reference) and upload **proof of payment**; admin **approves/rejects** with a note |
| **QR attendance** | Every learner has a **QR code** (parents show it from their dashboard; admin can display/print it). **Teachers and all school staff scan it** — the child's details pop up and they mark **in school (present)** at drop-off or **left school** at pick-up. Each scan is recorded with who/when, the child's live in/out status shows on the parent dashboard, and **parents are emailed on every drop-off and departure**. A name search fallback covers forgotten cards or browsers without a camera |
| **Email notifications (SMTP, no server)** | The **school admin captures the school's SMTP details in-app** (Email settings). All notification email — application status changes, payment reviews, attendance scans, fee receipts and broadcasts — is **sent directly from the app** over SMTP. Every message is logged to a `mailQueue` audit trail; messages composed on web (browsers can't open SMTP sockets) queue in an outbox and auto-send from any staff member's mobile/desktop session |
| **Broadcast messages** | Admin composes **HTML messages** (toolbar editor + live preview) targeted **per learner, per class or per school**. Recipients get an **in-app notification** (bell badge + announcements feed) and the message is **emailed** to every targeted parent |
| **School calendar** | Calendar (month view) with events for the **whole school, a class or all parents**. Admin adds any event; teachers add events for their own classes; parents see school/parent events plus their children's class events |
| **Fees** | Admin **configures fee structures** (per grade/year), sees **learners with outstanding fees**, **records office payments** (with optional emailed receipt), and **bulk-uploads learner payments** from a downloadable **CSV template** — uploads are **staged first** and only create payment records after review & approval |
| **In-app chat** | **Staff ↔ staff** chat works immediately. **Parents request a chat with a teacher**; the request (with reason + learner) goes to admin, and messaging unlocks only once **admin approves** |
| **Home banner** | Every signed-in user's home opens with a **colourful gradient banner**: a time-of-day greeting, their **latest messages**, and up to **3 upcoming events** (sections hide when empty) |
| **Teacher flow** | My classes → class register of assigned learners; staff chat |
| **Theming & customisation** | Modern, colourful Material 3 design (vibrant scheme, gradient hero surfaces, rounded components). Each user **customises their own app**: school colour palette, light/dark/system mode and text size — persisted locally |
| **Responsive** | Adapts across mobile / tablet / desktop; inline nav on wide screens, drawer on mobile |

## Project structure

```
lib/
  core/         constants (grades, languages, provinces), theme, responsive, SA ID validation
  models/       users & memberships, schools, classes/learners, subjects,
                academics (assessments, marks, lesson plans, homework),
                applications, payments/fees, chat, broadcasts, calendar
  services/     auth (phone OTP), firestore, storage
  state/        AuthController, ThemeController (Provider/ChangeNotifier)
  router/       go_router config + role-based redirect guards
  widgets/      responsive AppShell, phone auth form, upload button, shared UI
  screens/      common · auth · superadmin · admin · teacher · parent · chat · staff
docs/status-report.html   project/deliverable status report
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
6. **Sign in — that's it.** The **first** person to sign in on a fresh
   deployment automatically becomes the platform **Super Admin** (they claim
   `platform/config`, which can only ever be claimed once). No console
   editing needed. From there the Super Admin creates schools and assigns
   admins/principals from the in-app **Users** directory, and those admins
   add teachers themselves. Everyone else who signs up is a **Parent** by
   default. Assignments take effect immediately — the recipient's app is
   watching their memberships live.

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

## SMTP email notifications (no server needed)

There are **no Cloud Functions** — the school admin sets the SMTP details up
inside the app: **Dashboard → Email settings** (host, port, username,
password/app password, from name & address), then *Save & send test*. Any SMTP
provider works (the school's mail host, Gmail/Workspace with an app password,
SendGrid SMTP, Mailgun, …). Port 465 is used as SMTPS; 587 as STARTTLS.

Email is then sent **directly from the app** wherever it's triggered:
application status changes, payment reviews, fee receipts, attendance scans
and broadcasts. Every message is logged to the `mailQueue` collection
(`sent` / `pending` / `error`) as an audit trail.

**Web note:** browsers cannot open SMTP connections, so email triggered from
the web app is queued in the outbox and delivered automatically the next time
any staff member opens the app on Android/iOS/desktop (or taps *Send outbox
now* under Email settings).

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
firebase deploy --only hosting,firestore,storage
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
   **scan learner QR codes at the gate** (drop-off / pick-up) → staff chat →
   chat with parents once admin approves the request.
4. **Attendance:** parent shows the child's QR (dashboard → tap the child) →
   any staff member scans it (`Scan` in the nav), checks the details, and
   marks *in school* or *left school* → the event is logged and every linked
   parent is emailed immediately.
5. **Broadcasts:** admin → Broadcasts → *New broadcast* → pick the
   destination (learner / class / school), write the HTML message, send →
   parents' bells light up in-app and the message lands in their inbox.
6. **Fees:** admin → Fees → configure structures → *Outstanding* shows who
   still owes → record office payments directly, or *Download template CSV*,
   fill in the amounts, upload → review the staged rows → approve to create
   the payment records.

## Known gaps / next steps

Tracked in [`REQUIREMENTS.md`](REQUIREMENTS.md). Highlights: report cards and
homework are out of scope for this iteration; payments are proof-of-payment
based (no card gateway); broadcast notifications are in-app + email (true FCM
push needs a server component, which this serverless design deliberately
avoids); and chat has no unread badges/typing indicators.
