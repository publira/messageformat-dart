import 'package:messageformat/messageformat.dart';
import 'package:test/test.dart';

/// Formats [source] for [locale] without bidi isolation, returning the
/// result and the types of the errors reported, separated by spaces.
(String, String) _format(
  String source, {
  String locale = 'en-US',
  Map<String, Object?>? params,
}) {
  final errors = <String>[];
  final result = MessageFormat(
    locale,
    source,
    options: const MessageFormatOptions(bidiIsolation: BidiIsolation.none),
  ).format(params, (error) => errors.add(error.type));
  return (result, errors.join(' '));
}

/// The formatted string of [source], which must report no errors.
String _ok(String source, {String locale = 'en-US', Object? x}) {
  final (result, errors) =
      _format(source, locale: locale, params: x == null ? null : {'x': x});
  expect(errors, '', reason: source);
  return result;
}

/// The parts of the single placeholder in [source].
List<MessageValuePart>? _parts(String source,
    {String locale = 'en-US', Object? x}) {
  final parts = MessageFormat(
    locale,
    source,
    options: const MessageFormatOptions(bidiIsolation: BidiIsolation.none),
  ).formatToParts(x == null ? null : {'x': x});
  return (parts.single as MessageExpressionPart).parts;
}

void main() {
  group('number functions format as Intl.NumberFormat', () {
    // The expected strings are those of V8's Intl.NumberFormat (ICU 78.3,
    // CLDR 48) with the same options.
    for (final (locale, source, value, expected) in [
      ('en-US', '{\$x :number}', 1234567.891, '1,234,567.891'),
      ('en-US', '{\$x :number}', -0.5, '-0.5'),
      ('de', '{\$x :number}', 1234567.891, '1.234.567,891'),
      ('fr', '{\$x :number}', 1234567.891, '1\u202f234\u202f567,891'),
      ('de-CH', '{\$x :number}', 1234567.891, '1\'234\'567.891'),
      ('es', '{\$x :number}', 1234, '1234'),
      ('es', '{\$x :number}', 12345, '12.345'),
      ('pl', '{\$x :number}', 1234, '1234'),
      ('en-IN', '{\$x :number}', 123456789, '12,34,56,789'),
      ('hi', '{\$x :number}', 123456789, '12,34,56,789'),
      ('ar', '{\$x :number}', -1234.5, '\u200e-1,234.5'),
      ('ar-AE', '{\$x :number}', -1234.5, '\u200e-1,234.5'),
      ('ar-u-nu-latn', '{\$x :number}', -1234.5, '\u200e-1,234.5'),
      (
        'fa',
        '{\$x :number}',
        -1234.5,
        '\u200e\u2212\u06f1\u066c\u06f2\u06f3\u06f4\u066b\u06f5'
      ),
      (
        'pa-PK',
        '{\$x :number}',
        1234.5,
        '\u06f1\u066c\u06f2\u06f3\u06f4\u066b\u06f5'
      ),
      (
        'th-u-nu-thai',
        '{\$x :number}',
        1234.5,
        '\u0e51,\u0e52\u0e53\u0e54.\u0e55'
      ),
      (
        'en-u-nu-arab',
        '{\$x :number}',
        1234.5,
        '\u0661\u066c\u0662\u0663\u0664\u066b\u0665'
      ),
      ('ja', '{\$x :number}', 1234.5, '1,234.5'),
      ('zh-TW', '{\$x :number}', 1234.5, '1,234.5'),
      ('iw', '{\$x :number}', -1234.5, '\u200e-1,234.5'),
      ('en-US', '{\$x :number minimumFractionDigits=2}', 4.2, '4.20'),
      ('en-US', '{\$x :number maximumFractionDigits=0}', 2.5, '3'),
      ('en-US', '{\$x :number maximumFractionDigits=0}', -2.5, '-3'),
      ('en-US', '{\$x :number maximumFractionDigits=2}', 0.125, '0.13'),
      ('en-US', '{\$x :number maximumFractionDigits=2}', 1.005, '1.01'),
      ('en-US', '{\$x :number maximumSignificantDigits=2}', 1234, '1,200'),
      ('en-US', '{\$x :number maximumSignificantDigits=2}', 999, '1,000'),
      ('en-US', '{\$x :number minimumSignificantDigits=3}', 1, '1.00'),
      ('en-US', '{\$x :number minimumIntegerDigits=3}', 7, '007'),
      ('en-US', '{\$x :number signDisplay=always}', 0, '+0'),
      ('en-US', '{\$x :number signDisplay=always}', -0.0, '-0'),
      ('en-US', '{\$x :number signDisplay=exceptZero}', 0, '0'),
      ('en-US', '{\$x :number signDisplay=exceptZero}', -0.001, '-0.001'),
      ('en-US', '{\$x :number signDisplay=exceptZero}', 1, '+1'),
      ('en-US', '{\$x :number signDisplay=negative}', -0.0, '0'),
      ('en-US', '{\$x :number signDisplay=negative}', -1, '-1'),
      ('en-US', '{\$x :number signDisplay=never}', -1, '1'),
      ('en-US', '{\$x :number}', -0.0001, '-0'),
      ('en-US', '{\$x :number useGrouping=never}', 12345, '12345'),
      ('en-US', '{\$x :number useGrouping=min2}', 1234, '1234'),
      ('en-US', '{\$x :number useGrouping=min2}', 12345, '12,345'),
      ('es', '{\$x :number useGrouping=always}', 1234, '1.234'),
      (
        'en-US',
        '{\$x :number trailingZeroDisplay=stripIfInteger minimumFractionDigits=2}',
        5,
        '5'
      ),
      (
        'en-US',
        '{\$x :number trailingZeroDisplay=stripIfInteger minimumFractionDigits=2}',
        5.1,
        '5.10'
      ),
      (
        'en-US',
        '{\$x :number roundingIncrement=5 minimumFractionDigits=2 maximumFractionDigits=2}',
        1.23,
        '1.25'
      ),
      (
        'en-US',
        '{\$x :number roundingIncrement=25 minimumFractionDigits=2 maximumFractionDigits=2}',
        1.13,
        '1.25'
      ),
      (
        'en-US',
        '{\$x :number roundingPriority=morePrecision maximumSignificantDigits=2 maximumFractionDigits=2}',
        1.234,
        '1.23'
      ),
      (
        'en-US',
        '{\$x :number roundingPriority=lessPrecision maximumSignificantDigits=2 maximumFractionDigits=2}',
        1.234,
        '1.2'
      ),
      ('en-US', '{\$x :number}', 1e+21, '1,000,000,000,000,000,000,000'),
      ('en-US', '{\$x :number}', 1.5e-7, '0'),
      ('en-US', '{\$x :percent}', 0.256, '26%'),
      ('en-US', '{\$x :percent maximumFractionDigits=1}', 0.1234, '12.3%'),
      ('fr', '{\$x :percent}', 0.5, '50\u00a0%'),
      ('de', '{\$x :percent}', -0.5, '-50\u00a0%'),
      ('tr', '{\$x :percent}', 0.5, '%50'),
      ('ar', '{\$x :percent}', 0.5, '50\u200e%\u200e'),
      ('en-US', '{\$x :currency currency=USD}', 1234.5, '\$1,234.50'),
      ('en-US', '{\$x :currency currency=EUR}', -1234.5, '-\u20ac1,234.50'),
      ('en-US', '{\$x :currency currency=JPY}', 1234.5, '\u00a51,235'),
      ('en-US', '{\$x :currency currency=BHD}', 1.5, 'BHD\u00a01.500'),
      ('en-US', '{\$x :currency currency=CHF}', 42, 'CHF\u00a042.00'),
      (
        'en-US',
        '{\$x :currency currency=CAD currencyDisplay=narrowSymbol}',
        42,
        '\$42.00'
      ),
      ('en-US', '{\$x :currency currency=CAD}', 42, 'CA\$42.00'),
      (
        'en-US',
        '{\$x :currency currency=EUR currencyDisplay=code}',
        42,
        'EUR\u00a042.00'
      ),
      (
        'en-US',
        '{\$x :currency currency=USD currencySign=accounting}',
        -42,
        '(\$42.00)'
      ),
      ('en-US', '{\$x :currency currency=USD fractionDigits=0}', 42.5, '\$43'),
      (
        'en-US',
        '{\$x :currency currency=USD trailingZeroDisplay=stripIfInteger}',
        5,
        '\$5'
      ),
      ('en-US', '{\$x :currency currency=usd}', 5, '\$5.00'),
      ('de', '{\$x :currency currency=EUR}', 1234.5, '1.234,50\u00a0\u20ac'),
      ('de-AT', '{\$x :currency currency=EUR}', 1234.5, '\u20ac\u00a01.234,50'),
      (
        'fr',
        '{\$x :currency currency=EUR}',
        -1234.5,
        '-1\u202f234,50\u00a0\u20ac'
      ),
      ('fr-CH', '{\$x :currency currency=CHF}', 1234.5, '1\'234.50\u00a0CHF'),
      ('en-DE', '{\$x :currency currency=EUR}', 1234.5, '\u20ac1,234.50'),
      ('ja', '{\$x :currency currency=JPY}', 1234, '\uffe51,234'),
      ('ja', '{\$x :currency currency=USD}', 1234, '\$1,234.00'),
      ('zh-Hant', '{\$x :currency currency=TWD}', 1234, '\$1,234.00'),
      ('ko', '{\$x :currency currency=KRW}', 1234, '\u20a91,234'),
      ('hi', '{\$x :currency currency=INR}', 1234567, '\u20b912,34,567.00'),
      (
        'ar',
        '{\$x :currency currency=EGP}',
        1234.5,
        '\u200f1,234.50\u00a0\u062c.\u0645.\u200f'
      ),
      (
        'he',
        '{\$x :currency currency=ILS}',
        -1234.5,
        '\u200f\u200e-1,234.50\u00a0\u200f\u20aa'
      ),
    ]) {
      test('$locale $source with $value', () {
        expect(_ok(source, locale: locale, x: value), expected);
      });
    }

    for (final (mode, results) in [
      ('ceil', ['1.3', '-1.2', '1.4']),
      ('floor', ['1.2', '-1.3', '1.3']),
      ('expand', ['1.3', '-1.3', '1.4']),
      ('trunc', ['1.2', '-1.2', '1.3']),
      ('halfCeil', ['1.3', '-1.2', '1.4']),
      ('halfFloor', ['1.2', '-1.3', '1.3']),
      ('halfExpand', ['1.3', '-1.3', '1.4']),
      ('halfTrunc', ['1.2', '-1.2', '1.3']),
      ('halfEven', ['1.2', '-1.2', '1.4']),
    ]) {
      test('roundingMode=$mode', () {
        final source =
            '{\$x :number roundingMode=$mode maximumFractionDigits=1}';
        expect(
          [
            for (final x in [1.25, -1.25, 1.35]) _ok(source, x: x)
          ],
          results,
        );
      });
    }
  });

  group('numeric operands', () {
    test('are numbers, BigInts, or number literals', () {
      expect(_ok('{\$x :number}', x: 42), '42');
      expect(_ok('{\$x :number}', x: BigInt.parse('12345678901234567890')),
          '12,345,678,901,234,567,890');
      expect(_ok('{\$x :number}', x: '-1234.5e-1'), '-123.45');
      expect(_ok('{|1E3| :number}'), '1,000');
    });

    test('are rounded exactly as written', () {
      expect(_ok('{0.125 :number maximumFractionDigits=2}'), '0.13');
      expect(
        _ok('{|0.30000000000000000001| :number maximumSignificantDigits=21}'),
        '0.30000000000000000001',
      );
    });

    test('format infinities and NaN', () {
      expect(_ok('{\$x :number}', x: double.infinity), '\u221e');
      expect(_ok('{\$x :number}', x: double.negativeInfinity), '-\u221e');
      expect(_ok('{\$x :number}', x: double.nan), 'NaN');
      expect(_ok('{\$x :percent}', x: double.infinity), '\u221e%');
    });

    test('report a Bad Operand for other values', () {
      for (final x in <Object>['1.', 'x', true, DateTime(2006)]) {
        expect(_format('{\$x :number}', params: {'x': x}),
            (r'{$x}', 'bad-operand'),
            reason: '$x');
      }
      expect(_format('{:integer}'), ('{:integer}', 'bad-operand'));
    });

    test('report an Unsupported Operation beyond what can be formatted', () {
      expect(
          _format('{1e1001 :number}'), ('{|1e1001|}', 'unsupported-operation'));
      expect(_format('{1e-99999999999 :number}'),
          ('{|1e-99999999999|}', 'unsupported-operation'));
    });

    test('take the value and options of a number function', () {
      expect(
        _ok(
            '.input {\$x :number minimumFractionDigits=2 signDisplay=always} '
            '{{{\$x :number minimumFractionDigits=1}}}',
            x: 4.25),
        '+4.25',
      );
      expect(
        _ok('.local \$n = {4.2 :number minimumFractionDigits=3} '
            '{{{\$n :integer}}}'),
        '4',
      );
      expect(_ok('.local \$n = {0.5 :number} {{{\$n :percent}}}'), '50%');
    });

    test('take the value of a custom function', () {
      final mf = MessageFormat(
        'en',
        '.local \$t = {1 :ten} {{{\$t :number}}}',
        options: MessageFormatOptions(
          bidiIsolation: BidiIsolation.none,
          functions: {'ten': (context, options, operand) => _Ten()},
        ),
      );
      expect(mf.format(), '10.5');
    });
  });

  group('options', () {
    test('accept digit size options as strings and integers', () {
      expect(_ok('{1 :number minimumFractionDigits=|2|}'), '1.00');
      expect(
        _format('{1 :number minimumFractionDigits=\$d}', params: {'d': 2}),
        ('1.00', ''),
      );
      expect(
        _ok('.local \$d = {2 :integer} '
            '{{{1 :number minimumFractionDigits=\$d}}}'),
        '1.00',
      );
    });

    test('report a Bad Option for a bad value and ignore it', () {
      for (final option in [
        'minimumFractionDigits=x',
        'minimumFractionDigits=101',
        'minimumFractionDigits=-1',
        'minimumIntegerDigits=0',
        'maximumSignificantDigits=0',
        'signDisplay=sometimes',
        'roundingIncrement=3',
      ]) {
        expect(_format('{1.5 :number $option}'), ('1.5', 'bad-option'),
            reason: option);
      }
    });

    test('report a Bad Option for conflicting values', () {
      expect(
        _format(
            '{1.5 :number minimumFractionDigits=3 maximumFractionDigits=1}'),
        ('1.5', 'bad-option'),
      );
      expect(
        _format('{1.234 :number roundingIncrement=5 maximumFractionDigits=2}'),
        ('1.23', 'bad-option'),
      );
    });

    test('ignore unknown options', () {
      expect(_format('{1 :number foo=bar}'), ('1', ''));
    });

    test('are the resolved options of the value', () {
      late Map<String, Object?> seen;
      final mf = MessageFormat(
        'en',
        '.local \$n = {1 :number signDisplay=always foo=bar} {{{\$n :see}}}',
        options: MessageFormatOptions(functions: {
          'see': (context, options, operand) {
            seen = (operand! as MessageValue).options;
            return operand as MessageValue;
          },
        }),
      );
      mf.format();
      expect(seen, {'signDisplay': 'always'});
    });
  });

  group(':number and :integer', () {
    test('have the value of their operand, as an integer for :integer', () {
      Object? seen;
      MessageFormat(
        'en',
        '.local \$n = {\$x :integer} {{{\$n :see}}}',
        options: MessageFormatOptions(functions: {
          'see': (context, options, operand) {
            seen = (operand! as MessageValue).value;
            return operand as MessageValue;
          },
        }),
      ).format({'x': 2.5});
      expect(seen, 3);
    });

    test('format as parts', () {
      expect(_parts('{\$x :number}', x: -1234.5), [
        const MessageValuePart('minusSign', '-'),
        const MessageValuePart('integer', '1'),
        const MessageValuePart('group', ','),
        const MessageValuePart('integer', '234'),
        const MessageValuePart('decimal', '.'),
        const MessageValuePart('fraction', '5'),
      ]);
      expect(_parts('{\$x :percent signDisplay=always}', x: 0.5), [
        const MessageValuePart('plusSign', '+'),
        const MessageValuePart('integer', '50'),
        const MessageValuePart('percentSign', '%'),
      ]);
      expect(_parts('{\$x :currency currency=CHF}', x: 1), [
        const MessageValuePart('currency', 'CHF'),
        const MessageValuePart('literal', '\u00a0'),
        const MessageValuePart('integer', '1'),
        const MessageValuePart('decimal', '.'),
        const MessageValuePart('fraction', '00'),
      ]);
    });

    test('have the direction and locale of the message', () {
      final parts = MessageFormat('ar', '{1 :number}').formatToParts();
      expect(
        parts[1],
        isA<MessageExpressionPart>()
            .having((part) => part.dir, 'dir', MessageDirection.rtl)
            .having((part) => part.locale, 'locale', 'ar'),
      );
    });

    test('use the first of several locales that has data', () {
      expect(
        MessageFormat(['xx', 'de'], '{1.5 :number}',
                options: const MessageFormatOptions(
                    bidiIsolation: BidiIsolation.none))
            .format(),
        '1,5',
      );
    });
  });

  group('selection', () {
    String select(String declaration, Object? x, {String locale = 'en'}) =>
        _format(
          '.input {\$x $declaration} .match \$x '
          '0 {{=0}} 1 {{=1}} zero {{zero}} one {{one}} two {{two}} '
          'few {{few}} many {{many}} * {{other}}',
          locale: locale,
          params: {'x': x},
        ).$1;

    test('prefers an exact match to a plural category', () {
      expect(select(':number', 1), '=1');
      expect(select(':number', 1.0), '=1');
      expect(select(':number', '1.0'), '=1');
      expect(select(':number', 2, locale: 'cy'), 'two');
      expect(select(':number', 0, locale: 'cy'), '=0');
    });

    test('selects the plural category of the formatted number', () {
      expect(select(':number minimumFractionDigits=1', 1), '=1');
      expect(
        _format(
            '.input {\$x :number minimumFractionDigits=1} .match \$x '
            'one {{one}} * {{other}}',
            params: {'x': 1}).$1,
        'other',
      );
      expect(
        _format(
            '.input {\$x :number maximumFractionDigits=0} .match \$x '
            'one {{one}} * {{other}}',
            params: {'x': 1.2}).$1,
        'one',
      );
    });

    test('selects ordinal categories', () {
      String ordinal(int n) => _format(
            '.input {\$n :number select=ordinal} .match \$n '
            'one {{{\$n}st}} two {{{\$n}nd}} few {{{\$n}rd}} * {{{\$n}th}}',
            params: {'n': n},
          ).$1;
      expect([1, 2, 3, 4, 11, 12, 13, 21, 22, 23, 101].map(ordinal), [
        '1st', '2nd', '3rd', '4th', '11th', '12th', '13th', //
        '21st', '22nd', '23rd', '101st',
      ]);
    });

    test('matches only exact keys with select=exact', () {
      expect(select(':number select=exact', 1), '=1');
      expect(select(':number select=exact', 2), 'other');
    });

    test('selects :integer and :percent by their formatted values', () {
      expect(select(':integer', 1.4), '=1');
      expect(select(':percent', 0.01), '=1');
      expect(select(':percent', 0.02), 'other');
    });

    test('reports a Bad Variant Key once and still selects', () {
      expect(
        _format(
            '.input {\$x :number} .match \$x '
            'horse {{horse}} one {{one}} * {{other}}',
            params: {'x': 1}),
        ('one', 'bad-variant-key'),
      );
    });

    test('is not supported by :currency', () {
      expect(
        _format(
            '.input {\$x :currency currency=EUR} .match \$x '
            '1 {{one}} * {{other}}',
            params: {'x': 1}),
        ('other', 'bad-selector'),
      );
    });
  });

  group(':offset', () {
    test('adds to or subtracts from its operand', () {
      expect(_ok('{\$x :offset add=2}', x: 40), '42');
      expect(_ok('{\$x :offset subtract=2}', x: 0.5), '-1.5');
      expect(_ok('{\$x :offset add=1}', x: BigInt.parse('9' * 20)),
          '100,000,000,000,000,000,000');
    });

    test('keeps the function and options of its operand', () {
      expect(
        _ok('.local \$p = {0.5 :percent} {{{\$p :offset add=1}}}'),
        '150%',
      );
      expect(
        _ok('.local \$n = {1 :currency currency=EUR} {{{\$n :offset add=1}}}'),
        '\u20ac2.00',
      );
    });

    test('selects with the offset applied', () {
      String likes(int count) => _format(
            '.input {\$count :integer} '
            '.local \$others = {\$count :offset subtract=1} '
            '.match \$count \$others '
            '0 * {{No likes}} '
            '1 * {{Liked by you}} '
            '* one {{Liked by you and {\$others} other}} '
            '* * {{Liked by you and {\$others} others}}',
            params: {'count': count},
          ).$1;
      expect([0, 1, 2, 3].map(likes), [
        'No likes',
        'Liked by you',
        'Liked by you and 1 other',
        'Liked by you and 2 others',
      ]);
    });
  });

  group(':currency', () {
    test('shows the currency code for currencyDisplay=name', () {
      expect(
          _ok('{1 :currency currency=EUR currencyDisplay=name}'), '1.00 EUR');
      expect(
          _ok('{1 :currency currency=EUR currencyDisplay=name}', locale: 'fr'),
          '1,00 EUR');
    });

    test('hides the currency for currencyDisplay=never', () {
      expect(_ok('{1 :currency currency=EUR currencyDisplay=never}'), '1.00');
    });

    test('rejects a currency that is not a three-letter code', () {
      expect(_format('{1 :currency currency=EURO}'),
          ('{|1|}', 'bad-option bad-operand'));
    });

    test('cannot change the currency of a currency value', () {
      expect(
        _format('.local \$n = {1 :currency currency=EUR} '
            '{{{\$n :currency currency=USD}}}'),
        ('\u20ac1.00', 'bad-option'),
      );
    });
  });

  group(':string', () {
    test('formats and selects the string value of its operand', () {
      expect(_ok('{\$x :string}', x: 42), '42');
      expect(_ok('{\$x :string}', x: 'a'), 'a');
      expect(
        _format('.input {\$x :string} .match \$x |a b| {{space}} * {{other}}',
            params: {'x': 'a b'}).$1,
        'space',
      );
    });

    test('ignores its options and has none', () {
      late Map<String, Object?> seen;
      MessageFormat(
        'en',
        '.local \$s = {a :string foo=bar} {{{\$s :see}}}',
        options: MessageFormatOptions(functions: {
          'see': (context, options, operand) {
            seen = (operand! as MessageValue).options;
            return operand as MessageValue;
          },
        }),
      ).format();
      expect(seen, isEmpty);
    });

    test('formats an unresolved operand as its fallback', () {
      expect(_format('{\$x :string}'), (r'{$x}', 'unresolved-variable'));
    });
  });
}

/// A custom value whose numeric value is 10.5.
final class _Ten extends MessageValue {
  @override
  String get type => 'ten';

  @override
  Object? get value => 10.5;

  @override
  String formatToString() => 'ten';
}
