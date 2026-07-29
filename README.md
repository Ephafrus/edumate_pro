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
| **School settings** | The school's own admin or principal maintains its **name, motto, contact details and logo**. The logo is school-wide — it appears in the school switcher for everyone signed in there, and updates live. Suspending a school stays a platform decision, enforced in the rules |
| **School users directory** | One page listing **everybody who joined the school**, grouped into **Staff**, **Parents** (with a child on the roll) and **Applicants** (joined but no enrolled child yet), with search, recent joins, role changes, deactivation and removal |
| **Teacher assignment** | Class teachers and subject teachers are picked from a single list of **active staff plus staff who have been invited but not yet signed in** — assign somebody the moment you add them, and the link completes itself on their first sign-in |
| **Application notes & messages** | The review team leaves **internal notes** on an application and **messages the applicant** directly; messages appear on the parent's application page and can be **emailed** at the same time |
| **Payments** | Parents complete a **payment form** (purpose, method, amount, date, reference) and upload **proof of payment**; admin **approves/rejects** with a note |
| **QR attendance** | Every learner has a **QR code** (parents show it from their dashboard; admin can display/print it). **Teachers and all school staff scan it** — the child's details pop up and they mark **in school (present)** at drop-off or **left school** at pick-up. Each scan is recorded with who/when, the child's live in/out status shows on the parent dashboard, and **parents are emailed on every drop-off and departure**. A name search fallback covers forgotten cards or browsers without a camera |
| **Email notifications (SMTP, no server)** | The **school admin captures the school's SMTP details in-app** (Email settings). All notification email — application status changes, payment reviews, attendance scans, fee receipts and broadcasts — is **sent directly from the app** over SMTP. Every message is logged to a `mailQueue` audit trail; messages composed on web (browsers can't open SMTP sockets) queue in an outbox and auto-send from any staff member's mobile/desktop session |
| **Broadcast messages** | Admin composes **HTML messages** (toolbar editor + live preview) targeted **per learner, per class or per school**. Recipients get an **in-app notification** (bell badge + announcements feed) and the message is **emailed** to every targeted parent |
| **School calendar** | Calendar (month view) with events for the **whole school, a class or all parents**. Admin adds any event; teachers add events for their own classes; parents see school/parent events plus their children's class events |
| **Fees & invoicing** | Admin sets the **annual fee per grade**, split into monthly installments. Enrolling a child lays out the **whole year's invoice schedule**; a new month's invoices are raised when a manager next opens the finance area (invoice ids are deterministic, so it is safe to run repeatedly). Once-off charges are supported alongside tuition |
| **Principal approval** | **Only a principal approves payments** — enforced in the security rules, not just the UI. Office staff record receipts that stay **pending**; a principal's own entry is **approved as it is written**; **bulk approval** clears the queue in one pass |
| **Parent fee account** | **Balance to date**, **monthly installment**, amount paid and the year's total, plus a **reducing-balance statement** of every charge and payment. A payment awaiting approval is shown but never counted as settled. Statements **download as CSV** |
| **Outstanding fees** | Learners in arrears appear on the **admin and principal dashboards**, worst first, with the total owed |
| **Payments** | Parents complete a payment form and upload **proof of payment**; **bulk-upload** of learner payments from a downloadable **CSV template**, staged first and only creating records after approval |
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

### How the first Super Admin actually works

There is no seed script and no magic phone number. On sign-in the app tries
to create `platform/config` naming itself:

```
platform/config
  bootstrapped      true
  firstSuperAdminUid <your uid>
  createdAt         <server timestamp>
```

The rules let **any** signed-in user create that document, but only with
their *own* uid in `firstSuperAdminUid`, and once it exists only a Super
Admin can change it. So the claim is first-come, once-only. Holding the
claim is also the one condition under which `users/{uid}` may set
`superAdmin: true` on itself — that is the whole bootstrap.

