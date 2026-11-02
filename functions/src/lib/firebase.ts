/**
 * Shared Firebase Admin initialization.
 * Import this module first to ensure initializeApp() runs before any other Firebase call.
 */

import * as admin from "firebase-admin";
import { setGlobalOptions } from "firebase-functions/v2";

admin.initializeApp();
setGlobalOptions({ region: "asia-southeast1" }); // Closest to Malaysia

export const db = admin.firestore();
export const messaging = admin.messaging();
