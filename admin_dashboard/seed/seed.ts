/**
 * i-Share Admin Dashboard — Seed Script
 *
 * Creates fake but realistic data so the FYP defense dashboard has something to show:
 *   - 50 profiles (60% User / 30% Trusted / 10% Elite by credibility tier)
 *   - 30 co_requests (all 4 statuses + all 5 categories, KL-area lat/lng)
 *   - 20 realtime_matches (all 3 statuses, ~30% converted_to_cobuy)
 *   - 100 score_activities (all 10 credibility event types present)
 *
 * Every seeded document is tagged with `_seedTag: 'fyp-demo-2026'` so `wipe.ts`
 * can remove ONLY this data without touching real users.
 *
 * Usage:
 *   1. Place a Firebase service-account-key.json in this directory (see README.md)
 *   2. npm install
 *   3. npm run seed
 */

import * as admin from "firebase-admin";
import { faker } from "@faker-js/faker";
import * as fs from "fs";
import * as path from "path";

// ─── Constants ────────────────────────────────────────────────────────────────

const SEED_TAG = "fyp-demo-2026";

const TARGETS = {
    profiles: 50,
    coRequests: 30,
    realtimeMatches: 20,
    scoreActivities: 100,
};

// Mirrors lib/features/co_request/models/co_request_model.dart > RequestCategories (8 keys)
const CATEGORIES = [
    "groceries",
    "fresh",
    "snacks",
    "household",
    "personal",
    "baby_pets",
    "electronics",
    "others",
];
const CO_REQUEST_STATUSES = ["active", "completed", "expired", "cancelled"];
const RTM_STATUSES = ["waiting", "matched", "closed"];

// Mirrors lib/features/profile/services/credibility_service.dart (10 events; 'complaint' removed 2026-05-23 — feature not implemented in app)
const CREDIBILITY_EVENTS = [
    { event: "completeDeal", points: 15, description: "Completed a split" },
    { event: "rating5Star", points: 10, description: "Received 5★ rating" },
    { event: "rating4Star", points: 3, description: "Received 4★ rating" },
    { event: "rating3Below", points: -5, description: "Received ≤3★ rating" },
    { event: "cancelWithParticipants", points: -25, description: "Cancelled with participants" },
    { event: "cancelNoParticipants", points: 0, description: "Cancelled (no participants)" },
    { event: "leaveRequest", points: -10, description: "Left a request" },
    { event: "expiredWithParticipants", points: -10, description: "Request expired with participants" },
    { event: "verifyEmail", points: 20, description: "Verified email" },
    { event: "verifyPhone", points: 30, description: "Verified phone" },
];

// West Malaysia city centers — requests are scattered around these points
// instead of all clustered in one bounding box. Weight reflects realistic
// population density (KL heavier, smaller towns lighter).
const WEST_MY_CITIES: Array<{ name: string; lat: number; lng: number; weight: number }> = [
    // Klang Valley (highest weight)
    { name: "Kuala Lumpur",   lat: 3.1390, lng: 101.6869, weight: 6 },
    { name: "Petaling Jaya",  lat: 3.1073, lng: 101.6068, weight: 4 },
    { name: "Subang Jaya",    lat: 3.0436, lng: 101.5818, weight: 3 },
    { name: "Shah Alam",      lat: 3.0731, lng: 101.5188, weight: 3 },
    { name: "Klang",          lat: 3.0449, lng: 101.4455, weight: 2 },
    { name: "Putrajaya",      lat: 2.9264, lng: 101.6964, weight: 2 },
    // North
    { name: "George Town",    lat: 5.4141, lng: 100.3288, weight: 4 },
    { name: "Butterworth",    lat: 5.3993, lng: 100.3633, weight: 2 },
    { name: "Ipoh",           lat: 4.5975, lng: 101.0901, weight: 3 },
    { name: "Alor Setar",     lat: 6.1184, lng: 100.3685, weight: 2 },
    // Central / South
    { name: "Seremban",       lat: 2.7297, lng: 101.9381, weight: 2 },
    { name: "Melaka",         lat: 2.1896, lng: 102.2501, weight: 3 },
    { name: "Johor Bahru",    lat: 1.4655, lng: 103.7578, weight: 4 },
    { name: "Iskandar Puteri", lat: 1.4118, lng: 103.6308, weight: 2 },
    // East coast
    { name: "Kuantan",        lat: 3.8077, lng: 103.3260, weight: 2 },
    { name: "Kota Bharu",     lat: 6.1254, lng: 102.2381, weight: 2 },
    { name: "Kuala Terengganu", lat: 5.3302, lng: 103.1408, weight: 1 },
];

