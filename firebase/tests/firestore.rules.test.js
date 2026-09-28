// Security rules tests. Run with `npm test` in this folder (starts the emulators).
import { test, before, after, beforeEach } from 'node:test';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
} from '@firebase/rules-unit-testing';
import { doc, getDoc, setDoc, updateDoc, deleteDoc } from 'firebase/firestore';
import { ref, uploadBytes, getBytes } from 'firebase/storage';

const rulesPath = (name) => fileURLToPath(new URL(`../${name}`, import.meta.url));
let env;

before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-discipline',
    firestore: { rules: readFileSync(rulesPath('firestore.rules'), 'utf8'), host: '127.0.0.1', port: 8080 },
    storage: { rules: readFileSync(rulesPath('storage.rules'), 'utf8'), host: '127.0.0.1', port: 9199 },
  });
});
after(async () => { await env?.cleanup(); });
beforeEach(async () => {
  await env.clearFirestore();
});

const alice = () => env.authenticatedContext('alice').firestore();
const bob = () => env.authenticatedContext('bob').firestore();

const profile = (uid, condition = 'aiAssisted') => ({
  id: uid, email: `${uid}@x.io`, displayName: uid, createdAt: new Date(),
  onboardingCompleted: false, participantId: 'P-ABCDEFGH23', trackingCondition: condition,
});

async function seed(path, data) {
  await env.withSecurityRulesDisabled(async (ctx) => { await setDoc(doc(ctx.firestore(), path), data); });
}

const completion = (overrides = {}) => ({
  id: 'c1', userId: 'alice', habitId: 'h1', day: '2026-09-28', quantity: 1,
  status: 'selfReported', method: 'selfReport', trackingCondition: 'aiAssisted',
  createdAt: new Date(), updatedAt: new Date(), clientRequestId: 'r1', ...overrides,
});

// ---------- users ----------
test('user can create and read own profile, not others', async () => {
  await assertSucceeds(setDoc(doc(alice(), 'users/alice'), profile('alice')));
  await assertSucceeds(getDoc(doc(alice(), 'users/alice')));
  await assertFails(getDoc(doc(bob(), 'users/alice')));
  await assertFails(setDoc(doc(bob(), 'users/alice'), profile('alice')));
});

test('profile rejects invalid participant id or condition', async () => {
  await assertFails(setDoc(doc(alice(), 'users/alice'), { ...profile('alice'), participantId: 'alice@x.io' }));
  await assertFails(setDoc(doc(alice(), 'users/alice'), { ...profile('alice'), trackingCondition: 'whatever' }));
});

test('tracking condition and participant id are immutable', async () => {
  await seed('users/alice', profile('alice', 'manual'));
  await assertFails(updateDoc(doc(alice(), 'users/alice'), { trackingCondition: 'aiAssisted' }));
  await assertFails(updateDoc(doc(alice(), 'users/alice'), { participantId: 'P-ZZZZZZZZZZ' }));
  await assertSucceeds(updateDoc(doc(alice(), 'users/alice'), { onboardingCompleted: true }));
});

// ---------- completions ----------
test('client cannot write a verified completion', async () => {
  await seed('users/alice', profile('alice'));
  await seed('habits/h1', { id: 'h1', userId: 'alice', requiresEvidence: true });
  await assertFails(setDoc(doc(alice(), 'habitCompletions/c1'),
    completion({ status: 'verified', method: 'photoVerification' })));
});

test('AI-assisted participant cannot self-report an evidence-required habit', async () => {
  await seed('users/alice', profile('alice', 'aiAssisted'));
  await seed('habits/h1', { id: 'h1', userId: 'alice', requiresEvidence: true });
  await assertFails(setDoc(doc(alice(), 'habitCompletions/c1'), completion()));
  await assertSucceeds(setDoc(doc(alice(), 'habitCompletions/c1'),
    completion({ status: 'pendingVerification', method: 'photoVerification' })));
});

test('manual participant can self-report', async () => {
  await seed('users/alice', profile('alice', 'manual'));
  await seed('habits/h1', { id: 'h1', userId: 'alice', requiresEvidence: true });
  await assertSucceeds(setDoc(doc(alice(), 'habitCompletions/c1'), completion({ trackingCondition: 'manual' })));
});

test('completion condition must match the profile condition', async () => {
  await seed('users/alice', profile('alice', 'manual'));
  await seed('habits/h1', { id: 'h1', userId: 'alice', requiresEvidence: false });
  await assertFails(setDoc(doc(alice(), 'habitCompletions/c1'), completion({ trackingCondition: 'aiAssisted' })));
});

test('client cannot change a server-decided completion', async () => {
  await seed('users/alice', profile('alice', 'aiAssisted'));
  await seed('habits/h1', { id: 'h1', userId: 'alice', requiresEvidence: false });
  await seed('habitCompletions/c1', completion({ status: 'rejected', verificationId: 'v1' }));
  await assertFails(updateDoc(doc(alice(), 'habitCompletions/c1'), { verificationId: 'v2' }));
  await seed('habitCompletions/c1', completion({ status: 'verified' }));
  await assertFails(updateDoc(doc(alice(), 'habitCompletions/c1'), { status: 'pending' }));
});

