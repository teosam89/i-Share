import 'package:flutter_test/flutter_test.dart';
import 'package:i_share/features/co_request/services/geohash_util.dart';

void main() {
  // Ipoh, Malaysia — a representative coordinate for the target market.
  const lat = 4.5975;
  const lng = 101.0901;

  group('GeoHashUtil.encode', () {
    test('produces a hash of the requested precision', () {
      expect(GeoHashUtil.encode(lat, lng, precision: 7).length, 7);
      expect(GeoHashUtil.encode(lat, lng, precision: 5).length, 5);
    });

    test('is deterministic for the same input', () {
      expect(
        GeoHashUtil.encode(lat, lng, precision: 7),
        GeoHashUtil.encode(lat, lng, precision: 7),
      );
    });

    test('a lower precision hash is a prefix of a higher precision hash', () {
      final p5 = GeoHashUtil.encode(lat, lng, precision: 5);
      final p7 = GeoHashUtil.encode(lat, lng, precision: 7);
      expect(p7.startsWith(p5), isTrue);
    });

    test('uses only base-32 geohash characters', () {
      final hash = GeoHashUtil.encode(lat, lng, precision: 9);
      expect(RegExp(r'^[0123456789bcdefghjkmnpqrstuvwxyz]+$').hasMatch(hash),
          isTrue);
    });
  });

  group('GeoHashUtil.decodeBounds', () {
    test('bounding box contains the original point', () {
      final hash = GeoHashUtil.encode(lat, lng, precision: 7);
      final b = GeoHashUtil.decodeBounds(hash);
      expect(lat, greaterThanOrEqualTo(b.minLat));
      expect(lat, lessThanOrEqualTo(b.maxLat));
      expect(lng, greaterThanOrEqualTo(b.minLng));
      expect(lng, lessThanOrEqualTo(b.maxLng));
    });

    test('higher precision yields a tighter box', () {
      final coarse = GeoHashUtil.decodeBounds(
          GeoHashUtil.encode(lat, lng, precision: 4));
      final fine = GeoHashUtil.decodeBounds(
          GeoHashUtil.encode(lat, lng, precision: 7));
      final coarseHeight = coarse.maxLat - coarse.minLat;
      final fineHeight = fine.maxLat - fine.minLat;
      expect(fineHeight, lessThan(coarseHeight));
    });
  });

  group('GeoHashUtil.neighborsOf', () {
    test('returns at most nine unique, equal-length cells', () {
      final cells = GeoHashUtil.neighborsOf(lat, lng, 6);
      expect(cells.length, lessThanOrEqualTo(9));
      expect(cells.toSet().length, cells.length); // all unique
      expect(cells.every((c) => c.length == 6), isTrue);
    });

    test('includes the centre cell', () {
      final centre = GeoHashUtil.encode(lat, lng, precision: 6);
      expect(GeoHashUtil.neighborsOf(lat, lng, 6), contains(centre));
    });
  });

  group('GeoHashUtil.queryRanges', () {
    test('returns non-empty ranges with start <= end', () {
      final ranges = GeoHashUtil.queryRanges(lat, lng, precision: 5);
      expect(ranges, isNotEmpty);
      for (final r in ranges) {
        expect(r.start.compareTo(r.end) <= 0, isTrue);
      }
    });

    test('covers the centre cell within one of its ranges', () {
      final centre = GeoHashUtil.encode(lat, lng, precision: 5);
      final ranges = GeoHashUtil.queryRanges(lat, lng, precision: 5);
      final covered = ranges.any(
        (r) => centre.compareTo(r.start) >= 0 && centre.compareTo(r.end) < 0,
      );
      expect(covered, isTrue);
    });
  });

  group('GeoHashUtil.queryPrecisionForRadius', () {
    test('always returns a valid precision in the supported range', () {
      for (final radius in <double>[50, 500, 1000, 5000, 10000]) {
        final p = GeoHashUtil.queryPrecisionForRadius(radius);
        expect(p, inInclusiveRange(1, 9));
      }
    });
  });
}
