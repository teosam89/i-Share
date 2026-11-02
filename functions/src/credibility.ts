/**
 * Credibility Cloud Functions
 * Covers: secure rating submission with participant validation and score calculation.
 */

import * as admin from "firebase-admin";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import { db } from "./lib/firebase";

/**
 * Secure rating submission with participant validation.
 * Ensures rater was actually a participant in the request.
 * Updates average rating and adjusts credibility score.
 */
export const submitRatingSecure = onCall(
    { region: "asia-southeast1" },
    async (request) => {
        if (!request.auth) {
            throw new HttpsError("unauthenticated", "User must be authenticated");
        }

        const { ratedUserId, requestId, rating, comment } = request.data;

        if (!ratedUserId || !requestId || rating === undefined) {
            throw new HttpsError("invalid-argument", "Missing required fields");
        }

        if (rating < 1 || rating > 5) {
            throw new HttpsError("invalid-argument", "Rating must be between 1 and 5");
        }

        const raterId = request.auth.uid;

        if (raterId === ratedUserId) {
            throw new HttpsError("invalid-argument", "Cannot rate yourself");
        }

        try {
            const requestDoc = await db.collection("co_requests").doc(requestId).get();

            if (!requestDoc.exists) {
                throw new HttpsError("not-found", "Request not found");
            }

            const requestData = requestDoc.data()!;
            const participants: string[] = requestData.participants || [];

            if (!participants.includes(raterId)) {
                throw new HttpsError("permission-denied", "You are not a participant of this request");
            }

            if (!participants.includes(ratedUserId)) {
                throw new HttpsError("invalid-argument", "Rated user is not a participant of this request");
            }

            // Prevent duplicate ratings for the same request
            const existingRating = await db.collection("profiles")
                .doc(ratedUserId)
                .collection("ratings")
                .where("fromUserId", "==", raterId)
                .where("requestId", "==", requestId)
                .limit(1)
                .get();

            if (!existingRating.empty) {
                throw new HttpsError("already-exists", "You have already rated this user for this request");
            }

            const raterDoc = await db.collection("profiles").doc(raterId).get();
            const raterName = raterDoc.exists ? raterDoc.data()?.displayName || "User" : "User";

            await db.collection("profiles").doc(ratedUserId).collection("ratings").add({
                fromUserId: raterId,
                fromUserName: raterName,
                toUserId: ratedUserId,
                requestId: requestId,
                rating: rating,
                comment: comment || null,
                createdAt: admin.firestore.FieldValue.serverTimestamp(),
            });

            // Recalculate average rating from all stored ratings
            const allRatings = await db.collection("profiles")
                .doc(ratedUserId)
                .collection("ratings")
                .get();

            let total = 0;
            allRatings.docs.forEach((doc) => { total += doc.data().rating || 0; });
            const avgRating = total / allRatings.size;

            // Map star rating to credibility score delta
            let scoreChange = 0;
            if (rating >= 5) scoreChange = 10;
            else if (rating >= 4) scoreChange = 3;
            else scoreChange = -5;

            await db.collection("profiles").doc(ratedUserId).update({
                rating: avgRating,
                ratingCount: allRatings.size,
                score: admin.firestore.FieldValue.increment(scoreChange),
            });

            console.log(`Rating ${rating} submitted for user ${ratedUserId} by ${raterId}`);
            return { success: true };

        } catch (error) {
            console.error("Error submitting rating:", error);
            if (error instanceof HttpsError) throw error;
            throw new HttpsError("internal", "Failed to submit rating");
        }
    }
);
