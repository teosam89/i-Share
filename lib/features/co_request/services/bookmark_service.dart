import 'package:shared_preferences/shared_preferences.dart';

/// Local bookmark service using SharedPreferences.
/// Stores bookmarked request IDs for quick access.
class BookmarkService {
  static const _key = 'bookmarked_requests';

  static BookmarkService? _instance;
  SharedPreferences? _prefs;

  BookmarkService._();
  factory BookmarkService() => _instance ??= BookmarkService._();

  Future<SharedPreferences> get _preferences async {
    return _prefs ??= await SharedPreferences.getInstance();
  }

  Future<Set<String>> getBookmarks() async {
    final prefs = await _preferences;
    return (prefs.getStringList(_key) ?? []).toSet();
  }

  Future<bool> isBookmarked(String requestId) async {
    final bookmarks = await getBookmarks();
    return bookmarks.contains(requestId);
  }

  Future<void> toggle(String requestId) async {
    final prefs = await _preferences;
    final bookmarks = (prefs.getStringList(_key) ?? []).toSet();
    if (bookmarks.contains(requestId)) {
      bookmarks.remove(requestId);
    } else {
      bookmarks.add(requestId);
    }
    await prefs.setStringList(_key, bookmarks.toList());
  }
}
