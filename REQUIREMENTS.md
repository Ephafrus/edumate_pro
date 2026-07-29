# EduMate Pro — Requirements

**Project:** EduMate Pro — a single school management platform connecting
**teachers, parents and school admin**.

**Stack:** Flutter (Web, Android, iOS) · Firebase Phone Auth · Cloud Firestore ·
Cloud Storage. **No server component** — SMTP email is sent directly from the
app using school-configured settings.

---

## 1. Roles

| Role | Summary |
|------|---------|
| **Super Admin** | Platform level: creates schools and assigns the admins/principals who run each one |
| **Principal** | Leads a school; same management rights as the school admin |
| **School admin** | Runs the school: staff, learners, classes, subjects, applications, payments, fees, chat approvals |
| **Teacher** | Sees assigned classes and learners; chats with staff and approved parents |
| **Parent** | Applies for children, tracks applications, submits payments, requests teacher chats |

## 2. Functional requirements

### System activity log (FR-43…FR-45)
- **FR-43** Every meaningful interaction is written to an **append-only**
  `activityLogs` trail: sign-in/out, profile creation, school join/switch,
  **opening the enrollment application**, application saves/submissions and
  status changes, learner/class/subject changes, marks, lesson plans,
  homework, attendance scans, payments and fee actions, broadcasts, chat,
  calendar events, staff invites and assignments, and platform actions.
- **FR-44** Only a **Super Admin** can read the feed; it is filterable by
  category and searchable by person, school or target. Nobody — including
  Super Admins — can edit or delete an entry (enforced in rules).
- **FR-45** Logging is fire-and-forget: a failed log write never blocks or
  breaks the user action it describes.

### Platform bootstrap & user directory (FR-46…FR-48)
- **FR-46** The **first user to sign in** on an empty deployment atomically
  claims the platform and becomes its **Super Admin**, so a fresh install is
  immediately usable without console edits.
- **FR-47** Every subsequent sign-up is a **Parent** by default, unless a
  Super Admin has assigned them an admin/principal role or a school admin
  has invited them as a teacher.
- **FR-48** The Super Admin has a **user directory**: all accounts, search
  by name/phone/email, a filter for people not yet in a school, one-tap
  assignment to a school with a role, membership removal, and granting or
  revoking Super Admin. Assignments apply **live** — the recipient's app
  subscribes to their memberships, so a promoted user sees the school
  without signing out.

### Super Admin school oversight (FR-49)
- **FR-49** A Super Admin can **sign in to any school** from the console and
  use its full admin area, without holding a membership there. The mode is
  visible at all times (banner + exit), audited on entry and exit, and
  backed by security rules that grant Super Admins access to every school's
  data.

### Multi-school platform (FR-33…FR-36)
- **FR-33** A **Super Admin** creates a school (name, address, contacts) and
  can suspend it.
- **FR-34** The Super Admin **assigns an admin or principal** to a school by
  phone number — granted immediately if that person already has an account,
  otherwise as an invitation that activates on their first sign-in.
- **FR-35** All school data is stored under `schools/{schoolId}/…`; access
  requires a membership at that school, checked in security rules.
- **FR-36** A person may belong to **several schools**, with a different role
  at each. Admins, principals and teachers see every school they are assigned
  to and switch between them from the app bar; parents may join more than one
  school if their children attend different schools.

### Subjects & academics (FR-37…FR-41)
- **FR-37** A school admin **creates classes, adds subjects** to them and
  assigns the teacher for each subject.
- **FR-38** Teachers sign in and see **their own classes and subjects**.
- **FR-39** Teachers create assessments (title, term, total, date) and
  **capture marks per learner per subject** on a batch mark sheet;
  re-capturing overwrites cleanly.
- **FR-40** **Progress reports**: per-subject averages, trend and symbol
  bands — school-wide for admin (class by class) and per child for parents.
- **FR-41** Teachers publish **dated lesson plans** and set **homework with
  due dates** and optional uploaded worksheets; parents see both against
  their child.

### Search (FR-42)
- **FR-42** Role-scoped search: Super Admin over schools; admins/principals
  over learners, classes, subjects, staff, parents and applications;
  teachers over their own classes, subjects and learners.

### Authentication (FR-1…FR-3)
- **FR-1** All users sign in with **Firebase Phone Auth** (phone number + SMS
  OTP). No passwords.
- **FR-2** A brand-new phone number becomes a **parent** account. A phone
  number pre-added by an admin (staff invite) becomes a **teacher/admin**
  account automatically on first sign-in, consuming the invite.
