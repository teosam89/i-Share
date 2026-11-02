/// Geohash encoding and query utilities for Firestore geo-queries.
///
/// Geohash divides the world into a grid of cells identified by short strings.
/// Longer strings = smaller cells = higher precision.
///
/// Precision guide (approximate cell dimensions):
///   4 → ~20km  |  5 → ~5km  |  6 → ~1.2km  |  7 → ~150m
///
/// Strategy:
///   - Store at precision 7 (~150m) for accurate positioning
///   - Query at precision 5 (~5km) for nearby feed — single Firestore range query
///   - Client-side Haversine filters exact distance after Firestore returns results
class GeoHashUtil {
  GeoHashUtil._();

  static const _base32 = '0123456789bcdefghjkmnpqrstuvwxyz';

  /// Default storage precision (~150m cells)
  static const int storagePrecision = 7;

  /// Default query precision (~5km cells, suitable for university/local area)
  static const int defaultQueryPrecision = 5;

  // Approximate cell dimensions in meters per precision level
  // Used to auto-select query precision from a radius
  static const _precisionMeters = <int, double>{
    1: 5000000,
    2: 1250000,
    3: 156000,
    4: 39100,
    5: 4900,
    6: 1200,
    7: 153,
    8: 38,
    9: 5,
  };

  /// Encode (lat, lng) to a geohash string.
  ///
  /// Uses the standard geohash algorithm: alternating longitude/latitude bits
  /// packed into base-32 characters.
  static String encode(double lat, double lng, {int precision = storagePrecision}) {
    assert(precision >= 1 && precision <= 12, 'Precision must be 1-12');

    double minLat = -90, maxLat = 90;
    double minLng = -180, maxLng = 180;
    bool isLng = true;
    int bits = 0;
    int charIndex = 0;
    final buffer = StringBuffer();

    while (buffer.length < precision) {
      if (isLng) {
        final mid = (minLng + maxLng) / 2;
        if (lng >= mid) {
          charIndex = charIndex * 2 + 1;
          minLng = mid;
        } else {
          charIndex = charIndex * 2;
          maxLng = mid;
        }
      } else {
        final mid = (minLat + maxLat) / 2;
        if (lat >= mid) {
          charIndex = charIndex * 2 + 1;
          minLat = mid;
        } else {
          charIndex = charIndex * 2;
          maxLat = mid;
        }
      }
      isLng = !isLng;
      bits++;
      if (bits == 5) {
        buffer.write(_base32[charIndex]);
        bits = 0;
        charIndex = 0;
      }
    }
    return buffer.toString();
  }

  /// Decode a geohash string back to a bounding box.
  ///
  /// Returns (minLat, minLng, maxLat, maxLng).
  static ({double minLat, double minLng, double maxLat, double maxLng}) decodeBounds(
    String hash,
  ) {
    double minLat = -90, maxLat = 90;
    double minLng = -180, maxLng = 180;
    bool isLng = true;

    for (int i = 0; i < hash.length; i++) {
      final charIndex = _base32.indexOf(hash[i]);
      for (int bit = 4; bit >= 0; bit--) {
        if (isLng) {
          final mid = (minLng + maxLng) / 2;
          if ((charIndex >> bit) & 1 == 1) {
            minLng = mid;
          } else {
            maxLng = mid;
          }
        } else {
          final mid = (minLat + maxLat) / 2;
          if ((charIndex >> bit) & 1 == 1) {
            minLat = mid;
          } else {
            maxLat = mid;
          }
        }
        isLng = !isLng;
      }
    }
    return (minLat: minLat, minLng: minLng, maxLat: maxLat, maxLng: maxLng);
  }

  /// Select the best query precision for a given search radius.
  ///
  /// Returns the finest precision whose cell size still covers [radiusMeters].
  static int queryPrecisionForRadius(double radiusMeters) {
    for (int p = 9; p >= 1; p--) {
      if (_precisionMeters[p]! <= radiusMeters) return p;
    }
    return 1;
  }

  /// Get the 9 geohash cells (center + 8 neighbors) around a point.
  ///
  /// Uses coordinate-based neighbor calculation: decode cell bounds,
  /// offset by cell dimensions, re-encode.
  static List<String> neighborsOf(double lat, double lng, int precision) {
    final center = encode(lat, lng, precision: precision);
    final box = decodeBounds(center);
    final cellH = box.maxLat - box.minLat;
    final cellW = box.maxLng - box.minLng;
    final cLat = (box.minLat + box.maxLat) / 2;
    final cLng = (box.minLng + box.maxLng) / 2;

    final hashes = <String>{};
    for (final dLat in [-cellH, 0.0, cellH]) {
      for (final dLng in [-cellW, 0.0, cellW]) {
        final nLat = (cLat + dLat).clamp(-90.0, 90.0);
        final nLng = (cLng + dLng).clamp(-180.0, 180.0);
        hashes.add(encode(nLat, nLng, precision: precision));
      }
    }
    return hashes.toList()..sort();
  }

  /// Get Firestore query ranges that cover all 9 cells around a point.
  ///
  /// Merges consecutive geohash prefixes into minimal ranges to reduce
  /// the number of Firestore queries needed.
  ///
  /// Each range is a (start, end) pair for:
  ///   `.where('geohash', isGreaterThanOrEqualTo: start)`
  ///   `.where('geohash', isLessThan: end)`
  static List<({String start, String end})> queryRanges(
    double lat,
    double lng, {
    int? precision,
    double? radiusMeters,
  }) {
    final p = precision ?? (radiusMeters != null ? queryPrecisionForRadius(radiusMeters) : defaultQueryPrecision);
    final hashes = neighborsOf(lat, lng, p);

    // Merge consecutive hashes into ranges
    final ranges = <({String start, String end})>[];
    var rangeStart = hashes[0];
    var rangePrev = hashes[0];

    for (int i = 1; i < hashes.length; i++) {
      if (_areAdjacent(rangePrev, hashes[i])) {
        rangePrev = hashes[i];
      } else {
        ranges.add((start: rangeStart, end: '$rangePrev~'));
        rangeStart = hashes[i];
        rangePrev = hashes[i];
      }
    }
    ranges.add((start: rangeStart, end: '$rangePrev~'));
    return ranges;
  }

  /// Check if two sorted geohash strings are lexicographically adjacent.
  ///
  /// Two hashes are adjacent if they differ only in the last character,
  /// and that character is exactly one step apart in base-32.
  static bool _areAdjacent(String a, String b) {
    if (a.length != b.length) return false;
    // Check all chars except last are identical
    final prefix = a.length - 1;
    if (a.substring(0, prefix) != b.substring(0, prefix)) return false;

    final idxA = _base32.indexOf(a[prefix]);
    final idxB = _base32.indexOf(b[prefix]);
    return (idxB - idxA) == 1;
  }
}