const STORE_NAMES = [
    "AEON Mid Valley", "Tesco Mutiara Damansara", "Lotus's Cheras",
    "Village Grocer Bangsar", "Jaya Grocer One Utama", "Mercato Pavilion",
    "99 Speedmart SS15", "Mydin USJ", "Giant Hypermarket Kelana Jaya",
    "NSK Trade City", "Sunway Hypermarket", "Cold Storage BSC",
    "AEON Bukit Indah JB", "Tesco Bayan Baru Penang", "Lotus's Tebrau JB",
    "Jaya Grocer Ipoh", "Village Grocer Melaka", "AEON Seremban 2",
    "Giant Kuantan", "Mydin Kota Bharu", "99 Speedmart Alor Setar",
];

// ─── Bootstrap Firebase Admin ────────────────────────────────────────────────

const keyPath = path.join(__dirname, "service-account-key.json");
if (!fs.existsSync(keyPath)) {
    console.error("\n❌ service-account-key.json not found.\n");
    console.error("   See README.md for how to download it from Firebase Console.\n");
    process.exit(1);
}
const serviceAccount = require(keyPath);
admin.initializeApp({
    credential: admin.credential.cert(serviceAccount),
    projectId: serviceAccount.project_id,
});
const db = admin.firestore();

// ─── Helpers ─────────────────────────────────────────────────────────────────

function pick<T>(arr: T[]): T {
    return arr[Math.floor(Math.random() * arr.length)];
}

// Build a flat weighted pool of cities so weight-3 cities appear 3x as often.
const _cityPool: typeof WEST_MY_CITIES = WEST_MY_CITIES.flatMap((c) =>
    Array(c.weight).fill(c)
);

function pickCity() {
    return _cityPool[Math.floor(Math.random() * _cityPool.length)];
}

// Pick a city, then jitter ±0.04° (~4–5 km) so points scatter naturally
// around the city center instead of stacking at the same coordinate.
function randomLatLng(): { latitude: number; longitude: number } {
    const city = pickCity();
    const jitter = () => (Math.random() - 0.5) * 0.08;
    return {
        latitude: city.lat + jitter(),
        longitude: city.lng + jitter(),
    };
}

function uidLike(): string {
    // Firebase Auth UIDs are 28 alphanumeric chars
    return faker.string.alphanumeric(28);
}

// ─── Seed: profiles ──────────────────────────────────────────────────────────

async function seedProfiles(): Promise<string[]> {
    console.log(`\n→ Seeding ${TARGETS.profiles} profiles...`);
    const userIds: string[] = [];

    // Score buckets: 30 User (0–299), 15 Trusted (300–699), 5 Elite (700+)
    const scores: number[] = [
        ...Array.from({ length: 30 }, () => faker.number.int({ min: 0, max: 299 })),
        ...Array.from({ length: 15 }, () => faker.number.int({ min: 300, max: 699 })),
        ...Array.from({ length: 5 }, () => faker.number.int({ min: 700, max: 1000 })),
    ];

    const batch = db.batch();
    for (let i = 0; i < TARGETS.profiles; i++) {
        const uid = uidLike();
        userIds.push(uid);

        const createdAt = faker.date.between({
            from: new Date("2026-01-01"),
            to: new Date("2026-05-22"),
        });
        const verifyEmail = faker.datatype.boolean({ probability: 0.75 });
        const verifyPhone = faker.datatype.boolean({ probability: 0.5 });
        const displayName = faker.person.fullName();

        batch.set(db.collection("profiles").doc(uid), {
            displayName,
            email: verifyEmail ? faker.internet.email() : null,
            phone: verifyPhone ? `+60${faker.string.numeric(9)}` : null,
            photoUrl: null,
            gender: pick(["male", "female", "other", null]),
            bio: faker.lorem.sentence({ min: 5, max: 12 }),
            bannerColor: faker.number.int({ min: 0xff000000, max: 0xffffffff }),
            createdAt,
            lastActiveAt: faker.date.between({ from: createdAt, to: new Date() }),
            score: scores[i],
            totalRequests: faker.number.int({ min: 0, max: 10 }),
            totalJoined: faker.number.int({ min: 0, max: 15 }),
            completedRequests: faker.number.int({ min: 0, max: 8 }),
            cancelledRequests: faker.number.int({ min: 0, max: 3 }),
            rating: faker.number.float({ min: 1, max: 5, fractionDigits: 1 }),
            ratingCount: faker.number.int({ min: 0, max: 20 }),
            verifications: {
                email: verifyEmail,
                phone: verifyPhone,
                identity: false,
            },
            badges: [],
            _seedTag: SEED_TAG,
        });
    }
    await batch.commit();
    console.log(`  ✓ ${TARGETS.profiles} profiles created`);
    return userIds;
}

