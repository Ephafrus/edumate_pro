// Who may change a school's own identity.
//
// School documents were previously Super-Admin-only. Letting a school's own
// admin maintain its name, contact details and logo widens that, so the
// boundary is pinned here: profile fields yes, `active` no — suspending a
// school is the platform's decision and a school must not be able to
// un-suspend itself.
import { readFileSync } from 'node:fs';
import {
  initializeTestEnvironment, assertSucceeds, assertFails,
} from '@firebase/rules-unit-testing';
import { doc, setDoc, updateDoc } from 'firebase/firestore';

const SCHOOL = 'school1';
const OTHER = 'school2';
const ADMIN = 'adminUid';
const PRINCIPAL = 'principalUid';
const TEACHER = 'teacherUid';
const PARENT = 'parentUid';
const OTHER_ADMIN = 'otherAdminUid';
const SUPER = 'superUid';

const testEnv = await initializeTestEnvironment({
  projectId: 'demo-edumate-school',
  firestore: {
    host: '127.0.0.1',
    port: Number(process.env.FIRESTORE_EMULATOR_PORT ?? 8080),
    rules: readFileSync(new URL('../../firestore.rules', import.meta.url), 'utf8'),
  },
});

const school = {
  name: 'Test Primary', address: '1 Main Road', phone: '0211234567',
  email: 'office@test.example', motto: 'Learn well', logoUrl: '',
  active: true,
};

async function seed() {
  await testEnv.clearFirestore();
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, 'schools', SCHOOL), school);
    await setDoc(doc(db, 'schools', OTHER), { ...school, name: 'Other School' });
    for (const [uid, role, at] of [
      [ADMIN, 'admin', SCHOOL], [PRINCIPAL, 'principal', SCHOOL],
      [TEACHER, 'teacher', SCHOOL], [PARENT, 'parent', SCHOOL],
      [OTHER_ADMIN, 'admin', OTHER],
    ]) {
      await setDoc(doc(db, 'users', uid), { role, superAdmin: false });
      await setDoc(doc(db, 'schools', at, 'members', uid),
        { uid, schoolId: at, role, active: true });
    }
    await setDoc(doc(db, 'users', SUPER), { role: 'admin', superAdmin: true });
  });
}

const as = (uid) => testEnv.authenticatedContext(uid).firestore();
const results = [];
async function it(name, fn) {
  try {
    await seed();
    await fn();
    results.push(['PASS', name]);
  } catch (e) {
    results.push(['FAIL', name, String(e.message).split('\n')[0]]);
  }
}

const schoolDoc = (uid, id = SCHOOL) => doc(as(uid), 'schools', id);

// ---- The school maintains its own identity --------------------------------

await it('an admin may set their school logo', () => assertSucceeds(
  updateDoc(schoolDoc(ADMIN), { logoUrl: 'https://example.com/logo.png' })));

await it('a principal may set the school logo', () => assertSucceeds(
  updateDoc(schoolDoc(PRINCIPAL), { logoUrl: 'https://example.com/l.png' })));

await it('an admin may edit name, contact details and motto', () =>
  assertSucceeds(updateDoc(schoolDoc(ADMIN), {
    name: 'Test Primary School', address: '2 Main Road',
    phone: '0219998888', email: 'admin@test.example', motto: 'Onward',
  })));

await it('a super admin may still edit everything', () => assertSucceeds(
  updateDoc(schoolDoc(SUPER), { name: 'Renamed', active: false })));

// ---- but not the platform's decisions -------------------------------------

await it('an admin may NOT suspend their school', () => assertFails(
  updateDoc(schoolDoc(ADMIN), { active: false })));

await it('an admin may NOT un-suspend their school', async () => {
  await testEnv.withSecurityRulesDisabled(async (ctx) =>
    setDoc(doc(ctx.firestore(), 'schools', SCHOOL),
      { ...school, active: false }));
  await assertFails(updateDoc(schoolDoc(ADMIN), { active: true }));
});

await it('an admin may NOT sneak `active` in beside the logo', () =>
  assertFails(updateDoc(schoolDoc(ADMIN), {
    logoUrl: 'https://example.com/logo.png', active: false,
  })));

await it('an admin may NOT add a field the rule does not name', () =>
  assertFails(updateDoc(schoolDoc(ADMIN), { plan: 'enterprise' })));

// ---- and only their own school --------------------------------------------

await it("an admin may NOT change another school's logo", () => assertFails(
  updateDoc(schoolDoc(ADMIN, OTHER), { logoUrl: 'https://x/y.png' })));

await it("another school's admin may NOT change this one", () => assertFails(
  updateDoc(schoolDoc(OTHER_ADMIN, SCHOOL), { name: 'Hijacked' })));

// ---- and only managers ----------------------------------------------------

await it('a teacher may NOT change the school', () => assertFails(
  updateDoc(schoolDoc(TEACHER), { logoUrl: 'https://x/y.png' })));

await it('a parent may NOT change the school', () => assertFails(
  updateDoc(schoolDoc(PARENT), { name: 'Nope' })));

await it('nobody but a super admin may delete a school', async () => {
  const { deleteDoc } = await import('firebase/firestore');
  await assertFails(deleteDoc(schoolDoc(ADMIN)));
});

await testEnv.cleanup();

let failed = 0;
for (const [status, name, msg] of results) {
  if (status === 'FAIL') failed++;
  console.log(`${status}  ${name}${msg ? `\n      ${msg}` : ''}`);
}
console.log(`\n${results.length - failed}/${results.length} passed`);
process.exit(failed ? 1 : 0);
