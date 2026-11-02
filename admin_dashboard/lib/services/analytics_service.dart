import 'package:cloud_firestore/cloud_firestore.dart';

class UserMonthPoint {
  final String label;
  final int count;
  UserMonthPoint(this.label, this.count);
}

class DayPoint {
  final DateTime date;
  final int count;
  DayPoint(this.date, this.count);
}

class StoreCount {
  final String name;
  final int count;
  StoreCount(this.name, this.count);
}

class MapPoint {
  final double lat;
  final double lng;
  final String status;
  final String category;
  final String productName;
  final String storeName;
  final DateTime? createdAt;
  MapPoint({
    required this.lat,
    required this.lng,
    required this.status,
    required this.category,
    required this.productName,
    required this.storeName,
    this.createdAt,
  });
}

class ProfileSnap {
  final DateTime? createdAt;
  final double score;
  const ProfileSnap(this.createdAt, this.score);
}

class CoRequestSnap {
  final DateTime? createdAt;
  final String status;
  final String category;
  final String storeName;
  final String productName;
  final double? latitude;
  final double? longitude;
  final int participantCount;
  const CoRequestSnap({
    required this.createdAt,
    required this.status,
    required this.category,
    required this.storeName,
    required this.productName,
    required this.latitude,
    required this.longitude,
    required this.participantCount,
  });
}

class RtmSnap {
  final DateTime? createdAt;
  final bool converted;
  const RtmSnap(this.createdAt, this.converted);
}

class ScoreSnap {
  final DateTime? createdAt;
  final String event;
  const ScoreSnap(this.createdAt, this.event);
}

class MetricsSnapshot {
  final int totalUsers;
  final int totalCoRequests;
  final int completedCoRequests;
  final int totalRtms;
  final int convertedRtms;
  final double avgGroupSize;

  const MetricsSnapshot({
    required this.totalUsers,
    required this.totalCoRequests,
    required this.completedCoRequests,
    required this.totalRtms,
    required this.convertedRtms,
    required this.avgGroupSize,
  });

  double get completionRate =>
      totalCoRequests == 0 ? 0 : completedCoRequests / totalCoRequests;

  double get rtmConversionRate =>
      totalRtms == 0 ? 0 : convertedRtms / totalRtms;
}

class DashboardData {
  final DateTime fetchedAt;

  // Raw snap lists — every chart's data is derived from these at render time.
  final List<ProfileSnap> _profiles;
  final List<CoRequestSnap> _coRequests;
  final List<RtmSnap> _rtms;
  final List<ScoreSnap> _scoreActivities;

  DashboardData({
    required this.fetchedAt,
    required List<ProfileSnap> profiles,
    required List<CoRequestSnap> coRequests,
    required List<RtmSnap> rtms,
    required List<ScoreSnap> scoreActivities,
  })  : _profiles = profiles,
        _coRequests = coRequests,
        _rtms = rtms,
        _scoreActivities = scoreActivities;

  // ─── Filter helper ──────────────────────────────────────────────────────────

  bool _inRange(DateTime? t, int? days) {
    if (days == null) return true;
    if (t == null) return false;
    final cutoff = DateTime.now().subtract(Duration(days: days));
    return !t.isBefore(cutoff);
  }

  // ─── Filtered raw accessors (used by charts that need raw lists) ───────────

  List<ProfileSnap> profilesIn({int? days}) =>
      _profiles.where((p) => _inRange(p.createdAt, days)).toList();

  List<CoRequestSnap> coRequestsIn({int? days}) =>
      _coRequests.where((c) => _inRange(c.createdAt, days)).toList();

  List<RtmSnap> rtmsIn({int? days}) =>
      _rtms.where((r) => _inRange(r.createdAt, days)).toList();

  List<ScoreSnap> scoreActivitiesIn({int? days}) =>
      _scoreActivities.where((s) => _inRange(s.createdAt, days)).toList();

  // ─── Aggregations (parameterized by days) ───────────────────────────────────

  MetricsSnapshot metricsFor({int? days}) {
    final profs = profilesIn(days: days);
    final crs = coRequestsIn(days: days);
    final rtms = rtmsIn(days: days);

    final completed = crs.where((c) => c.status == 'completed').length;
    final converted = rtms.where((r) => r.converted).length;

    double avg = 0;
    final withP = crs.where((c) => c.participantCount > 0).toList();
    if (withP.isNotEmpty) {
      avg = withP.map((c) => c.participantCount).reduce((a, b) => a + b) /
          withP.length;
    }

    return MetricsSnapshot(
      totalUsers: profs.length,
      totalCoRequests: crs.length,
      completedCoRequests: completed,
      totalRtms: rtms.length,
      convertedRtms: converted,
      avgGroupSize: avg,
    );
  }