// ─── Seed: co_requests ───────────────────────────────────────────────────────

async function seedCoRequests(userIds: string[]): Promise<string[]> {
    console.log(`\n→ Seeding ${TARGETS.coRequests} co_requests...`);
    const requestIds: string[] = [];

    // Ensure all 4 statuses and all 8 categories appear: 30 / 4 ≈ 7-8, 30 / 8 ≈ 4
    const statuses: string[] = [];
    for (const s of CO_REQUEST_STATUSES) statuses.push(...Array(7).fill(s));
    while (statuses.length < TARGETS.coRequests) statuses.push(pick(CO_REQUEST_STATUSES));
    faker.helpers.shuffle(statuses);

    const cats: string[] = [];
    for (const c of CATEGORIES) cats.push(...Array(4).fill(c));
    while (cats.length < TARGETS.coRequests) cats.push(pick(CATEGORIES));
    faker.helpers.shuffle(cats);

    const batch = db.batch();
    for (let i = 0; i < TARGETS.coRequests; i++) {
        const docRef = db.collection("co_requests").doc();
        requestIds.push(docRef.id);

        const initiatorId = pick(userIds);
        const partnersNeeded = faker.number.int({ min: 2, max: 5 });
        const totalPrice = faker.number.float({ min: 10, max: 200, fractionDigits: 2 });
        const status = statuses[i];
        const category = cats[i];

        const createdAt = faker.date.between({
            from: new Date("2026-04-01"),
            to: new Date("2026-05-22"),
        });
        // expiresAt: 1h to 7d after createdAt
        const expiresAt = new Date(
            createdAt.getTime() + faker.number.int({ min: 3600_000, max: 7 * 86400_000 })
        );
        const completedAt =
            status === "completed"
                ? faker.date.between({ from: createdAt, to: expiresAt })
                : null;

        const otherCount =
            status === "expired" || status === "cancelled"
                ? faker.number.int({ min: 0, max: Math.max(0, partnersNeeded - 1) })
                : faker.number.int({ min: 0, max: partnersNeeded });
        const otherParticipants = faker.helpers.arrayElements(
            userIds.filter((u) => u !== initiatorId),
            otherCount
        );
        const participants = [initiatorId, ...otherParticipants];

        const city = pickCity();
        const jitter = () => (Math.random() - 0.5) * 0.08;
        const loc = {
            latitude: city.lat + jitter(),
            longitude: city.lng + jitter(),
        };

        batch.set(docRef, {
            initiatorId,
            initiatorName: faker.person.fullName(),
            initiatorPhotoUrl: null,
            productName: faker.commerce.productName(),
            productPhotoUrl: null,
            dealDescription: faker.commerce.productDescription(),
            totalPrice,
            pricePerPerson: parseFloat((totalPrice / (partnersNeeded + 1)).toFixed(2)),
            totalQuantity: faker.number.int({ min: 1, max: 10 }),
            partnersNeeded,
            participants,
            storeName: pick(STORE_NAMES),
            latitude: loc.latitude,
            longitude: loc.longitude,
            storeAddress: `${faker.location.streetAddress()}, ${city.name}, Malaysia`,
            category,
            status,
            notes: faker.lorem.sentence({ min: 4, max: 10 }),
            createdAt,
            expiresAt,
            completedAt,
            _seedTag: SEED_TAG,
        });
    }
    await batch.commit();
    console.log(`  ✓ ${TARGETS.coRequests} co_requests created`);
    return requestIds;
}

// ─── Seed: realtime_matches ──────────────────────────────────────────────────

