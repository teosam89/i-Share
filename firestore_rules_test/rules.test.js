/**
 * Firestore Security Rules integration tests for i-Share (FYP 2, Section 4.1.2).
 * Runs against the Firebase Local Emulator Suite via `firebase emulators:exec`.
 */
const { test, describe, before, after, beforeEach } = require('node:test');
const fs = require('fs');
const path = require('path');
const {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
} = require('@firebase/rules-unit-testing');
const {
  doc,
  getDoc,
  setDoc,
  updateDoc,
  deleteDoc,
  collection,
  collectionGroup,
  query,
  where,
  getDocs,
} = require('firebase/firestore');

// The real rules ship with a placeholder admin UID; the tests swap in this one.
const ADMIN = 'test-admin-uid';
let env;

before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-ishare',
    firestore: {
      rules: fs
        .readFileSync(path.resolve(__dirname, '..', 'firestore.rules'), 'utf8')
        .replaceAll('REPLACE_WITH_ADMIN_UID', ADMIN),
      host: '127.0.0.1',
      port: 8080,
    },
  });
});
after(async () => { await env.cleanup(); });
beforeEach(async () => { await env.clearFirestore(); });

const as = (uid) => env.authenticatedContext(uid).firestore();
const seed = (fn) => env.withSecurityRulesDisabled((ctx) => fn(ctx.firestore()));

describe('profiles/{uid}', () => {
  test('IT-PROF-01 owner can create own profile', async () => {
    await assertSucceeds(setDoc(doc(as('A'), 'profiles/A'), { displayName: 'Alice', score: 100 }));
  });
  test('IT-PROF-02 non-owner cannot create someone else\'s profile', async () => {
    await assertFails(setDoc(doc(as('B'), 'profiles/A'), { displayName: 'Mallory' }));
  });
  test('IT-PROF-03 any authenticated user can read a profile', async () => {
    await seed((db) => setDoc(doc(db, 'profiles/A'), { displayName: 'Alice' }));
    await assertSucceeds(getDoc(doc(as('B'), 'profiles/A')));
  });
  test('IT-PROF-04 owner can update an editable field', async () => {
    await seed((db) => setDoc(doc(db, 'profiles/A'), { displayName: 'Alice', score: 100 }));
    await assertSucceeds(updateDoc(doc(as('A'), 'profiles/A'), { displayName: 'Alice2' }));
  });
  test('IT-PROF-05 owner cannot write CF-managed credibility key (rating)', async () => {
    await seed((db) => setDoc(doc(db, 'profiles/A'), { displayName: 'Alice', rating: 4.0 }));
    await assertFails(updateDoc(doc(as('A'), 'profiles/A'), { rating: 5.0 }));
  });
  test('IT-PROF-06 non-owner cannot update a profile', async () => {
    await seed((db) => setDoc(doc(db, 'profiles/A'), { displayName: 'Alice' }));
    await assertFails(updateDoc(doc(as('B'), 'profiles/A'), { displayName: 'hacked' }));
  });
});

describe('profiles/{uid}/notifications/{id}', () => {
  test('IT-NOTIF-01 owner can create an inbox notification', async () => {
    await assertSucceeds(setDoc(doc(as('A'), 'profiles/A/notifications/n1'),
      { title: 'Join Request', isRead: false }));
  });
  test('IT-NOTIF-02 non-owner cannot read another user\'s inbox', async () => {
    await seed((db) => setDoc(doc(db, 'profiles/A/notifications/n1'), { title: 'x', isRead: false }));
    await assertFails(getDoc(doc(as('B'), 'profiles/A/notifications/n1')));
  });
  test('IT-NOTIF-03 owner can mark notification as read (isRead only)', async () => {
    await seed((db) => setDoc(doc(db, 'profiles/A/notifications/n1'), { title: 'x', isRead: false }));
    await assertSucceeds(updateDoc(doc(as('A'), 'profiles/A/notifications/n1'), { isRead: true }));
  });
  test('IT-NOTIF-04 owner cannot mutate other notification fields', async () => {
    await seed((db) => setDoc(doc(db, 'profiles/A/notifications/n1'), { title: 'x', isRead: false }));
    await assertFails(updateDoc(doc(as('A'), 'profiles/A/notifications/n1'), { title: 'tampered' }));
  });
  test('IT-NOTIF-05 notifications cannot be deleted', async () => {
    await seed((db) => setDoc(doc(db, 'profiles/A/notifications/n1'), { title: 'x', isRead: false }));
    await assertFails(deleteDoc(doc(as('A'), 'profiles/A/notifications/n1')));
  });
});

