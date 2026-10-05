import 'package:messageformat/locale.dart';
import 'package:messageformat/messageformat.dart';
import 'package:test/test.dart';

void main() {
  group('CldrLocale', () {
    test('resolves tags as the default functions do', () {
      final locale = CldrLocale(['xx', 'en-150-u-nu-arab-hc-h23']);
      expect(locale.tag, 'en-150-u-nu-arab-hc-h23');
      // en-150 inherits from en-001, not from en.
      expect(locale.chain, ['en-150', 'en-001', 'en', 'und']);
      expect(locale.numberingSystem, 'arab');
      expect(locale.digits.first, '٠');
      expect(locale.region, '150');
      expect(locale.hourCycle, 'h23');
      expect(locale.dir, MessageDirection.ltr);
    });

    test('falls back to the root locale', () {
      final locale = CldrLocale(const []);
      expect(locale.tag, 'und');
      expect(locale.chain, ['und']);
      expect(locale.digits.first, '0');
      expect(locale.region, isNull);
      expect(locale.hourCycle, isNull);
    });

    test('has the direction of the requested tag', () {
      expect(CldrLocale(['ar']).dir, MessageDirection.rtl);
      expect(CldrLocale(['he-IL']).chain, ['he', 'und']);
    });
  });
}