  Map<String, int> categoryCounts({int? days}) {
    final out = <String, int>{};
    for (final c in coRequestsIn(days: days)) {
      out[c.category] = (out[c.category] ?? 0) + 1;
    }
    return out;
  }

  Map<String, int> statusCounts({int? days}) {
    final out = <String, int>{
      'active': 0, 'completed': 0, 'expired': 0, 'cancelled': 0,
    };
    for (final c in coRequestsIn(days: days)) {
      if (out.containsKey(c.status)) {
        out[c.status] = out[c.status]! + 1;
      }
    }
    return out;
  }

  List<StoreCount> topStores({int? days, int limit = 5}) {
    final buckets = <String, int>{};
    for (final c in coRequestsIn(days: days)) {
      final s = c.storeName.trim();
      if (s.isEmpty) continue;
      buckets[s] = (buckets[s] ?? 0) + 1;
    }
    return (buckets.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value)))
        .take(limit)
        .map((e) => StoreCount(e.key, e.value))
        .toList();
  }

  Map<String, int> scoreDistribution({int? days}) {
    final out = <String, int>{'User': 0, 'Trusted': 0, 'Elite': 0};
    for (final p in profilesIn(days: days)) {
      final tier = p.score >= 700
          ? 'Elite'
          : p.score >= 300
              ? 'Trusted'
              : 'User';
      out[tier] = out[tier]! + 1;
    }
    return out;
  }

  Map<String, int> scoreEventCounts({int? days}) {
    final out = <String, int>{};
    for (final s in scoreActivitiesIn(days: days)) {
      out[s.event] = (out[s.event] ?? 0) + 1;
    }
    return out;
  }

  List<MapPoint> mapPoints({int? days}) {
    return coRequestsIn(days: days)
        .where((c) =>
            c.latitude != null &&
            c.longitude != null &&
            c.latitude != 0 &&
            c.longitude != 0)
        .map((c) => MapPoint(
              lat: c.latitude!,
              lng: c.longitude!,
              status: c.status,
              category: c.category,
              productName: c.productName,
              storeName: c.storeName,
              createdAt: c.createdAt,
            ))
        .toList();
  }

  /// Daily buckets, default 30 days when filter is all-time.
  List<DayPoint> coRequestsPerDay({int? days}) {
    final bucketCount = days ?? 30;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final buckets = <DateTime, int>{};
    for (int i = bucketCount - 1; i >= 0; i--) {
      buckets[today.subtract(Duration(days: i))] = 0;
    }
    for (final c in coRequestsIn(days: bucketCount)) {
      final d = c.createdAt;
      if (d == null) continue;
      final b = DateTime(d.year, d.month, d.day);
      if (buckets.containsKey(b)) buckets[b] = buckets[b]! + 1;
    }
    return buckets.entries
        .map((e) => DayPoint(e.key, e.value))
        .toList()
      ..sort((a, b) => a.date.compareTo(b.date));
  }

  /// User-growth time series. Bucket granularity adapts to the window:
  /// <=14d daily, <=90d weekly, otherwise monthly (6 buckets for "all time").
  List<UserMonthPoint> newUsersTimeSeries({int? days}) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    if (days != null && days <= 14) {
      // Daily buckets
      final buckets = <DateTime, int>{};
      for (int i = days - 1; i >= 0; i--) {
        buckets[today.subtract(Duration(days: i))] = 0;
      }
      for (final p in profilesIn(days: days)) {
        final d = p.createdAt;
        if (d == null) continue;
        final b = DateTime(d.year, d.month, d.day);
        if (buckets.containsKey(b)) buckets[b] = buckets[b]! + 1;
      }
      return buckets.entries
          .map((e) => UserMonthPoint(_dayLabel(e.key), e.value))
          .toList()
        ..sort((a, b) => a.label.compareTo(b.label));
    }

    if (days != null && days <= 90) {
      // Weekly buckets
      final weekCount = (days / 7).ceil();
      final buckets = <DateTime, int>{};
      for (int i = weekCount - 1; i >= 0; i--) {
        buckets[today.subtract(Duration(days: i * 7))] = 0;
      }
      final boundaries = buckets.keys.toList()..sort();
      for (final p in profilesIn(days: days)) {
        final d = p.createdAt;
        if (d == null) continue;
        // Find latest boundary <= d
        DateTime? chosen;
        for (final b in boundaries) {
          if (!b.isAfter(d)) chosen = b;
        }
        if (chosen != null) buckets[chosen] = buckets[chosen]! + 1;
      }
      return boundaries
          .map((b) => UserMonthPoint(_dayLabel(b), buckets[b]!))
          .toList();
    }

    // Monthly buckets — last 6 months (default for "all time")
    final months = days == null ? 6 : (days / 30).ceil().clamp(2, 24).toInt();
    final out = <UserMonthPoint>[];
    for (int i = months - 1; i >= 0; i--) {
      final m = DateTime(now.year, now.month - i, 1);
      final next = DateTime(m.year, m.month + 1, 1);
      final count = _profiles
          .where((p) =>
              p.createdAt != null &&
              !p.createdAt!.isBefore(m) &&
              p.createdAt!.isBefore(next))
          .length;
      out.add(UserMonthPoint(_monthLabel(m), count));
    }
    return out;
  }

  String _monthLabel(DateTime d) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
                    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${months[d.month - 1]} ${d.year.toString().substring(2)}';
  }

  String _dayLabel(DateTime d) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
                    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${d.day} ${months[d.month - 1]}';
  }
}