- **FR-3** Any user authenticating is presented with **Create a profile**
  (name, surname, email, address). Parents must complete it before applying
  for a child; the email address receives notifications.

### Enrollment applications (FR-4…FR-8)
- **FR-4** Parents complete a **step-by-step application form** (modern,
  responsive): ① learner details (incl. SA ID validation with gender decode /
  passport) → ② parent/guardian details (prefilled from profile) → ③ medical &
  emergency contacts → ④ supporting document uploads (birth certificate,
  immunisation card, report card, proof of residence, guardian ID) → ⑤ review
  & submit.
- **FR-5** Progress **auto-saves as a draft** after every step; drafts can be
  resumed from the parent dashboard.
- **FR-6** Applications move through **Submitted → Under review → Accepted →
  Enrolled**, or **Rejected** with a reason. Every transition appends a
  timeline event (who, when, note) visible to the parent (**enrollment
  tracking**).
- **FR-7** *Enroll* atomically creates the **learner record** from the
  application and links it to the applying parent.
- **FR-8** Admin can re-open a rejected application for review.

### Admin management (FR-9…FR-12)
- **FR-9** Admin adds **teachers** (and other admins) by phone number — a
  staff invite that activates on the invitee's first sign-in. Invites can be
  cancelled; staff accounts can be deactivated/reactivated.