The claim is idempotent: if you hold it but the promotion did not finish,
signing in again completes it. It also works for an account that existed
*before* the rules were deployed — sign out and back in.

### If the first sign-in did not make you Super Admin

Check these in order:

1. **Are the rules deployed?** `firebase deploy --only firestore`. Without
   them the claim write is denied and *nobody* can ever become Super Admin.
   This is by far the most common cause. Deploy, then sign out and in again.
2. **Has somebody else already claimed it?** Open `platform/config` in the
   Firestore console and compare `firstSuperAdminUid` with your uid
   (Firebase console → Authentication → Users). A throwaway test number
   signing in first will have taken it.
3. **Did the promotion land?** `users/{your uid}` should have
   `superAdmin: true`. When it does, the sidebar shows a **Platform**
   section (Schools · Users · System log) and home is `/super`.

To set it by hand — console writes bypass the rules, so this always works:

1. Sign in once with the number so `users/{uid}` exists, and copy the uid
   from Firebase console → Authentication → Users.
2. Firestore → create collection `platform`, document id `config`, with
   `bootstrapped` (boolean) `true` and `firstSuperAdminUid` (string) set to
   that uid.
3. Firestore → `users/{uid}` → add `superAdmin` (boolean) `true`.
4. Sign out and sign back in.

The same two edits move the role to a different account. Once you have one
Super Admin, grant the rest in-app from **Platform → Users**; never hand out
Super Admin by editing the console again.

Note that Super Admin is a **platform** flag on `users/{uid}`, not a school
membership — a Super Admin holds no member document anywhere, which is why
the rules give them an explicit bypass on school-scoped data.

### How staff become staff (and why it used to fail)

Staff are added by phone number, before they have an account:

1. An admin adds them under **Staff**, creating a `staffInvites` document.
2. They sign in with that number. The app finds the invite, writes their
   `schools/{id}/members/{uid}` document with the invited role, marks the
   invite claimed, and completes any class or subject that was assigned to
   the invite.

Step 2 is a write the person makes **about themselves**, so the rules have to
be able to prove they really were invited — at that school, in that role.
Rules cannot run a query, only fetch a document by id, so invites live at a
**derivable id**: `{schoolId}_{phoneE164}`. Without that, the membership write
is refused, the teacher lands on "choose a school", and joining from there
writes them in as a **parent** — which is exactly how invited teachers ended
up with the wrong role.

Practical consequences:

* The number on the invite must match the number they sign in with, exactly.
  The Add-staff form shows the normalised E.164 it will store, and the pending
  invite list repeats it — check it against what they actually use.
* Re-inviting the same number to the same school overwrites the invite rather
  than stacking duplicates.
* **Invites created before this change have random ids and cannot be
  verified.** Cancel and re-add anyone still listed as pending, or they will
  keep falling through to a parent account.
* If somebody is added while already signed in, they do not need to sign out:
  "choose a school" re-checks for invites on open and has a manual re-check.

`joinSchoolAsParent` also refuses to downgrade an existing staff membership,
so the join screen can no longer clobber a role.

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

## Email from the web portal

A browser cannot open a socket to a mail server, so **SMTP never works on the
web** — messages queue in the outbox and go out when somebody opens the mobile
or desktop app. If the school runs on the web portal, configure an **HTTPS
relay** instead under *Email settings*: an endpoint the school owns that
receives a message and sends it, which a browser *can* call.

`docs/email-relay.md` has a Google Apps Script relay you can paste in, the
JSON contract, the CORS headers a custom endpoint needs, and why a provider's
API key must not simply be embedded in the app.

*Send test email* reports what actually happened — a 401, a CORS refusal, a
timeout, or the provider's own error text — rather than a generic failure.

## Security-rules tests

`flutter test` cannot exercise Firestore rules, so they have their own suite
run against the emulator (requires Java):

```bash
cd test/rules
npm install
npm test
```

It covers the staff-invite claim path — that an invited teacher can write
their own membership, and that nobody can use it to grant themselves a role.

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
