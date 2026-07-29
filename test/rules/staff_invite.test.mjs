// Security-rules tests for the staff-invite claim path, run against the
// Firestore emulator.
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
} from '@firebase/rules-unit-testing';
import { doc, setDoc, getDoc } from 'firebase/firestore';

const SCHOOL = 'school1';
const TEACHER_UID = 'teacherUid';
const TEACHER_PHONE = '+27721234567';
const ADMIN_UID = 'adminUid';

const testEnv = await initializeTestEnvironment({
  projectId: 'demo-edumate',
  firestore: {
    host: '127.0.0.1',
    port: Number(process.env.FIRESTORE_EMULATOR_PORT ?? 8080),
    rules: readFileSync(new URL('../../firestore.rules', import.meta.url), 'utf8'),
  },
});

async function seed() {
  await testEnv.clearFirestore();
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, 'schools', SCHOOL), { name: 'Test School', active: true });
    // The admin who issued the invite.
    await setDoc(doc(db, 'users', ADMIN_UID), { role: 'admin', superAdmin: false });
    await setDoc(doc(db, 'schools', SCHOOL, 'members', ADMIN_UID), {
      uid: ADMIN_UID, schoolId: SCHOOL, role: 'admin', active: true,
    });
    // The teacher's own user record, created on first sign-in.
    await setDoc(doc(db, 'users', TEACHER_UID), {
      role: 'parent', superAdmin: false, phone: TEACHER_PHONE,
    });
  });
}

async function putInvite(id, data) {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), 'staffInvites', id), data);
  });
}

const teacherCtx = () =>
  testEnv.authenticatedContext(TEACHER_UID, { phone_number: TEACHER_PHONE });

const membership = (role) => ({
  uid: TEACHER_UID,
  schoolId: SCHOOL,
  schoolName: 'Test School',
  role,
  firstName: 'Thandi',
  lastName: 'Mokoena',
  phone: TEACHER_PHONE,
  active: true,
});

const inviteDocId = `${SCHOOL}_${TEACHER_PHONE}`;
const invite = (role = 'teacher', overrides = {}) => ({
  phone: TEACHER_PHONE,
  role,
  schoolId: SCHOOL,
  schoolName: 'Test School',
  firstName: 'Thandi',
  lastName: 'Mokoena',
  claimedByUid: null,
  ...overrides,
});

const results = [];
async function it(name, fn) {
  try {
    await seed();
    await fn();
    results.push(['PASS', name]);
  } catch (e) {
    results.push(['FAIL', name, e.message]);
  }
}

// ---- The bug the user reported -------------------------------------------

await it('teacher with a matching invite can create their own membership', async () => {
  await putInvite(inviteDocId, invite('teacher'));
  const db = teacherCtx().firestore();
  await assertSucceeds(
    setDoc(doc(db, 'schools', SCHOOL, 'members', TEACHER_UID), membership('teacher')),
  );
});

await it('teacher can read the invite addressed to their number', async () => {
  await putInvite(inviteDocId, invite('teacher'));
  const db = teacherCtx().firestore();
  await assertSucceeds(getDoc(doc(db, 'staffInvites', inviteDocId)));
});

await it('teacher can mark their own invite claimed', async () => {
  await putInvite(inviteDocId, invite('teacher'));
  const db = teacherCtx().firestore();
  await assertSucceeds(
    setDoc(doc(db, 'staffInvites', inviteDocId),
      { ...invite('teacher'), claimedByUid: TEACHER_UID }),
  );
});

await it('an invited principal gets the principal role, not teacher', async () => {
  await putInvite(inviteDocId, invite('principal'));
  const db = teacherCtx().firestore();
  await assertSucceeds(
    setDoc(doc(db, 'schools', SCHOOL, 'members', TEACHER_UID), membership('principal')),
  );
});

// ---- It must not become a way to grant yourself a role -------------------

await it('no invite means no self-granted staff membership', async () => {
  const db = teacherCtx().firestore();
  await assertFails(
    setDoc(doc(db, 'schools', SCHOOL, 'members', TEACHER_UID), membership('teacher')),
  );
});

await it('cannot claim a role higher than the invite grants', async () => {
  await putInvite(inviteDocId, invite('teacher'));
  const db = teacherCtx().firestore();
  await assertFails(
    setDoc(doc(db, 'schools', SCHOOL, 'members', TEACHER_UID), membership('admin')),
  );
});

await it("cannot use somebody else's invite", async () => {
  await putInvite(`${SCHOOL}_+27829999999`, invite('admin', { phone: '+27829999999' }));
  const db = teacherCtx().firestore();
  await assertFails(
    setDoc(doc(db, 'schools', SCHOOL, 'members', TEACHER_UID), membership('admin')),
  );
});

await it('an invite at one school grants nothing at another', async () => {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), 'schools', 'school2'),
      { name: 'Other', active: true });
  });
  await putInvite(inviteDocId, invite('teacher'));
  const db = teacherCtx().firestore();
  await assertFails(
    setDoc(doc(db, 'schools', 'school2', 'members', TEACHER_UID),
      { ...membership('teacher'), schoolId: 'school2' }),
  );
});

await it('a random-id invite does not grant a staff membership', async () => {
  // Invites written before ids became derivable: rules cannot find them.
  await putInvite('someRandomId', invite('teacher'));
  const db = teacherCtx().firestore();
  await assertFails(
    setDoc(doc(db, 'schools', SCHOOL, 'members', TEACHER_UID), membership('teacher')),
  );
});

// ---- Parents still work as before ----------------------------------------

await it('anyone may still join a school as a parent', async () => {
  const db = teacherCtx().firestore();
  await assertSucceeds(
    setDoc(doc(db, 'schools', SCHOOL, 'members', TEACHER_UID), membership('parent')),
  );
});

await it('a parent cannot promote their own membership to teacher', async () => {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), 'schools', SCHOOL, 'members', TEACHER_UID),
      membership('parent'));
  });
  const db = teacherCtx().firestore();
  await assertFails(
    setDoc(doc(db, 'schools', SCHOOL, 'members', TEACHER_UID), membership('teacher')),
  );
});

await it('an invited teacher whose parent membership exists is upgraded', async () => {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), 'schools', SCHOOL, 'members', TEACHER_UID),
      membership('parent'));
  });
  await putInvite(inviteDocId, invite('teacher'));
  const db = teacherCtx().firestore();
  await assertSucceeds(
    setDoc(doc(db, 'schools', SCHOOL, 'members', TEACHER_UID), membership('teacher')),
  );
});

await testEnv.cleanup();

let failed = 0;
for (const [status, name, msg] of results) {
  if (status === 'FAIL') failed++;
  console.log(`${status}  ${name}${msg ? `\n      ${msg.split('\n')[0]}` : ''}`);
}
console.log(`\n${results.length - failed}/${results.length} passed`);
process.exit(failed ? 1 : 0);
