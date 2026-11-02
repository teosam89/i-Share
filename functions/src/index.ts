/**
 * i-Share Cloud Functions — Entry Point
 *
 * This file only re-exports from domain modules.
 * All logic lives in: co-requests.ts, rtm.ts, chat.ts, credibility.ts
 *
 * Firebase Admin SDK is initialized via the side-effect import below,
 * which must run before any other Firebase call.
 */

// Initialize Firebase Admin SDK (side-effect: initializeApp + setGlobalOptions)
import "./lib/firebase";

// ── Co-Request domain (9 functions) ──
export {
    onNewRequest,
    onCoRequestUpdated,
    onPendingJoinRequest,
    onJoinRequestApproved,
    acceptJoinRequestSecure,
    leaveRequestSecure,
    verifyQrCodeSecure,
    cleanupExpiredRequests,
} from "./co-requests";

// ── RTM domain (4 functions) ──
export {
    onRTMMatchFound,
    leaveRealtimeMatchSecure,
    cleanupExpiredMatches,
    cleanupOldRealtimeMatches,
} from "./rtm";

// ── Chat domain (1 function) ──
export { onNewChatMessage } from "./chat";

// ── Credibility domain (1 function) ──
export { submitRatingSecure } from "./credibility";

/*
 * REMOVED: closeExpiredCoRequests
 * Reason: Duplicate of cleanupExpiredRequests — ran hourly alongside it and lacked
 * the "full request" exemption logic, causing incorrect expiry of full co-requests.
 *
 * ACTION REQUIRED after deploying: delete the old function from Firebase:
 *   firebase functions:delete closeExpiredCoRequests --region asia-southeast1
 */
