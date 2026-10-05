import 'package:messageformat/messageformat.dart';
import 'package:messageformat/src/plural_rules.dart';
import 'package:messageformat/src/plural_rules_data.dart';
import 'package:test/test.dart';

import 'plural_samples.dart';

void main() {
  group('the generated rules give each CLDR sample its category', () {
    for (final MapEntry(key: type, value: locales) in pluralSamples.entries) {
      test(type, () {
        final rules = type == 'ordinal' ? ordinalRules : cardinalRules;
        expect(rules.keys, unorderedEquals(locales.keys));
        for (final MapEntry(key: locale, value: categories)
            in locales.entries) {
          for (final MapEntry(key: category, value: samples)
              in categories.entries) {
            for (final sample in samples) {
              expect(
                pluralCategory([locale], PluralOperands(sample),
                    ordinal: type == 'ordinal'),
                category,
                reason: '$type $locale $sample',
              );
            }
          }
        }
      });
    }
  });

  group('PluralOperands', () {
    test('has the operands of a formatted number', () {
      final operands = PluralOperands('1.050');
      expect(
        (operands.i, operands.v, operands.w, operands.f, operands.t),
        (1, 3, 2, 50, 5),
      );
    });

    test('keeps large values congruent modulo 10^6', () {
      final operands = PluralOperands('12345678901234567890000001');
      expect(operands.i % 1000000, 1);
      expect(operands.i, greaterThan(999999999999999));
      expect(PluralOperands('0.0000000000000000000001').f, 1);
    });
  });

  group('selection', () {
    String category(String locale, num n, {bool ordinal = false}) =>
        MessageFormat(
          locale,
          '.input {\$n :number${ordinal ? ' select=ordinal' : ''}} .match \$n '
          'zero {{zero}} one {{one}} two {{two}} few {{few}} many {{many}} '
          '* {{other}}',
        ).format({'n': n});

    const numbers = [0, 1, 2, 3, 4, 5, 11, 21, 100, 1000000, 1.5];

    // The locales of the conformance suite and those that Publira ships.
    for (final (locale, cardinal, ordinal) in [
      (
        'en-US',
        [
          'other', 'one', 'other', 'other', 'other', 'other', 'other', //
          'other', 'other', 'other', 'other'
        ],
        [
          'other', 'one', 'two', 'few', 'other', 'other', 'other', //
          'one', 'other', 'other', 'other'
        ],
      ),
      (
        'en',
        [
          'other', 'one', 'other', 'other', 'other', 'other', 'other', //
          'other', 'other', 'other', 'other'
        ],
        [
          'other', 'one', 'two', 'few', 'other', 'other', 'other', //
          'one', 'other', 'other', 'other'
        ],
      ),
      (
        'fr',
        [
          'one', 'one', 'other', 'other', 'other', 'other', 'other', //
          'other', 'other', 'many', 'one'
        ],
        [
          'other', 'one', 'other', 'other', 'other', 'other', 'other', //
          'other', 'other', 'other', 'other'
        ],
      ),
      (
        'ar',
        [
          'zero', 'one', 'two', 'few', 'few', 'few', 'many', //
          'many', 'other', 'other', 'other'
        ],
        List.filled(11, 'other'),
      ),
      ('und', List.filled(11, 'other'), List.filled(11, 'other')),
      ('ja', List.filled(11, 'other'), List.filled(11, 'other')),
      ('ko', List.filled(11, 'other'), List.filled(11, 'other')),
      ('zh-Hans', List.filled(11, 'other'), List.filled(11, 'other')),
      ('zh-Hant', List.filled(11, 'other'), List.filled(11, 'other')),
    ]) {
      test('in $locale', () {
        expect([for (final n in numbers) category(locale, n)], cardinal,
            reason: 'cardinal');
        expect(
          [for (final n in numbers) category(locale, n, ordinal: true)],
          ordinal,
          reason: 'ordinal',
        );
      });
    }

    test('uses the rules of the locale\'s CLDR parent', () {
      // pt-AO inherits from pt-PT, whose `one` excludes 0.
      expect(category('pt', 0), 'one');
      expect(category('pt-PT', 0), 'other');
      expect(category('pt-AO', 0), 'other');
    });

    test('says 1 episode and 2 episodes', () {
      final mf = MessageFormat('en', '''
.input {\$count :number}
.match \$count
one {{{\$count} episode selected}}
*   {{{\$count} episodes selected}}
''');
      expect(mf.format({'count': 1}), '1 episode selected');
      expect(mf.format({'count': 2}), '2 episodes selected');
      expect(mf.format({'count': 0}), '0 episodes selected');
      expect(mf.format({'count': 1.5}), '1.5 episodes selected');
    });
  });
}