class TableRawData {
  final List<Map<String, dynamic>> profiles;
  final List<Map<String, dynamic>> coRequests;
  final List<Map<String, dynamic>> realtimeMatches;
  final List<Map<String, dynamic>> scoreActivities;

  TableRawData({
    required this.profiles,
    required this.coRequests,
    required this.realtimeMatches,
    required this.scoreActivities,
  });
}

class AnalyticsService {
  static final _db = FirebaseFirestore.instance;

  // 8 official keys — see lib/features/co_request/models/co_request_model.dart
  static const _knownCategories = {
    'groceries', 'fresh', 'snacks', 'household',
    'personal', 'baby_pets', 'electronics', 'others',
  };

  static String _normalizeCategory(String? raw) {
    if (raw == null) return 'others';
    return _knownCategories.contains(raw) ? raw : 'others';
  }

  static DateTime? _asDate(dynamic v) => v is Timestamp ? v.toDate() : null;

  static Future<DashboardData> load() async {
    final results = await Future.wait([
      _db.collection('profiles').get(),
      _db.collection('co_requests').get(),
      _db.collection('realtime_matches').get(),
      _db.collectionGroup('score_activities').get(),
    ]);

    final profileSnaps = results[0].docs.map((d) {
      final data = d.data();
      return ProfileSnap(
        _asDate(data['createdAt']),
        ((data['score'] as num?) ?? 0).toDouble(),
      );
    }).toList();

    final coRequestSnaps = results[1].docs.map((d) {
      final data = d.data();
      final list = data['participants'] as List?;
      return CoRequestSnap(
        createdAt: _asDate(data['createdAt']),
        status: (data['status'] as String?) ?? 'active',
        category: _normalizeCategory(data['category'] as String?),
        storeName: (data['storeName'] as String?) ?? '',
        productName: (data['productName'] as String?) ?? '',
        latitude: (data['latitude'] as num?)?.toDouble(),
        longitude: (data['longitude'] as num?)?.toDouble(),
        participantCount: list?.length ?? 0,
      );
    }).toList();

    final rtmSnaps = results[2].docs.map((d) {
      final data = d.data();
      return RtmSnap(
        _asDate(data['createdAt']),
        data['convertedToCoBuyId'] != null,
      );
    }).toList();

    final scoreSnaps = results[3].docs.map((d) {
      final data = d.data();
      return ScoreSnap(
        _asDate(data['createdAt']),
        (data['event'] as String?) ?? 'unknown',
      );
    }).toList();

    return DashboardData(
      fetchedAt: DateTime.now(),
      profiles: profileSnaps,
      coRequests: coRequestSnaps,
      rtms: rtmSnaps,
      scoreActivities: scoreSnaps,
    );
  }

  static Future<TableRawData> loadTableData() async {
    final results = await Future.wait([
      _db.collection('profiles').get(),
      _db.collection('co_requests').get(),
      _db.collection('realtime_matches').get(),
      _db.collectionGroup('score_activities').get(),
    ]);

    Map<String, dynamic> withId(QueryDocumentSnapshot doc) => {
      '__id': doc.id,
      ...(doc.data() as Map<String, dynamic>? ?? {}),
    };

    Map<String, dynamic> withIdNormalized(QueryDocumentSnapshot doc) {
      final m = withId(doc);
      if (m['category'] is String) {
        m['category'] = _normalizeCategory(m['category'] as String);
      }
      return m;
    }

    return TableRawData(
      profiles: results[0].docs.map(withId).toList(),
      coRequests: results[1].docs.map(withIdNormalized).toList(),
      realtimeMatches: results[2].docs.map(withIdNormalized).toList(),
      scoreActivities: results[3].docs.map((doc) => {
        '__id': doc.id,
        '__userId': doc.reference.parent.parent?.id ?? '',
        ...(doc.data() as Map<String, dynamic>? ?? {}),
      }).toList(),
    );
  }
}
