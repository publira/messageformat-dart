import 'package:messageformat/messageformat.dart';
import 'package:messageformat/src/locale_direction.dart';
import 'package:test/test.dart';

void main() {
  const ltr = MessageDirection.ltr;
  const rtl = MessageDirection.rtl;

  test('uses the likely script of the language', () {
    for (final locale in ['ar', 'he', 'fa', 'ur', 'rhg', 'apc', 'ary']) {
      expect(localeDirection(locale), rtl, reason: locale);
    }
    for (final locale in ['en', 'ja', 'und', 'zz', 'x-private', '']) {
      expect(localeDirection(locale), ltr, reason: locale);
    }
  });

  test('prefers a script subtag', () {
    expect(localeDirection('az-Arab'), rtl);
    expect(localeDirection('ar-Latn-EG'), ltr);
    expect(localeDirection('zh-yue-Arab'), rtl);
  });

  test('uses the likely script of the language and region', () {
    expect(localeDirection('pa-PK'), rtl);
    expect(localeDirection('pa-IN'), ltr);
    expect(localeDirection('sd-IN'), ltr);
    expect(localeDirection('sd_PK'), rtl);
    expect(localeDirection('ar-001'), rtl);
    expect(localeDirection('und-SA'), rtl);
    expect(localeDirection('und-IR'), rtl);
    expect(localeDirection('und-US'), ltr);
  });

  test('recognises deprecated codes', () {
    expect(localeDirection('iw'), rtl);
    expect(localeDirection('ji-US'), rtl);
    // Replaced by fa_AF.
    expect(localeDirection('prs'), rtl);
    expect(localeDirection('drw'), rtl);
    // Replaced by sr_Latn and sr_ME.
    expect(localeDirection('sh'), ltr);
    expect(localeDirection('cnr'), ltr);
  });

  test('ignores case and empty subtags', () {
    expect(localeDirection('AR-eg'), rtl);
    expect(localeDirection('ar-'), rtl);
    expect(localeDirection('en--Arab'), ltr);
  });
}
