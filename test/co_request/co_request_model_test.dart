import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:i_share/core/constants/request_status.dart';
import 'package:i_share/features/co_request/models/co_request_model.dart';

/// Builds a CoRequest with sensible defaults so individual tests only
/// override the field under test.
CoRequest makeRequest({
  String id = 'r1',
  String initiatorId = 'u1',
  double totalPrice = 30,
  int partnersNeeded = 2,
  double pricePerPerson = 10,
  String category = RequestCategories.groceries,
  String status = RequestStatus.active,
  List<String>? participants,
  String? geohash,
  String? notes,
  double? distanceMeters,
  DateTime? expiresAt,
  DateTime? completedAt,
}) {
  return CoRequest(
    id: id,
    initiatorId: initiatorId,
    initiatorName: 'Alice',
    productName: 'Detergent 3L',
    dealDescription: 'Buy 2 Free 1',
    totalPrice: totalPrice,
    totalQuantity: 3,
    partnersNeeded: partnersNeeded,
    pricePerPerson: pricePerPerson,
    latitude: 4.5975,
    longitude: 101.0901,
    geohash: geohash,
    storeName: 'Tesco Ipoh',
    notes: notes,
    distanceMeters: distanceMeters,
    category: category,
    status: status,
    participants: participants ?? <String>['u1'],
    createdAt: DateTime(2026, 1, 1),
    expiresAt: expiresAt ?? DateTime.now().add(const Duration(hours: 2)),
    completedAt: completedAt,
  );
}

void main() {
  group('CoRequest.calculatePricePerPerson (FR-1.7)', () {
    test('splits total across partners + initiator', () {
      // 30 / (2 partners + 1) = 10.00
      expect(CoRequest.calculatePricePerPerson(30, 2), 10.0);
    });

    test('three partners means four people', () {
      // 30 / (3 + 1) = 7.50
      expect(CoRequest.calculatePricePerPerson(30, 3), 7.5);
    });

    test('rounds to two decimal places', () {
      // 10 / 3 = 3.333... -> 3.33
      expect(CoRequest.calculatePricePerPerson(10, 2), 3.33);
    });

    test('solo buyer (zero partners) pays full price', () {
      expect(CoRequest.calculatePricePerPerson(10, 0), 10.0);
    });

    test('zero price yields zero', () {
      expect(CoRequest.calculatePricePerPerson(0, 3), 0.0);
    });
  });

  group('CoRequest expiry & capacity getters', () {
    test('isExpired is true for a past expiry', () {
      final r = makeRequest(
        expiresAt: DateTime.now().subtract(const Duration(minutes: 1)),
      );
      expect(r.isExpired, isTrue);
    });

    test('isExpired is false for a future expiry', () {
      final r = makeRequest(
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
      );
      expect(r.isExpired, isFalse);
    });

    test('isUrgent is true within the final hour', () {
      final r = makeRequest(
        expiresAt: DateTime.now().add(const Duration(minutes: 30)),
      );
      expect(r.isUrgent, isTrue);
    });

    test('isUrgent is false when more than an hour remains', () {
      final r = makeRequest(
        expiresAt: DateTime.now().add(const Duration(hours: 3)),
      );
      expect(r.isUrgent, isFalse);
    });

    test('isFull when participants reach partnersNeeded + 1', () {
      final r = makeRequest(
        partnersNeeded: 2,
        participants: <String>['u1', 'u2', 'u3'],
      );
      expect(r.isFull, isTrue);
    });

    test('isFull is false with an open slot', () {
      final r = makeRequest(
        partnersNeeded: 2,
        participants: <String>['u1', 'u2'],
      );
      expect(r.isFull, isFalse);
    });
  });

  group('CoRequest.displayBadge priority', () {
    test('completed status wins', () {
      final r = makeRequest(status: RequestStatus.completed);
      expect(r.displayBadge, ('Completed', 'completed'));
    });

    test('cancelled status wins', () {
      final r = makeRequest(status: RequestStatus.cancelled);
      expect(r.displayBadge, ('Cancelled', 'cancelled'));
    });

    test('full takes priority over time', () {
      final r = makeRequest(
        partnersNeeded: 1,
        participants: <String>['u1', 'u2'],
      );
      expect(r.displayBadge.$2, 'full');
    });

    test('expired badge when active but past expiry and not full', () {
      final r = makeRequest(
        partnersNeeded: 3,
        participants: <String>['u1'],
        expiresAt: DateTime.now().subtract(const Duration(minutes: 5)),
      );
      expect(r.displayBadge.$2, 'expired');
    });

    test('urgent badge inside the final hour', () {
      final r = makeRequest(
        partnersNeeded: 3,
        participants: <String>['u1'],
        expiresAt: DateTime.now().add(const Duration(minutes: 20)),
      );
      expect(r.displayBadge.$2, 'urgent');
    });
  });

  group('CoRequest.distanceText', () {
    test('unknown when distance is null', () {
      expect(makeRequest(distanceMeters: null).distanceText, 'Unknown');
    });

    test('metres under one kilometre', () {
      expect(makeRequest(distanceMeters: 450).distanceText, '450m away');
    });

    test('kilometres at or above one thousand metres', () {
      expect(makeRequest(distanceMeters: 2500).distanceText, '2.5km away');
    });
  });

  group('CoRequest.isInitiator', () {
    test('true for the initiator id', () {
      expect(makeRequest(initiatorId: 'u1').isInitiator('u1'), isTrue);
    });
    test('false for a different id', () {
      expect(makeRequest(initiatorId: 'u1').isInitiator('u2'), isFalse);
    });
  });

  group('CoRequest.toFirestore serialization', () {
    test('converts DateTimes to Timestamp', () {
      final map = makeRequest().toFirestore();
      expect(map['createdAt'], isA<Timestamp>());
      expect(map['expiresAt'], isA<Timestamp>());
    });

    test('omits null optional fields', () {
      final map = makeRequest(
        geohash: null,
        notes: null,
        completedAt: null,
      ).toFirestore();
      expect(map.containsKey('geohash'), isFalse);
      expect(map.containsKey('notes'), isFalse);
      expect(map.containsKey('completedAt'), isFalse);
    });

    test('includes optional fields when present', () {
      final map = makeRequest(
        geohash: 'w0qg6',
        notes: 'meet at entrance',
        completedAt: DateTime(2026, 2, 2),
      ).toFirestore();
      expect(map['geohash'], 'w0qg6');
      expect(map['notes'], 'meet at entrance');
      expect(map['completedAt'], isA<Timestamp>());
    });

    test('round-trips core scalar fields', () {
      final map = makeRequest(totalPrice: 30, category: 'electronics')
          .toFirestore();
      expect(map['totalPrice'], 30);
      expect(map['category'], 'electronics');
      expect(map['participants'], <String>['u1']);
    });
  });
}
