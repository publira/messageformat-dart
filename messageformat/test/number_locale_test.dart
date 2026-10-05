import 'package:messageformat/src/number_locale.dart';
import 'package:test/test.dart';

void main() {
  group('NumberLocale', () {
    String decimal(String tag) => NumberLocale([tag]).symbol('decimal')!;

    test('falls back by subtag and through CLDR parent locales', () {
      expect(decimal('de-AT'), ',');
      expect(decimal('en-US'), '.');
      // en-150 inherits from en-001, not from en.
      expect(NumberLocale(['en-150']).currencySymbol('USD'), 'US\$');
      expect(NumberLocale(['en']).currencySymbol('USD'), '\$');
    });

    test('adds the likely script of a tag without one', () {
      // zh-TW uses zh-Hant, whose symbol for TWD is `$`.
      expect(NumberLocale(['zh-TW']).currencySymbol('TWD'), '\$');
      expect(NumberLocale(['zh']).currencySymbol('TWD'), 'NT\$');
      expect(NumberLocale(['pa-PK']).numberingSystem, 'arabext');
      expect(NumberLocale(['pa']).numberingSystem, 'latn');
    });

    test('follows deprecated language codes', () {
      expect(NumberLocale(['iw']).currencySymbol('ILS'), '\u20aa');
      expect(NumberLocale(['sh']).currencySymbol('RSD'),
          NumberLocale(['sr-Latn']).currencySymbol('RSD'));
    });

    test('uses the first tag with data, or root', () {
      expect(decimal('xx'), '.');
      expect(NumberLocale(['xx', 'de']).symbol('decimal'), ',');
      expect(NumberLocale(['not a tag']).symbol('decimal'), '.');
      expect(NumberLocale(const []).symbol('decimal'), '.');
      expect(NumberLocale(['xx', 'de-AT']).tag, 'de-AT');
      expect(NumberLocale(['xx', 'yy']).tag, 'xx');
      expect(NumberLocale(const []).tag, 'und');
    });

    test('reads the numbering system from the u extension', () {
      expect(NumberLocale(['ar-u-nu-latn']).numberingSystem, 'latn');
      expect(NumberLocale(['en-u-ca-gregory-nu-arab']).digits[1], '\u0661');
      expect(NumberLocale(['en-u-nu-unknown']).numberingSystem, 'latn');
      expect(NumberLocale(['en-x-u-nu-arab']).numberingSystem, 'latn');
    });

    test('finds the plural rules of the language without number data', () {
      expect(NumberLocale(['pt-AO']).pluralLocales, contains('pt-PT'));
      expect(NumberLocale(['xx']).pluralLocales, ['xx', 'und']);
    });
  });
}
