/// Firebase Auth UIDs allowed to use the admin dashboard.
///
/// Replace 'REPLACE_WITH_ADMIN_UID' with the UID(s) of your admin account(s)
/// (Firebase Console > Authentication > Users). The same UIDs must be listed in
/// `firestore.rules` (function isAdmin) - the rules are the real enforcement;
/// this list only decides what the UI shows.
class AdminConstants {
  static const List<String> adminUids = [
    'REPLACE_WITH_ADMIN_UID',
  ];

  static bool isAdmin(String? uid) =>
      uid != null && adminUids.contains(uid);
}
