/**
 * EduMate Pro Cloud Functions — SMTP email notifications.
 *
 * Outgoing email is sent over SMTP with nodemailer. Configure before deploy:
 *
 *   firebase functions:secrets:set SMTP_PASSWORD    # SMTP account password
 *
 * and set the remaining values as params (prompted on first deploy, stored in
 * functions/.env): SMTP_HOST, SMTP_PORT, SMTP_USERNAME, SMTP_FROM.
 *
 * How mail flows:
 *  - Everything to be sent is a doc in `mailQueue` ({to, subject, text}).
 *    `processMailQueue` picks each doc up, sends it, and records the result
 *    on the doc (status: sent | error) — giving an audit trail.
 *  - `onApplicationStatusChange` and `onPaymentReviewed` watch Firestore and
 *    queue the parent-facing notification emails automatically.
 *  - School admins can also queue custom notices from the app (Firestore
 *    rules restrict `mailQueue` creation to admins).
 */
const {onDocumentCreated, onDocumentUpdated} =
    require("firebase-functions/v2/firestore");
const {defineSecret, defineString} = require("firebase-functions/params");
const admin = require("firebase-admin");
const nodemailer = require("nodemailer");

admin.initializeApp();
const db = admin.firestore();

const SMTP_HOST = defineString("SMTP_HOST");
const SMTP_PORT = defineString("SMTP_PORT", {default: "587"});
const SMTP_USERNAME = defineString("SMTP_USERNAME");
const SMTP_FROM = defineString("SMTP_FROM",
    {description: "From header, e.g. \"EduMate Pro <no-reply@school.co.za>\""});
const SMTP_PASSWORD = defineSecret("SMTP_PASSWORD");

/** Builds a nodemailer transport from the configured SMTP settings. */
function transporter() {
  const port = Number(SMTP_PORT.value() || "587");
  return nodemailer.createTransport({
    host: SMTP_HOST.value(),
    port,
    secure: port === 465, // SMTPS; 587 uses STARTTLS
    auth: {
      user: SMTP_USERNAME.value(),
      pass: SMTP_PASSWORD.value(),
    },
  });
}

/** Queues an email document; `processMailQueue` sends it. */
async function queueMail(to, subject, text) {
  if (!to) return;
  await db.collection("mailQueue").add({
    to,
    subject,
    text,
    status: "pending",
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });
}

/** Sends every newly queued email and records the outcome on the doc. */
exports.processMailQueue = onDocumentCreated(
    {document: "mailQueue/{id}", secrets: [SMTP_PASSWORD]},
    async (event) => {
      const snap = event.data;
      if (!snap) return;
      const m = snap.data();
      if (m.status !== "pending" || !m.to) return;
      try {
        await transporter().sendMail({
          from: SMTP_FROM.value(),
          to: m.to,
          subject: m.subject || "EduMate Pro notification",
          text: m.text || "",
        });
        await snap.ref.update({
          status: "sent",
          sentAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      } catch (err) {
        console.error("SMTP send failed", err);
        await snap.ref.update({status: "error", error: String(err)});
      }
    });

/** Parent-facing copy for each application status. */
function applicationEmail(app, status) {
  const learner = `${app.learnerFirstName || ""} ${app.learnerLastName || ""}`
      .trim() || "your child";
  const subjects = {
    submitted: `Application received — ${learner}`,
    underReview: `Application under review — ${learner}`,
    accepted: `Application accepted — ${learner}`,
    rejected: `Application outcome — ${learner}`,
    enrolled: `Welcome! ${learner} is enrolled`,
  };
  const bodies = {
    submitted:
      `We have received your enrollment application for ${learner} ` +
      `(${app.gradeApplyingFor || "grade not specified"}). ` +
      `We will email you as it progresses. You can also track it any time ` +
      `in the EduMate Pro app.`,
    underReview:
      `Your enrollment application for ${learner} is now under review. ` +
      `We will be in touch with the outcome soon.`,
    accepted:
      `Great news — your enrollment application for ${learner} has been ` +
      `accepted! The school will finalise enrollment and let you know the ` +
      `next steps (including any registration payment).`,
    rejected:
      `We are sorry — your enrollment application for ${learner} was not ` +
      `successful.` +
      (app.rejectionReason ? `\n\nReason: ${app.rejectionReason}` : "") +
      `\n\nPlease contact the school office if you would like to discuss ` +
      `this.`,
    enrolled:
      `${learner} is now enrolled! Their learner profile has been created ` +
      `and linked to your account in the EduMate Pro app, where you will ` +
      `see class placement, payments and messages.`,
  };
  if (!subjects[status]) return null;
  const greeting = app.guardianFirstName ?
      `Dear ${app.guardianFirstName},\n\n` : `Dear parent/guardian,\n\n`;
  return {
    subject: subjects[status],
    text: `${greeting}${bodies[status]}\n\nKind regards\nThe School Office\n` +
        `(sent by EduMate Pro — please do not reply to this address)`,
  };
}

/** Emails the guardian whenever an application's status changes. */
exports.onApplicationStatusChange = onDocumentUpdated(
    "applications/{id}",
    async (event) => {
      const before = event.data.before.data();
      const after = event.data.after.data();
      if (!after || before.status === after.status) return;
      if (after.status === "draft") return;
      const mail = applicationEmail(after, after.status);
      if (!mail) return;
      await queueMail(after.guardianEmail, mail.subject, mail.text);
    });

/** Emails the parent when an admin approves/rejects their payment. */
exports.onPaymentReviewed = onDocumentUpdated(
    "payments/{id}",
    async (event) => {
      const before = event.data.before.data();
      const after = event.data.after.data();
      if (!after || before.status === after.status) return;
      if (after.status !== "approved" && after.status !== "rejected") return;

      // The payment form doesn't capture email; use the parent's profile.
      const userSnap =
          await db.collection("users").doc(after.parentUid).get();
      const email = userSnap.exists ? userSnap.data().email : null;
      if (!email) return;

      const amount = `R ${((after.amountCents || 0) / 100).toFixed(2)}`;
      const forLine = after.learnerName ?
          ` for ${after.learnerName}` : "";
      const approved = after.status === "approved";
      const subject = approved ?
          `Payment approved — ${after.purpose || "payment"} (${amount})` :
          `Payment could not be verified — ${after.purpose || "payment"}`;
      const text = (userSnap.data().firstName ?
          `Dear ${userSnap.data().firstName},\n\n` : `Dear parent,\n\n`) +
        (approved ?
          `Your payment of ${amount}${forLine} (${after.purpose}) has been ` +
          `reviewed and approved by the school. Thank you!` :
          `Your submitted payment of ${amount}${forLine} ` +
          `(${after.purpose}) could not be verified.` +
          (after.reviewNote ? `\n\nNote from the school: ${after.reviewNote}` :
              "") +
          `\n\nPlease check the details and re-submit, or contact the school ` +
          `office.`) +
        `\n\nKind regards\nThe School Office\n` +
        `(sent by EduMate Pro — please do not reply to this address)`;
      await queueMail(email, subject, text);
    });
