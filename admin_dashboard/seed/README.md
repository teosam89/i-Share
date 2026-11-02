# Admin Dashboard — Seed Scripts

Creates and removes fake demo data for the i-Share Admin Dashboard demo.

## What this seeds

- **50 profiles** — credibility distribution 60% User / 30% Trusted / 10% Elite
- **30 co_requests** — all 4 statuses (active/completed/expired/cancelled) and all 5 categories (food/household/electronics/personal/others). Locations spread across KL.
- **20 realtime_matches** — all 3 statuses, with ~15% of total marked `closedReason: 'converted_to_cobuy'`
- **100 score_activities** — distributed across users; all 11 credibility event types present

Every seeded document carries `_seedTag: 'fyp-demo-2026'`. Wipe targets only docs with this tag — your real user data is never touched.

---

## One-time setup

### 1. Download a service account key

Firestore Admin SDK needs a private key to bypass security rules during seeding.

1. Open the Firebase Console → [Service Accounts](https://console.firebase.google.com/project/your-firebase-project-id/settings/serviceaccounts/adminsdk) for the `your-firebase-project-id` project.
2. Click **Generate new private key** → confirm. A JSON file downloads.
3. Rename it to **`service-account-key.json`** and place it in **this directory** (`admin_dashboard/seed/`).
4. It is gitignored — **never commit it**. It is equivalent to root credentials for your Firebase project.

### 2. Install Node dependencies

From this directory:

```bash
cd admin_dashboard/seed
npm install
```

Requires Node.js 20+. If `npm install` fails, check your Node version with `node --version`.

---

## Commands

### Seed

```bash
npm run seed
```

Takes ~10 seconds. Output ends with:
```
✅ Seed complete
   All documents tagged with _seedTag: 'fyp-demo-2026'
```

You can run `npm run seed` multiple times — each run creates a fresh batch (it does NOT replace previous seed data). If you want a clean slate, run `npm run wipe` first.

### Wipe

```bash
npm run wipe
```

Prompts for `yes` confirmation, then deletes all docs with `_seedTag = 'fyp-demo-2026'`.
Takes ~5 seconds.

---

## After the demo — cleanup checklist

1. Run `npm run wipe`
2. Delete `service-account-key.json` from this directory
3. In Firebase Console, **revoke** the service account key (Service Accounts → ⋮ → Delete key)
4. (Optional) Remove your admin UID from `firestore.rules` and redeploy

---

## Troubleshooting

| Error | Fix |
|---|---|
| `service-account-key.json not found` | Did you place the file in `admin_dashboard/seed/`, not elsewhere? |
| `PERMISSION_DENIED` | The key is for the wrong project. Make sure you downloaded it from `your-firebase-project-id`. |
| `Quota exceeded` | You hit Firebase free-tier limits. Wait a few minutes and re-run. Targets stay safely under daily quota. |
| `Cannot find module '@faker-js/faker'` | Run `npm install` first. |
