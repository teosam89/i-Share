import 'package:flutter_test/flutter_test.dart';
import 'package:i_share/features/profile/models/user_profile_model.dart';
import 'package:i_share/features/profile/services/credibility_service.dart';

void main() {
  group('CredibilityService.getCredibilityLevel (FR-3.7 tiers)', () {
    test('score below 300 is User', () {
      expect(CredibilityService.getCredibilityLevel(0), 'User');
      expect(CredibilityService.getCredibilityLevel(85), 'User');
      expect(CredibilityService.getCredibilityLevel(299), 'User');
    });

    test('300 to 699 is Trusted', () {
      expect(CredibilityService.getCredibilityLevel(300), 'Trusted');
      expect(CredibilityService.getCredibilityLevel(699), 'Trusted');
    });

    test('700 and above is Elite', () {
      expect(CredibilityService.getCredibilityLevel(700), 'Elite');
      expect(CredibilityService.getCredibilityLevel(1000), 'Elite');
    });
  });

  group('CredibilityService colour & icon mapping', () {
    test('tier colours match the design system', () {
      expect(CredibilityService.getCredibilityColor('Elite'), 0xFFFFD700);
      expect(CredibilityService.getCredibilityColor('Trusted'), 0xFF4CAF50);
      expect(CredibilityService.getCredibilityColor('User'), 0xFF2196F3);
    });

    test('unknown tier falls back to User blue', () {
      expect(CredibilityService.getCredibilityColor('Anything'), 0xFF2196F3);
    });

    test('tier icons resolve to distinct assets', () {
      expect(CredibilityService.getCredibilityIcon('Elite'),
          'assets/icons/CElite.png');
      expect(CredibilityService.getCredibilityIcon('Trusted'),
          'assets/icons/CTrusted.png');
      expect(CredibilityService.getCredibilityIcon('User'),
          'assets/icons/CUser.png');
    });
  });

  group('CredibilityService.eventPoints (FR-3.8 score events)', () {
    test('award and penalty magnitudes match the specification', () {
      const p = CredibilityService.eventPoints;
      expect(p[CredibilityEvent.completeDeal], 15);
      expect(p[CredibilityEvent.rating5Star], 10);
      expect(p[CredibilityEvent.rating4Star], 3);
      expect(p[CredibilityEvent.rating3Below], -5);
      expect(p[CredibilityEvent.cancelWithParticipants], -25);
      expect(p[CredibilityEvent.cancelNoParticipants], 0);
      expect(p[CredibilityEvent.leaveRequest], -10);
      expect(p[CredibilityEvent.expiredWithParticipants], -10);
      expect(p[CredibilityEvent.verifyEmail], 20);
      expect(p[CredibilityEvent.verifyPhone], 30);
    });
  });

  group('Verifications model', () {
    test('verifiedCount counts the true flags', () {
      expect(Verifications(email: true, phone: true).verifiedCount, 2);
      expect(Verifications().verifiedCount, 0);
      expect(
        Verifications(email: true, phone: true, identity: true).verifiedCount,
        3,
      );
    });

    test('fromMap tolerates a null document', () {
      final v = Verifications.fromMap(null);
      expect(v.email, isFalse);
      expect(v.phone, isFalse);
      expect(v.identity, isFalse);
    });

    test('fromMap then toMap round-trips', () {
      final v = Verifications.fromMap(<String, dynamic>{
        'email': true,
        'phone': false,
        'identity': true,
      });
      expect(v.toMap(), <String, dynamic>{
        'email': true,
        'phone': false,
        'identity': true,
      });
    });
  });
}
