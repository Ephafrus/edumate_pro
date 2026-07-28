# EduMate Pro — Requirements

**Project:** EduMate Pro — a single school management platform connecting
**teachers, parents and school admin**.

**Stack:** Flutter (Web, Android, iOS) · Firebase Phone Auth · Cloud Firestore ·
Cloud Storage · Cloud Functions (SMTP email via nodemailer).

---

## 1. Roles

| Role | Summary |
|------|---------|
| **School admin** | Runs the platform: staff, learners, classes, applications, payments, chat approvals |
| **Teacher** | Sees assigned classes and learners; chats with staff and approved parents |
| **Parent** | Applies for children, tracks applications, submits payments, requests teacher chats |

## 2. Functional requirements

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
- **FR-15** A Cloud Functions **SMTP component** (nodemailer; host / port /
  username / from as params, password as a secret) sends email to parents:
  - on every application status change (received, under review, accepted,
    rejected with reason, enrolled);
  - on payment approval/rejection;
  - for admin-composed notices (queued from the app).
  All mail flows through a `mailQueue` collection with a per-message outcome
  (`sent`/`error`) for auditing.

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
- **GR-2** User-selectable theme palette + light/dark mode, persisted locally.
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
mailQueue/{id}         to, subject, text, status (pending|sent|error), sentAt
```

Storage: `applications/{uid}/{applicationId}/…`, `paymentProofs/{uid}/…`,
`profilePhotos/{uid}.jpg`.

## 4. Out of scope for this iteration / open questions

- Attendance registers, homework, report cards and timetables.
- Card/EFT gateway payments (payments are proof-of-payment based); invoicing
  and fee statements.
- Push notifications (email only for now) and chat unread badges.
- Multi-school tenancy — the deployment serves one school per Firebase project.
- Bulk import of learners/parents (CSV) for migration.
- Localisation — the UI is English-only in this iteration.