describe('co_requests/{id} lifecycle', () => {
  const base = { initiatorId: 'A', createdAt: 't0', status: 'active', participants: ['A'] };
  test('IT-COREQ-01 any authenticated user can create a request', async () => {
    await assertSucceeds(setDoc(doc(as('A'), 'co_requests/r1'), base));
  });
  test('IT-COREQ-02 initiator may transition active -> completed', async () => {
    await seed((db) => setDoc(doc(db, 'co_requests/r1'), base));
    await assertSucceeds(updateDoc(doc(as('A'), 'co_requests/r1'), { status: 'completed' }));
  });
  test('IT-COREQ-03 reverse transition completed -> active is rejected', async () => {
    await seed((db) => setDoc(doc(db, 'co_requests/r1'), { ...base, status: 'completed' }));
    await assertFails(updateDoc(doc(as('A'), 'co_requests/r1'), { status: 'active' }));
  });
  test('IT-COREQ-04 initiator may reactivate expired -> active', async () => {
    await seed((db) => setDoc(doc(db, 'co_requests/r1'), { ...base, status: 'expired' }));
    await assertSucceeds(updateDoc(doc(as('A'), 'co_requests/r1'), { status: 'active' }));
  });
  test('IT-COREQ-05 non-initiator cannot update the request', async () => {
    await seed((db) => setDoc(doc(db, 'co_requests/r1'), base));
    await assertFails(updateDoc(doc(as('B'), 'co_requests/r1'), { status: 'completed' }));
  });
  test('IT-COREQ-06 only the initiator can delete the request', async () => {
    await seed((db) => setDoc(doc(db, 'co_requests/r1'), base));
    await assertFails(deleteDoc(doc(as('B'), 'co_requests/r1')));
    await assertSucceeds(deleteDoc(doc(as('A'), 'co_requests/r1')));
  });
});

describe('chat_rooms/{id}/messages', () => {
  // Co-buy style room (id is not dm_/rtm_), participantIds = [A, B]
  const seedRoom = (db) => Promise.all([
    setDoc(doc(db, 'chat_rooms/room1'), { participantIds: ['A', 'B'] }),
    setDoc(doc(db, 'chat_rooms/room1/messages/m1'), { senderId: 'A', content: 'hi', type: 'text', isRead: false }),
  ]);
  test('IT-CHAT-01 participant can read messages', async () => {
    await seed(seedRoom);
    await assertSucceeds(getDoc(doc(as('B'), 'chat_rooms/room1/messages/m1')));
  });
  test('IT-CHAT-02 non-participant cannot read messages', async () => {
    await seed(seedRoom);
    await assertFails(getDoc(doc(as('C'), 'chat_rooms/room1/messages/m1')));
  });
  test('IT-CHAT-03 participant can send a message as themselves', async () => {
    await seed(seedRoom);
    await assertSucceeds(setDoc(doc(as('B'), 'chat_rooms/room1/messages/m2'),
      { senderId: 'B', content: 'yo', type: 'text' }));
  });
  test('IT-CHAT-04 a message cannot be sent under a forged senderId', async () => {
    await seed(seedRoom);
    await assertFails(setDoc(doc(as('B'), 'chat_rooms/room1/messages/m3'),
      { senderId: 'A', content: 'spoof', type: 'text' }));
  });
  test('IT-CHAT-05 sender can recall their own message (content+type)', async () => {
    await seed(seedRoom);
    await assertSucceeds(updateDoc(doc(as('A'), 'chat_rooms/room1/messages/m1'),
      { content: 'This message was recalled', type: 'recalled' }));
  });
  test('IT-CHAT-06 non-sender cannot recall another user\'s message', async () => {
    await seed(seedRoom);
    await assertFails(updateDoc(doc(as('B'), 'chat_rooms/room1/messages/m1'),
      { content: 'recalled', type: 'recalled' }));
  });
  test('IT-CHAT-07 non-sender may mark a message as read', async () => {
    await seed(seedRoom);
    await assertSucceeds(updateDoc(doc(as('B'), 'chat_rooms/room1/messages/m1'), { isRead: true }));
  });
  test('IT-CHAT-08 messages cannot be deleted', async () => {
    await seed(seedRoom);
    await assertFails(deleteDoc(doc(as('A'), 'chat_rooms/room1/messages/m1')));
  });
});

