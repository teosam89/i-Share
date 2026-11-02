/**
 * i-Share Admin Dashboard — Wipe Script
 *
 * Deletes ONLY documents tagged with `_seedTag: 'fyp-demo-2026'` from:
 *   - profiles
 *   - co_requests
 *   - realtime_matches
 *   - score_activities (via collectionGroup query, since they live under profiles/{uid}/)
 *
 * Real user data (without the seed tag) is NOT touched.
 *
 * Usage:
 *   npm run wipe
 */

import * as admin from "firebase-admin";
import * as fs from "fs";
import * as path from "path";
import * as readline from "readline";

const SEED_TAG = "fyp-demo-2026";
const BATCH_LIMIT = 500;

// ─── Bootstrap Firebase Admin ────────────────────────────────────────────────

const keyPath = path.join(__dirname, "service-account-key.json");
if (!fs.existsSync(keyPath)) {
    console.error("\n❌ service-account-key.json not found.\n");
    console.error("   See README.md for how to download it.\n");
    process.exit(1);
}
const serviceAccount = require(keyPath);
admin.initializeApp({
    credential: admin.credential.cert(serviceAccount),
    projectId: serviceAccount.project_id,
});
const db = admin.firestore();

// ─── Helpers ─────────────────────────────────────────────────────────────────

async function promptConfirm(question: string): Promise<boolean> {
    const rl = readline.createInterface({ input: process.stdin, output: process.stdout });
    return new Promise((resolve) => {
        rl.question(`${question} (yes/no): `, (answer) => {
            rl.close();
            resolve(answer.trim().toLowerCase() === "yes");
        });
    });
}

async function wipe(
    label: string,
    query: FirebaseFirestore.Query
): Promise<number> {
    process.stdout.write(`  ${label} ... `);
    const snap = await query.where("_seedTag", "==", SEED_TAG).get();
    if (snap.empty) {
        console.log("(0 docs)");
        return 0;
    }
    let deleted = 0;
    for (let i = 0; i < snap.docs.length; i += BATCH_LIMIT) {
        const batch = db.batch();
        const chunk = snap.docs.slice(i, i + BATCH_LIMIT);
        chunk.forEach((d) => batch.delete(d.ref));
        await batch.commit();
        deleted += chunk.length;
    }
    console.log(`${deleted} deleted`);
    return deleted;
}

/**
 * Wipe score_activities without using a collectionGroup query (which would
 * require a Firestore composite index on `_seedTag`). Instead, enumerate
 * tagged profiles and run a single-field query within each profile's
 * subcollection — those don't need an index.
 */
async function wipeScoreActivities(): Promise<number> {
    process.stdout.write(`  score_activities (per-profile)     ... `);
    const profilesSnap = await db
        .collection("profiles")
        .where("_seedTag", "==", SEED_TAG)
        .get();
    if (profilesSnap.empty) {
        console.log("(0 profiles tagged)");
        return 0;
    }
    let total = 0;
    for (const profileDoc of profilesSnap.docs) {
        const subSnap = await profileDoc.ref
            .collection("score_activities")
            .where("_seedTag", "==", SEED_TAG)
            .get();
        if (subSnap.empty) continue;
        for (let i = 0; i < subSnap.docs.length; i += BATCH_LIMIT) {
            const batch = db.batch();
            const chunk = subSnap.docs.slice(i, i + BATCH_LIMIT);
            chunk.forEach((d) => batch.delete(d.ref));
            await batch.commit();
            total += chunk.length;
        }
    }
    console.log(`${total} deleted (scanned ${profilesSnap.size} profiles)`);
    return total;
}

// ─── Main ────────────────────────────────────────────────────────────────────

async function main(): Promise<void> {
    console.log("═══════════════════════════════════════════════════════════════");
    console.log("  i-Share Admin Dashboard — Wipe Script");
    console.log("═══════════════════════════════════════════════════════════════");
    console.log(`  Project:  ${serviceAccount.project_id}`);
    console.log(`  Tag:      ${SEED_TAG}`);
    console.log(`  Target:   ALL documents with _seedTag = '${SEED_TAG}'`);
    console.log(`            (real user data is NOT touched)`);
    console.log("═══════════════════════════════════════════════════════════════\n");

    const ok = await promptConfirm("Proceed with wipe?");
    if (!ok) {
        console.log("\nAborted.\n");
        process.exit(0);
    }

    console.log("\n→ Deleting seed data...\n");

    let total = 0;
    // Order matters: wipe score_activities FIRST while parent profiles still
    // exist (we enumerate via the parent profile docs to avoid needing a
    // collectionGroup index on `_seedTag`).
    total += await wipeScoreActivities();
    total += await wipe("co_requests                        ", db.collection("co_requests"));
    total += await wipe("realtime_matches                   ", db.collection("realtime_matches"));
    total += await wipe("profiles                           ", db.collection("profiles"));

    console.log("\n═══════════════════════════════════════════════════════════════");
    console.log(`  ✅ Wipe complete — ${total} documents deleted`);
    console.log("═══════════════════════════════════════════════════════════════\n");
    process.exit(0);
}

main().catch((err) => {
    console.error("\n❌ Wipe failed:", err);
    process.exit(1);
});
