import 'package:flutter_test/flutter_test.dart';
import 'package:i_share/features/co_request/models/co_request_model.dart';

void main() {
  group('RequestCategories taxonomy (FR-1.6 / FR-2.1)', () {
    test('exposes exactly eight canonical categories', () {
      expect(RequestCategories.all.length, 8);
    });

    test('every canonical key has a display label', () {
      for (final key in RequestCategories.all) {
        expect(
          RequestCategories.labels.containsKey(key),
          isTrue,
          reason: 'missing label for "$key"',
        );
      }
    });

    test('canonical keys match the documented taxonomy', () {
      expect(RequestCategories.all, <String>[
        'groceries',
        'fresh',
        'snacks',
        'household',
        'personal',
        'baby_pets',
        'electronics',
        'others',
      ]);
    });
  });

  group('RequestCategories.normalizeCategory (legacy migration)', () {
    test('maps legacy "food" to groceries', () {
      expect(RequestCategories.normalizeCategory('food'),
          RequestCategories.groceries);
    });

    test('passes a current key through unchanged', () {
      expect(RequestCategories.normalizeCategory('electronics'), 'electronics');
    });

    test('passes an unknown key through unchanged', () {
      expect(RequestCategories.normalizeCategory('vintage'), 'vintage');
    });
  });

  group('RequestCategories.queryAliases', () {
    test('groceries query covers both the new key and legacy "food"', () {
      final aliases = RequestCategories.queryAliases[RequestCategories.groceries];
      expect(aliases, isNotNull);
      expect(aliases, containsAll(<String>['groceries', 'food']));
    });
  });
}