describe('realtime_matches/{id} join & skip', () => {
  const base = { ownerId: 'O', createdAt: 't0', expiresAt: 't9', status: 'waiting', participants: ['O'], participantIntents: {}, skippedBy: [] };
  test('IT-RTM-01 a user can join (participants+intents+status)', async () => {
    await seed((db) => setDoc(doc(db, 'realtime_matches/rm1'), base));
    await assertSucceeds(updateDoc(doc(as('J'), 'realtime_matches/rm1'),
      { participants: ['O', 'J'], participantIntents: { J: 'Eggs 30-pack' }, status: 'matched' }));
  });
  test('IT-RTM-02 any user can skip a room (skippedBy only)', async () => {
    await seed((db) => setDoc(doc(db, 'realtime_matches/rm1'), base));
    await assertSucceeds(updateDoc(doc(as('S'), 'realtime_matches/rm1'), { skippedBy: ['S'] }));
  });
  test('IT-RTM-03 immutable ownerId cannot be changed', async () => {
    await seed((db) => setDoc(doc(db, 'realtime_matches/rm1'), base));
    await assertFails(updateDoc(doc(as('O'), 'realtime_matches/rm1'), { ownerId: 'X' }));
  });
  test('IT-RTM-04 only the owner can delete the match', async () => {
    await seed((db) => setDoc(doc(db, 'realtime_matches/rm1'), base));
    await assertFails(deleteDoc(doc(as('J'), 'realtime_matches/rm1')));
    await assertSucceeds(deleteDoc(doc(as('O'), 'realtime_matches/rm1')));
  });
});

describe('qr_verifications/{requestId}', () => {
  const seedReq = (db) => setDoc(doc(db, 'co_requests/r1'), { initiatorId: 'A', createdAt: 't0', status: 'active', participants: ['A', 'B'] });
  test('IT-QR-01 only the request initiator can open a verification session', async () => {
    await seed(seedReq);
    await assertSucceeds(setDoc(doc(as('A'), 'qr_verifications/r1'),
      { secret: 'abc', participantIds: ['A', 'B'], ownerId: 'A', verifiedIds: [] }));
  });
  test('IT-QR-02 a non-initiator cannot open a verification session', async () => {
    await seed(seedReq);
    await assertFails(setDoc(doc(as('B'), 'qr_verifications/r1'),
      { secret: 'abc', participantIds: ['A', 'B'], ownerId: 'B', verifiedIds: [] }));
  });
  test('IT-QR-03 a participant may add themselves to verifiedIds only', async () => {
    await seed(async (db) => {
      await seedReq(db);
      await setDoc(doc(db, 'qr_verifications/r1'), { secret: 'abc', participantIds: ['A', 'B'], ownerId: 'A', verifiedIds: [] });
    });
    await assertSucceeds(updateDoc(doc(as('B'), 'qr_verifications/r1'), { verifiedIds: ['B'] }));
  });
});

describe('collection-group rules', () => {
  test('IT-CG-01 host can query their own join_requests across requests', async () => {
    await seed((db) => setDoc(doc(db, 'co_requests/r1/join_requests/j1'), { hostId: 'H', requesterId: 'R', status: 'pending' }));
    const q = query(collectionGroup(as('H'), 'join_requests'), where('hostId', '==', 'H'));
    await assertSucceeds(getDocs(q));
  });
  test('IT-CG-02 score_activities collection-group is readable only by admin', async () => {
    await seed((db) => setDoc(doc(db, 'profiles/A/score_activities/a1'), { delta: 15, reason: 'completeDeal' }));
    await assertSucceeds(getDocs(collectionGroup(as(ADMIN), 'score_activities')));
    await assertFails(getDocs(collectionGroup(as('B'), 'score_activities')));
  });
});