- **FR-10** Admin adds/edits/deletes **learners** directly (for learners that
  didn't come through an application).
- **FR-11** Admin creates **classes** (name, grade, year) and assigns a
  **teacher** to each; learners are **assigned to classes**.
- **FR-12** Admin **links learners to parent accounts** (multiple parents per
  learner supported), giving those parents visibility of the child.

### Payments (FR-13…FR-14)
- **FR-13** Parents complete a **payment form** — learner (optional), purpose
  (registration fee, school fees, uniform, …), method, amount, date paid,
  reference, notes — and must attach an uploaded **proof of payment**
  (PDF/image).
- **FR-14** Admin reviews each submission with the proof document and
  **approves** or **rejects** (with a note). The decision is emailed to the
  parent.

### Email notifications — SMTP (FR-15)
- **FR-15** The **school admin configures the school's SMTP details in-app**
  (host, port, username, password, from name/address; with save-and-test).
  All email is sent **directly from the app** over SMTP — no Cloud
  Functions:
  - on every application status change (received, under review, accepted,
    rejected with reason, enrolled);
  - on payment approval/rejection and admin-recorded fee receipts;
  - on every QR attendance scan;
  - for broadcast messages.
  Every message is logged to `mailQueue` (`sent`/`pending`/`error`).
  Browsers cannot open SMTP sockets, so web-triggered email queues in the
  outbox and is auto-delivered by the next staff mobile/desktop session.

### Broadcast messages (FR-23…FR-25)
- **FR-23** Admin composes broadcasts with an **HTML message editor**
  (formatting toolbar + live preview).
- **FR-24** Destination is **per learner** (their parents), **per class**
  (parents of the class's learners) or **per school** (all parents).
- **FR-25** Sending stores the broadcast as an **in-app notification** — a
  bell badge in the app bar and an announcements feed for each recipient —
  and **emails** every targeted parent over SMTP.

### School calendar (FR-26…FR-28)
- **FR-26** A month-view **calendar** available to every role.
- **FR-27** Events target the **whole school**, **a class**, or **all
  parents**; each viewer sees only what applies to them (parents also see
  their children's class events; teachers their own classes).
- **FR-28** Admin adds events for any audience; a **teacher** adds events
  for classes they teach. Creators (and admin) can delete events.

### Fees (FR-29…FR-32)
- **FR-29** Admin **configures fee structures**: name, grade (or all
  grades), year, amount, optional due date.
- **FR-30** An **Outstanding** view lists active learners whose approved
  fee payments fall short of their applicable structures, with per-learner
  due/paid/outstanding amounts and a school total.
- **FR-31** Admin **records payments** received at the office (pre-approved,
  optionally linked to a fee structure, with an optional emailed receipt).
- **FR-32** Admin **bulk-uploads learner payments** via a downloadable **CSV
  template** (pre-filled with each learner's id/name/grade/class). Uploads
  are parsed and **staged** (`paymentImports`) with per-row validation;
  payment records are only created when the admin **approves** the batch
  (discard is also available).

### QR attendance (FR-19…FR-22)
- **FR-19** Every learner has a **QR code** (encoding their learner id).
  Parents display it from their dashboard; admin can display/print it from
  learner management.
- **FR-20** **Teachers and all school staff** can scan the code (camera
  scanner with a name-search fallback). Scanning shows the **child's
  details** (name, grade, class, DOB, current status, linked parents).
- **FR-21** The staff member marks the child **In school / Present** at
  drop-off, and **Left school** at pick-up. Each scan is stored as an
  immutable attendance event (who scanned, when) and stamps the learner's
  live in/out status.
- **FR-22** **Linked parents are emailed on every scan** — when the child is
  dropped at school and when they leave. The live status and recent scan
  history are visible on the parent dashboard.

### In-app chat (FR-16…FR-18)
- **FR-16** **Staff ↔ staff** chat: any admin/teacher starts a conversation
  with a colleague from the staff directory; messaging is immediate.
- **FR-17** **Parents request a chat with a teacher**, giving a reason and the
  learner concerned. The thread is created in a *requested* state and is
  locked for messaging.
- **FR-18** **Admin approves or declines** parent chat requests; on approval,
  messaging unlocks for both sides. Approval state is enforced by security
  rules, not just UI.

### General (GR-1…GR-5)
- **GR-1** Responsive layout across mobile / tablet / desktop (inline nav vs
  drawer, adaptive grids, two-column form rows on wide screens).
- **GR-2** Modern, colourful design (vibrant Material 3, gradient hero
  surfaces). Users **customise their own app**: theme palette, light/dark
  mode and text size, persisted locally.
- **GR-6** Every signed-in home shows an **in-app banner** with a greeting,
  the user's latest messages, and up to 3 upcoming events (hidden when
  there are none).
- **GR-3** Role-based routing guards: each role only reaches its own area;
  unauthenticated users only the landing/login pages.
- **GR-4** Firestore + Storage **security rules** enforce all role boundaries
  server-side (role escalation blocked, drafts-only parent edits, admin-only
  approvals, participant-only chat, approved-thread-only messaging).
- **GR-5** The app runs against a placeholder Firebase config with a helpful
  setup screen instead of crashing.

## 3. Data model (Firestore)

```
users/{uid}            role, phone, email, firstName, lastName, address,
                       profileComplete, active, createdAt
staffInvites/{phone}   role, firstName, lastName, email, claimedByUid   (id = E.164)
classes/{id}           name, grade, year, teacherUid, teacherName
learners/{id}          names, dob, gender, idNumber, grade, status,
                       classId, className, parentUids[], applicationId
applications/{id}      parentUid, status, learner*, guardian*, medical*,
                       documents{label→url}, events[{status,note,byName,at}],
                       rejectionReason, learnerId, createdAt/updatedAt/submittedAt
payments/{id}          parentUid, parentName, learnerId, learnerName, purpose,
                       method, amountCents, reference, paymentDate, notes,
                       proofUrl, status, reviewNote, reviewedByName, reviewedAt
chats/{id}             type (staff|parentTeacher), participantUids[],
                       participantNames{}, approval, requestReason, learnerName,
                       lastMessage, updatedAt
chats/{id}/messages/{id}  senderUid, senderName, text, createdAt
attendance/{id}        learnerId, learnerName, className, type (checkIn|checkOut),
                       byUid, byName, parentUids[], at
settings/smtp          host, port, username, password, fromName, fromAddress
activityLogs/{id}      action, category, actorUid/Name/Role, schoolId/Name,
                       target, details, at            (global, append-only)
platform/config        bootstrapped, firstSuperAdminUid   (one-time claim)
broadcasts/{id}        subject, html, scope (school|schoolClass|learner),
                       classId/Name, learnerId/Name, recipientUids[],
                       emailsSent/Failed, sentByName, createdAt
events/{id}            title, description, start, end, audience
                       (school|schoolClass|parents), classId/Name, createdBy*
feeStructures/{id}     name, grade|All grades, year, amountCents, dueDate
paymentImports/{id}    filename, rows[{learnerId, amountCents, date, …, error}],
                       status (staged|approved|discarded), createdByName
mailQueue/{id}         to, subject, text, html, status (pending|sent|error), sentAt
```

Storage: `applications/{uid}/{applicationId}/…`, `paymentProofs/{uid}/…`,
`profilePhotos/{uid}.jpg`.

## 4. Out of scope for this iteration / open questions

- Attendance registers, homework, report cards and timetables.
- Card/EFT gateway payments (payments are proof-of-payment based); invoicing
  and fee statements.
- True push notifications (FCM) — they require a server; broadcast
  notifications are in-app (bell + feed) plus email. Chat unread badges.
- Multi-school tenancy — the deployment serves one school per Firebase project.
- Bulk import of learners/parents (CSV) for migration.
- Localisation — the UI is English-only in this iteration.