// ---------- verifications / evidence ----------
test('verification results are backend-only and immutable', async () => {
  await seed('verifications/v1', { id: 'v1', userId: 'alice', status: 'rejected' });
  await assertSucceeds(getDoc(doc(alice(), 'verifications/v1')));
  await assertFails(getDoc(doc(bob(), 'verifications/v1')));
  await assertFails(updateDoc(doc(alice(), 'verifications/v1'), { status: 'verified' }));
  await assertFails(setDoc(doc(alice(), 'verifications/v2'), { id: 'v2', userId: 'alice', status: 'verified' }));
  await assertFails(deleteDoc(doc(alice(), 'verifications/v1')));
});

test('evidence must start pending and point at the owner storage path', async () => {
  const evidence = { id: 'e1', userId: 'alice', habitId: 'h1', completionId: 'c1',
    storagePath: 'evidence/alice/e1.jpg', verificationStatus: 'pending', submittedAt: new Date() };
  await assertFails(setDoc(doc(alice(), 'evidence/e1'), { ...evidence, verificationStatus: 'verified' }));
  await assertFails(setDoc(doc(alice(), 'evidence/e1'), { ...evidence, storagePath: 'evidence/bob/e1.jpg' }));
  await assertSucceeds(setDoc(doc(alice(), 'evidence/e1'), evidence));
  await assertFails(updateDoc(doc(alice(), 'evidence/e1'), { verificationStatus: 'verified' }));
});

// ---------- accountability ----------
test('accountability task cannot be self-completed or exceed safety limit', async () => {
  const task = { id: 't1', userId: 'alice', sourceHabitId: 'h1', sourceCompletionId: 'c1', day: '2026-09-28',
    type: 'pushUps', target: 50, progress: 0, status: 'pending', deadline: new Date(Date.now() + 86_400_000) };
  await assertFails(setDoc(doc(alice(), 'accountabilityTasks/t1'), { ...task, target: 1000 }));
  await assertSucceeds(setDoc(doc(alice(), 'accountabilityTasks/t1'), task));
  await assertSucceeds(updateDoc(doc(alice(), 'accountabilityTasks/t1'), { status: 'inProgress' }));
  await assertFails(updateDoc(doc(alice(), 'accountabilityTasks/t1'), { status: 'completed' }));
  await assertFails(updateDoc(doc(alice(), 'accountabilityTasks/t1'), { deadline: new Date(Date.now() + 10 * 86_400_000) }));
});

test('exercise sessions are write-once and tied to own task', async () => {
  await seed('accountabilityTasks/t1', { id: 't1', userId: 'alice' });
  await seed('accountabilityTasks/tb', { id: 'tb', userId: 'bob' });
  const session = { id: 's1', userId: 'alice', accountabilityTaskId: 't1', validReps: 50, invalidReps: 3 };
  await assertFails(setDoc(doc(alice(), 'exerciseSessions/s2'), { ...session, id: 's2', accountabilityTaskId: 'tb' }));
  await assertSucceeds(setDoc(doc(alice(), 'exerciseSessions/s1'), session));
  await assertFails(updateDoc(doc(alice(), 'exerciseSessions/s1'), { validReps: 100 }));
});

// ---------- challenges ----------
test('challenge rules are locked once active', async () => {
  await seed('challenges/ch1', { id: 'ch1', ownerId: 'alice', status: 'active', rules: { allowSkipping: false } });
  await assertFails(updateDoc(doc(alice(), 'challenges/ch1'), { 'rules.allowSkipping': true }));
  await assertSucceeds(updateDoc(doc(alice(), 'challenges/ch1'), { status: 'completed' }));
});

// ---------- research ----------
test('daily records: researchers read, participants read own, nobody writes', async () => {
  await seed('users/alice', profile('alice'));
  await seed('dailyRecords/P-ABCDEFGH23_2026-09-28', { participantId: 'P-ABCDEFGH23' });
  await seed('dailyRecords/P-OTHER22222_2026-09-28', { participantId: 'P-OTHER22222' });
  const researcher = env.authenticatedContext('r', { researcher: true }).firestore();
  await assertSucceeds(getDoc(doc(researcher, 'dailyRecords/P-OTHER22222_2026-09-28')));
  await assertSucceeds(getDoc(doc(alice(), 'dailyRecords/P-ABCDEFGH23_2026-09-28')));
  await assertFails(getDoc(doc(alice(), 'dailyRecords/P-OTHER22222_2026-09-28')));
  await assertFails(setDoc(doc(alice(), 'dailyRecords/P-ABCDEFGH23_2026-09-29'), { participantId: 'P-ABCDEFGH23' }));
});

// ---------- storage ----------
test('evidence photos are private, JPEG-only and immutable', async () => {
  const jpeg = new Uint8Array([0xff, 0xd8, 0xff, 0xd9]);
  const aliceStorage = env.authenticatedContext('alice').storage();
  const bobStorage = env.authenticatedContext('bob').storage();
  await assertSucceeds(uploadBytes(ref(aliceStorage, 'evidence/alice/e1.jpg'), jpeg, { contentType: 'image/jpeg' }));
  await assertFails(uploadBytes(ref(aliceStorage, 'evidence/alice/e1.jpg'), jpeg, { contentType: 'image/jpeg' }));
  await assertFails(uploadBytes(ref(aliceStorage, 'evidence/alice/e2.png'), jpeg, { contentType: 'image/png' }));
  await assertFails(uploadBytes(ref(bobStorage, 'evidence/alice/e3.jpg'), jpeg, { contentType: 'image/jpeg' }));
  await assertFails(getBytes(ref(bobStorage, 'evidence/alice/e1.jpg')));
  await assertFails(getBytes(ref(env.unauthenticatedContext().storage(), 'evidence/alice/e1.jpg')));
});
