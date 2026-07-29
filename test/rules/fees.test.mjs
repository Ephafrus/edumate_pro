// Who may approve money, and who may see whose invoices.
//
// Approval is the principal's signature. Enforcing that by hiding a button
// would leave the office able to approve its own receipts through any other
// client, so it is enforced here and checked here.
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import {
  initializeTestEnvironment, assertSucceeds, assertFails,
} from '@firebase/rules-unit-testing';
import {
  doc, setDoc, updateDoc, getDoc, collection, query, where, getDocs,
} from 'firebase/firestore';

const SCHOOL = 'school1';
const ADMIN = 'adminUid';
const PRINCIPAL = 'principalUid';
const TEACHER = 'teacherUid';
const PARENT = 'parentUid';
const OTHER_PARENT = 'otherParentUid';

const testEnv = await initializeTestEnvironment({
  projectId: 'demo-edumate-fees',
  firestore: {
    host: '127.0.0.1',
    port: Number(process.env.FIRESTORE_EMULATOR_PORT ?? 8080),
    rules: readFileSync(new URL('../../firestore.rules', import.meta.url), 'utf8'),
  },
});

const member = (uid, role) => ({ uid, schoolId: SCHOOL, role, active: true });

async function seed() {
  await testEnv.clearFirestore();
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, 'schools', SCHOOL), { name: 'Test School', active: true });
    for (const [uid, role] of [
      [ADMIN, 'admin'], [PRINCIPAL, 'principal'],
      [TEACHER, 'teacher'], [PARENT, 'parent'], [OTHER_PARENT, 'parent'],
    ]) {
      await setDoc(doc(db, 'users', uid), { role, superAdmin: false });
      await setDoc(doc(db, 'schools', SCHOOL, 'members', uid), member(uid, role));
    }
    await setDoc(doc(db, 'schools', SCHOOL, 'payments', 'pay1'), {
      parentUid: PARENT, learnerId: 'l1', amountCents: 100000,
      status: 'pending', purpose: 'School fees', source: 'parent',
    });
    await setDoc(doc(db, 'schools', SCHOOL, 'invoices', 'l1__f1__2026-01'), {
      learnerId: 'l1', learnerName: 'Thandi', grade: 'Grade 4',
      parentUids: [PARENT], period: '2026-01', amountCents: 100000,
    });
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

const payment = (overrides = {}) => ({
  parentUid: PARENT, learnerId: 'l1', amountCents: 50000,
  status: 'pending', purpose: 'School fees', source: 'admin', ...overrides,
});

// ---- Approval is the principal's ------------------------------------------

await it('a principal may approve a payment', () => assertSucceeds(
  updateDoc(doc(as(PRINCIPAL), 'schools', SCHOOL, 'payments', 'pay1'),
    { status: 'approved', reviewedByName: 'The Principal' })));

await it('a principal may reject a payment', () => assertSucceeds(
  updateDoc(doc(as(PRINCIPAL), 'schools', SCHOOL, 'payments', 'pay1'),
    { status: 'rejected', reviewNote: 'No proof' })));

await it('an admin may NOT approve a payment', () => assertFails(
  updateDoc(doc(as(ADMIN), 'schools', SCHOOL, 'payments', 'pay1'),
    { status: 'approved' })));

await it('an admin may NOT reject a payment', () => assertFails(
  updateDoc(doc(as(ADMIN), 'schools', SCHOOL, 'payments', 'pay1'),
    { status: 'rejected' })));

await it('a parent may NOT approve their own payment', () => assertFails(
  updateDoc(doc(as(PARENT), 'schools', SCHOOL, 'payments', 'pay1'),
    { status: 'approved' })));

await it('a teacher may not touch payments at all', () => assertFails(
  updateDoc(doc(as(TEACHER), 'schools', SCHOOL, 'payments', 'pay1'),
    { status: 'approved' })));

await it('an admin may still correct a pending payment', () => assertSucceeds(
  updateDoc(doc(as(ADMIN), 'schools', SCHOOL, 'payments', 'pay1'),
    { status: 'pending', reference: 'EFT-12345' })));

// ---- Recording ------------------------------------------------------------

await it('a principal may record a payment already approved', () => assertSucceeds(
  setDoc(doc(as(PRINCIPAL), 'schools', SCHOOL, 'payments', 'new1'),
    payment({ status: 'approved', source: 'admin' }))));

await it("an admin's recorded payment must start pending", () => assertFails(
  setDoc(doc(as(ADMIN), 'schools', SCHOOL, 'payments', 'new2'),
    payment({ status: 'approved' }))));

await it('an admin may record a pending payment', () => assertSucceeds(
  setDoc(doc(as(ADMIN), 'schools', SCHOOL, 'payments', 'new3'), payment())));

await it('a parent may submit a pending payment', () => assertSucceeds(
  setDoc(doc(as(PARENT), 'schools', SCHOOL, 'payments', 'new4'),
    payment({ source: 'parent' }))));

await it('a parent may not submit one already approved', () => assertFails(
  setDoc(doc(as(PARENT), 'schools', SCHOOL, 'payments', 'new5'),
    payment({ status: 'approved', source: 'parent' }))));

// ---- Invoices -------------------------------------------------------------

await it('staff may raise an invoice', () => assertSucceeds(
  setDoc(doc(as(ADMIN), 'schools', SCHOOL, 'invoices', 'l2__f1__2026-02'), {
    learnerId: 'l2', parentUids: [PARENT], period: '2026-02',
    amountCents: 100000,
  })));

await it('a teacher may read invoices but not raise them', async () => {
  await assertSucceeds(
    getDoc(doc(as(TEACHER), 'schools', SCHOOL, 'invoices', 'l1__f1__2026-01')));
  await assertFails(
    setDoc(doc(as(TEACHER), 'schools', SCHOOL, 'invoices', 'x'), {
      learnerId: 'l9', parentUids: [], period: '2026-02', amountCents: 1,
    }));
});

await it("a parent reads their own child's invoices", async () => {
  const snap = await assertSucceeds(getDocs(query(
    collection(as(PARENT), 'schools', SCHOOL, 'invoices'),
    where('parentUids', 'array-contains', PARENT))));
  assert.equal(snap.size, 1);
});

await it("a parent cannot read another family's invoices", () => assertFails(
  getDocs(query(
    collection(as(OTHER_PARENT), 'schools', SCHOOL, 'invoices'),
    where('parentUids', 'array-contains', PARENT)))));

await it('a parent cannot list every invoice in the school', () => assertFails(
  getDocs(collection(as(PARENT), 'schools', SCHOOL, 'invoices'))));

await it('a parent cannot raise an invoice', () => assertFails(
  setDoc(doc(as(PARENT), 'schools', SCHOOL, 'invoices', 'l1__f1__2026-03'), {
    learnerId: 'l1', parentUids: [PARENT], period: '2026-03', amountCents: 1,
  })));

await testEnv.cleanup();

let failed = 0;
for (const [status, name, msg] of results) {
  if (status === 'FAIL') failed++;
  console.log(`${status}  ${name}${msg ? `\n      ${msg}` : ''}`);
}
console.log(`\n${results.length - failed}/${results.length} passed`);
process.exit(failed ? 1 : 0);
