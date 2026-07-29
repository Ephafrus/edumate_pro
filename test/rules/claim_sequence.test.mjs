// Walks the *exact* sequence of writes `AuthController._claimInvites`
// performs on an invited teacher's first sign-in, as that teacher, against
// the real rules.
//
// The membership write is the one that used to be refused, but it is not the
// only write in that try block — a denial on any of them surfaces as the same
// "staff invite claim failed" line, so each step is checked separately here.
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import {
  initializeTestEnvironment, assertSucceeds,
} from '@firebase/rules-unit-testing';
import {
  doc, setDoc, updateDoc, getDoc, collection, query, where, getDocs,
} from 'firebase/firestore';

const SCHOOL = 'school1';
const UID = 'teacherUid';
const PHONE = '+27721234567';
const INVITE_ID = `${SCHOOL}_${PHONE}`;

const testEnv = await initializeTestEnvironment({
  projectId: 'demo-edumate-claim',
  firestore: {
    host: '127.0.0.1',
    port: Number(process.env.FIRESTORE_EMULATOR_PORT ?? 8080),
    rules: readFileSync(new URL('../../firestore.rules', import.meta.url), 'utf8'),
  },
});

await testEnv.clearFirestore();
await testEnv.withSecurityRulesDisabled(async (ctx) => {
  const db = ctx.firestore();
  await setDoc(doc(db, 'schools', SCHOOL), { name: 'Test School', active: true });
  await setDoc(doc(db, 'staffInvites', INVITE_ID), {
    phone: PHONE, role: 'teacher', schoolId: SCHOOL, schoolName: 'Test School',
    firstName: 'Thandi', lastName: 'Mokoena', email: 't@example.com',
    claimedByUid: null,
  });
  // A class an admin assigned to the invite before it was claimed.
  await setDoc(doc(db, 'schools', SCHOOL, 'classes', 'c1'), {
    name: 'Grade 4 Blue', grade: 'Grade 4',
    teacherUid: null, teacherName: 'Thandi Mokoena', teacherInviteId: INVITE_ID,
  });
  await setDoc(doc(db, 'schools', SCHOOL, 'subjects', 's1'), {
    name: 'Mathematics', classId: 'c1', className: 'Grade 4 Blue',
    teacherUid: null, teacherName: 'Thandi Mokoena', teacherInviteId: INVITE_ID,
  });
});

const db = testEnv.authenticatedContext(UID, { phone_number: PHONE }).firestore();
const steps = [];
async function step(name, fn) {
  try {
    await fn();
    steps.push(['PASS', name]);
  } catch (e) {
    steps.push(['FAIL', name, String(e.message).split('\n')[0]]);
  }
}

// 0. _ensureUserRecord creates the global user document.
await step('create own user record', () => assertSucceeds(
  setDoc(doc(db, 'users', UID), {
    role: 'parent', superAdmin: false, phone: PHONE, profileComplete: false,
  })));

// 1. getStaffInvitesForPhone
await step('query staffInvites by phone', async () => {
  const snap = await assertSucceeds(getDocs(query(
    collection(db, 'staffInvites'), where('phone', '==', PHONE))));
  assert.equal(snap.size, 1);
});

// 2. setMembership with the invited role
await step('write own membership as teacher', () => assertSucceeds(
  setDoc(doc(db, 'schools', SCHOOL, 'members', UID), {
    uid: UID, schoolId: SCHOOL, schoolName: 'Test School', role: 'teacher',
    firstName: 'Thandi', lastName: 'Mokoena', phone: PHONE,
    email: 't@example.com', active: true,
  }, { merge: true })));

// 3. markInviteClaimed
await step('mark the invite claimed', () => assertSucceeds(
  updateDoc(doc(db, 'staffInvites', INVITE_ID), { claimedByUid: UID })));

// 4. resolveTeacherInvite — find and complete the teaching links
await step('query classes by teacherInviteId', async () => {
  const snap = await assertSucceeds(getDocs(query(
    collection(db, 'schools', SCHOOL, 'classes'),
    where('teacherInviteId', '==', INVITE_ID))));
  assert.equal(snap.size, 1);
});
await step('complete the class teaching link', () => assertSucceeds(
  updateDoc(doc(db, 'schools', SCHOOL, 'classes', 'c1'),
    { teacherUid: UID, teacherName: 'Thandi Mokoena', teacherInviteId: null })));
await step('query subjects by teacherInviteId', async () => {
  const snap = await assertSucceeds(getDocs(query(
    collection(db, 'schools', SCHOOL, 'subjects'),
    where('teacherInviteId', '==', INVITE_ID))));
  assert.equal(snap.size, 1);
});
await step('complete the subject teaching link', () => assertSucceeds(
  updateDoc(doc(db, 'schools', SCHOOL, 'subjects', 's1'),
    { teacherUid: UID, teacherName: 'Thandi Mokoena', teacherInviteId: null })));

// 5. Backfill the profile from the invite.
await step('fill in own profile from the invite', () => assertSucceeds(
  updateDoc(doc(db, 'users', UID), {
    firstName: 'Thandi', lastName: 'Mokoena', email: 't@example.com',
    profileComplete: true,
  })));

// 6. Keep the cached role honest.
await step('update own cached role to teacher', () => assertSucceeds(
  updateDoc(doc(db, 'users', UID), { role: 'teacher' })));

// 7. _applyActiveSchool remembers where they landed.
await step('persist activeSchoolId', () => assertSucceeds(
  updateDoc(doc(db, 'users', UID), { activeSchoolId: SCHOOL })));

// 8. The audit trail write that follows.
await step('write an activity log entry', () => assertSucceeds(
  setDoc(doc(collection(db, 'activityLogs')), {
    action: 'memberAssigned', actorUid: UID, actorName: 'Thandi Mokoena',
    actorRole: 'Teacher', schoolId: SCHOOL, schoolName: 'Test School',
    target: 'Test School', details: 'staff invite claimed as Teacher',
  })));

// 9. What the teacher's own screens then read.
await step('read own membership back', () => assertSucceeds(
  getDoc(doc(db, 'schools', SCHOOL, 'members', UID))));
await step('read own classes', () => assertSucceeds(getDocs(query(
  collection(db, 'schools', SCHOOL, 'classes'),
  where('teacherUid', '==', UID)))));
await step('read own subjects', () => assertSucceeds(getDocs(query(
  collection(db, 'schools', SCHOOL, 'subjects'),
  where('teacherUid', '==', UID)))));

await testEnv.cleanup();

let failed = 0;
for (const [status, name, msg] of steps) {
  if (status === 'FAIL') failed++;
  console.log(`${status}  ${name}${msg ? `\n      ${msg}` : ''}`);
}
console.log(`\n${steps.length - failed}/${steps.length} steps allowed`);
process.exit(failed ? 1 : 0);