async function seedRealtimeMatches(
    userIds: string[],
    coRequestIds: string[]
): Promise<void> {
    console.log(`\n→ Seeding ${TARGETS.realtimeMatches} realtime_matches...`);

    // Ensure all 3 statuses: 6/6/6 + 2 extra
    const statuses: string[] = [];
    for (const s of RTM_STATUSES) statuses.push(...Array(6).fill(s));
    while (statuses.length < TARGETS.realtimeMatches) statuses.push(pick(RTM_STATUSES));
    faker.helpers.shuffle(statuses);

    const batch = db.batch();
    for (let i = 0; i < TARGETS.realtimeMatches; i++) {
        const docRef = db.collection("realtime_matches").doc();
        const ownerId = pick(userIds);
        const status = statuses[i];
        const createdAt = faker.date.between({
            from: new Date("2026-04-15"),
            to: new Date("2026-05-22"),
        });
        const expiresAt = new Date(createdAt.getTime() + 24 * 3600_000);
        const maxPartners = pick([1, 2, 3]);
        const loc = randomLatLng();

        const otherCount =
            status === "waiting"
                ? 0
                : faker.number.int({ min: 1, max: maxPartners });
        const otherParticipants = faker.helpers.arrayElements(
            userIds.filter((u) => u !== ownerId),
            otherCount
        );
        const participants = [ownerId, ...otherParticipants];

        // ~50% of closed matches were "converted to cobuy" (= ~16% of all RTMs)
        const converted = status === "closed" && Math.random() < 0.5;

        batch.set(docRef, {
            ownerId,
            ownerName: faker.person.fullName(),
            ownerPhotoUrl: null,
            category: pick(CATEGORIES),
            latitude: loc.latitude,
            longitude: loc.longitude,
            radiusKm: pick([0.5, 1, 2, 5, 10]),
            locationName: `${faker.location.streetAddress()}, Malaysia`,
            participants,
            maxPartners,
            status,
            chatRoomId: status !== "waiting" ? `rtm_${docRef.id}` : null,
            createdAt,
            expiresAt,
            closedReason:
                status === "closed" ? (converted ? "converted_to_cobuy" : "expired") : null,
            convertedToCoBuyId: converted ? pick(coRequestIds) : null,
            closedAt:
                status === "closed"
                    ? faker.date.between({ from: createdAt, to: new Date() })
                    : null,
            _seedTag: SEED_TAG,
        });
    }
    await batch.commit();
    console.log(`  ✓ ${TARGETS.realtimeMatches} realtime_matches created`);
}

// ─── Seed: score_activities ──────────────────────────────────────────────────

async function seedScoreActivities(
    userIds: string[],
    coRequestIds: string[]
): Promise<void> {
    console.log(`\n→ Seeding ${TARGETS.scoreActivities} score_activities...`);

    // Ensure every one of the 11 event types appears at least once
    const events = [...CREDIBILITY_EVENTS];
    while (events.length < TARGETS.scoreActivities) events.push(pick(CREDIBILITY_EVENTS));
    faker.helpers.shuffle(events);

    // 100 < 500 ops, fits in a single batch
    const batch = db.batch();
    for (let i = 0; i < TARGETS.scoreActivities; i++) {
        const userId = pick(userIds);
        const evt = events[i];
        const activityRef = db
            .collection("profiles")
            .doc(userId)
            .collection("score_activities")
            .doc();

        batch.set(activityRef, {
            event: evt.event,
            points: evt.points,
            description: evt.description,
            relatedId: pick(coRequestIds),
            createdAt: faker.date.between({
                from: new Date("2026-04-01"),
                to: new Date("2026-05-22"),
            }),
            _seedTag: SEED_TAG,
        });
    }
    await batch.commit();
    console.log(`  ✓ ${TARGETS.scoreActivities} score_activities created`);
}

// ─── Main ────────────────────────────────────────────────────────────────────

async function main(): Promise<void> {
    console.log("═══════════════════════════════════════════════════════════════");
    console.log("  i-Share Admin Dashboard — Seed Script");
    console.log("═══════════════════════════════════════════════════════════════");
    console.log(`  Project:  ${serviceAccount.project_id}`);
    console.log(`  Tag:      ${SEED_TAG}`);
    console.log(`  Targets:  ${TARGETS.profiles} profiles, ${TARGETS.coRequests} co_requests,`);
    console.log(`            ${TARGETS.realtimeMatches} RTMs, ${TARGETS.scoreActivities} activities`);
    console.log("═══════════════════════════════════════════════════════════════");

    const userIds = await seedProfiles();
    const coRequestIds = await seedCoRequests(userIds);
    await seedRealtimeMatches(userIds, coRequestIds);
    await seedScoreActivities(userIds, coRequestIds);

    console.log("\n═══════════════════════════════════════════════════════════════");
    console.log("  ✅ Seed complete");
    console.log(`  All documents tagged with _seedTag: '${SEED_TAG}'`);
    console.log("  To remove later: npm run wipe");
    console.log("═══════════════════════════════════════════════════════════════\n");
    process.exit(0);
}

main().catch((err) => {
    console.error("\n❌ Seed failed:", err);
    process.exit(1);
});
