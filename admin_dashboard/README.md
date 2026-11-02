# i-Share Admin Dashboard

A Flutter web app with charts and tables over the aggregated data of the i-Share app (user growth, request
categories, credibility distribution). Only whitelisted admin accounts can open it; the Firestore rules
(`../firestore.rules`, function `isAdmin`) are the real enforcement.

## Setup

1. Create a Web app in your Firebase project and generate the options file, or copy the template and fill it in:
   `lib/firebase_options.dart.example` to `lib/firebase_options.dart` (git-ignored).
2. Put your admin UID in `lib/core/admin_constants.dart` and in `../firestore.rules`
   (replace `REPLACE_WITH_ADMIN_UID`).
3. **Maps API key.** `web/index.html` contains the placeholder `__GOOGLE_MAPS_API_KEY__`, so no key is stored in
   the repository. Inject your (restricted) browser key into the built output, not into the source:

   ```
   flutter pub get
   flutter build web
   # bash
   sed -i 's/__GOOGLE_MAPS_API_KEY__/YOUR_KEY/' build/web/index.html
   # PowerShell
   (Get-Content build/web/index.html) -replace '__GOOGLE_MAPS_API_KEY__','YOUR_KEY' | Set-Content build/web/index.html
   ```

   For `flutter run -d chrome`, temporarily replace the placeholder in `web/index.html` and do not commit it.
4. Deploy the contents of `build/web` with Firebase Hosting (the root `firebase.json` has a hosting entry that
   points at `admin_dashboard/build/web`; link your own site with `firebase target:apply hosting admin <site-id>`).

## Demo data

`seed/` contains scripts that create and remove synthetic demo documents. See [`seed/README.md`](seed/README.md).
