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

/// The value that [source] gives the variable `$d` it declares.
Object? _declared(String source) {
  Object? value;
  MessageFormat('en-US', source,
      options: MessageFormatOptions(functions: {
        'peek': (context, options, operand) {
          value = operand;
          return _Empty();
        },
      })).format();
  return value;
}

final class _Empty extends MessageValue {
  @override
  String get type => 'empty';

  @override
  Object? get value => null;

  @override
  String formatToString() => '';
}

void main() {
  group('date/time functions format as Intl.DateTimeFormat', () {
    // The expected strings are those of V8's Intl.DateTimeFormat (ICU 78.3,
    // CLDR 48) with the options that the semantic skeleton maps to, except
    // that V8 shows U+202F NARROW NO-BREAK SPACE as a space.
    const t = '2006-01-02T15:04:06';
    for (final (locale, source, expected) in [
      ('en-US', '{|$t| :date length=long}', 'January 2, 2006'),
      ('en-US', '{|$t| :date}', 'Jan 2, 2006'),
      ('en-US', '{|$t| :date length=short}', '1/2/06'),
      (
        'en-US',
        '{|$t| :date fields=year-month-day-weekday length=long}',
        'Monday, January 2, 2006'
      ),
      ('en-US', '{|$t| :date fields=weekday length=short}', 'M'),
      ('en-US', '{|$t| :time}', '3:04\u202fPM'),
      ('en-US', '{|$t| :time precision=hour}', '3\u202fPM'),
      ('en-US', '{|$t| :datetime}', 'Jan 2, 2006, 3:04\u202fPM'),
      (
        'en-US',
        '{|$t| :datetime dateLength=long timePrecision=second}',
        'January 2, 2006 at 3:04:06\u202fPM'
      ),
      ('en-GB', '{|$t| :datetime}', '2 Jan 2006, 15:04'),
      ('de', '{|$t| :date}', '02.01.2006'),
      ('de', '{|$t| :datetime dateLength=long}', '2. Januar 2006 um 15:04'),
      (
        'fr',
        '{|$t| :date fields=year-month-day-weekday length=long}',
        'lundi 2 janvier 2006'
      ),
      ('ja', '{|$t| :datetime dateLength=long}', '2006年1月2日 15:04'),
      ('ja', '{|$t| :date}', '2006/01/02'),
      ('zh-TW', '{|$t| :time}', '下午3:04'),
      ('ko', '{|$t| :time}', '오후 3:04'),
      ('ar-EG', '{|$t| :date length=long}', '٢ يناير ٢٠٠٦'),
      ('ar-EG', '{|$t| :time}', '٣:٠٤ م'),
      ('hi', '{|$t| :datetime}', '2 जन॰ 2006, 3:04 pm'),
      ('ru', '{|$t| :date length=long}', '2 января 2006\u202fг.'),
      ('en-US', '{|0750-01-02| :date}', 'Jan 2, 750 AD'),
      ('sq', '{|0750-01-02| :date length=short}', '2.1.750 mbas Krishtit'),
      ('en-US', '{|$t| :time hour12=false}', '15:04'),
      ('en-u-hc-h23', '{|$t| :time}', '15:04'),
      (
        'en-US',
        '{|$t-08:00| :time timeZone=input timeZoneStyle=short}',
        '3:04\u202fPM GMT-8'
      ),
      (
        'en-US',
        '{|$t+05:30| :time timeZone=input timeZoneStyle=long}',
        '3:04\u202fPM GMT+05:30'
      ),
      ('de', '{|${t}Z| :time timeZone=UTC timeZoneStyle=short}', '15:04 GMT+0'),
    ]) {
      test('$source in $locale', () {
        expect(_ok(source, locale: locale), expected);
      });
    }
  });

  group('date/time functions', () {
    test('default to the options the specification gives', () {
      expect(
          _ok('{|2006-01-02T15:04:06| :datetime}'),
          _ok('{|2006-01-02T15:04:06| :datetime dateFields=year-month-day '
              'timePrecision=minute}'));
      expect(_ok('{|2006-01-02| :date}'),
          _ok('{|2006-01-02| :date fields=year-month-day length=medium}'));
      expect(_ok('{|2006-01-02T15:04:06| :time}'),
          _ok('{|2006-01-02T15:04:06| :time precision=minute}'));
    });

    test('format a date literal without a time at midnight', () {
      expect(_ok('{|2006-01-02| :datetime}'), 'Jan 2, 2006, 12:00\u202fAM');
    });

    test('format each date field set', () {
      const d = '|2006-01-02|';
      expect(_ok('{$d :date fields=weekday}'), 'Mon');
      expect(_ok('{$d :date fields=weekday length=long}'), 'Monday');
      expect(_ok('{$d :date fields=day-weekday}'), '2 Mon');
      expect(_ok('{$d :date fields=month-day}'), 'Jan 2');
      expect(_ok('{$d :date fields=month-day-weekday}'), 'Mon, Jan 2');
      expect(
          _ok('{$d :date fields=year-month-day-weekday}'), 'Mon, Jan 2, 2006');
      expect(_ok('{$d :datetime dateFields=weekday}'), 'Mon 12:00\u202fAM');
    });

    test('show the day period that the locale uses', () {
      // Taiwan prefers flexible day periods, such as 中午 (noon).
      expect(_ok('{|2006-01-02T12:00:00| :time}', locale: 'zh-TW'), '中午12:00');
      expect(_ok('{|2006-01-02T21:00:00| :time}', locale: 'zh-TW'), '晚上9:00');
      expect(_ok('{|2006-01-02T15:04:06| :time hour12=true}', locale: 'ja'),
          '午後3:04');
      expect(_ok('{|2006-01-02T00:30:00| :time}', locale: 'ja-u-hc-h11'),
          '午前0:30');
      expect(
          _ok('{|2006-01-02T00:30:00| :time}', locale: 'en-u-hc-h24'), '24:30');
    });

    test('accept hour12 from a variable', () {
      expect(
          _ok(r'{|2006-01-02T15:04:06| :time hour12=$x}', x: false), '15:04');
      expect(_ok(r'{|2006-01-02T15:04:06| :time hour12=$x}', x: 'true'),
          '3:04\u202fPM');
    });

    test('format DateTime values', () {
      expect(_ok(r'{$x :datetime}', x: DateTime(2006, 1, 2, 15, 4, 6)),
          'Jan 2, 2006, 3:04\u202fPM');
      expect(
          _ok(r'{$x :time timeZone=UTC timeZoneStyle=short}',
              x: DateTime.utc(2006, 1, 2, 15, 4, 6)),
          '3:04\u202fPM GMT+0');
      expect(
          _ok(r'{$x :time timeZone=input timeZoneStyle=short}',
              x: DateTime.utc(2006, 1, 2, 15, 4, 6)),
          '3:04\u202fPM GMT+0');
      // A DateTime without a function is formatted with :datetime.
      expect(_ok(r'{$x}', x: DateTime(2006, 1, 2, 15, 4, 6)),
          'Jan 2, 2006, 3:04\u202fPM');
    });

    test('convert a time with an offset to UTC', () {
      expect(_ok('{|2006-01-02T15:04:06-08:00| :datetime timeZone=UTC}'),
          'Jan 2, 2006, 11:04\u202fPM');
      expect(_ok('{|2006-01-02T20:04:06-08:00| :date timeZone=UTC}'),
          'Jan 3, 2006');
    });

    test('show a floating time as it is in the given time zone', () {
      expect(_ok('{|2006-01-02T15:04:06| :time timeZone=UTC}'), '3:04\u202fPM');
      expect(
          _ok('{|2006-01-02T15:04:06Z| :time timeZone=utc}'), '3:04\u202fPM');
      expect(_ok('{|2006-01-02T15:04:06Z| :time timeZone=|Etc/GMT|}'),
          '3:04\u202fPM');
      expect(_ok('{|2006-01-02T15:04:06| :time timeZone=|Asia/Tokyo|}'),
          '3:04\u202fPM');
    });

    test('format to parts', () {
      final parts = MessageFormat(
        'en-US',
        '{|2006-01-02T15:04:06| :datetime}',
        options: const MessageFormatOptions(bidiIsolation: BidiIsolation.none),
      ).formatToParts().single as MessageExpressionPart;
      expect(parts.type, 'datetime');
      expect(parts.locale, 'en-US');
      expect(parts.dir, MessageDirection.ltr);
      expect(
        [for (final part in parts.parts!) (part.type, part.value)],
        [
          ('month', 'Jan'),
          ('literal', ' '),
          ('day', '2'),
          ('literal', ', '),
          ('year', '2006'),
          ('literal', ', '),
          ('hour', '3'),
          ('literal', ':'),
          ('minute', '04'),
          ('literal', '\u202f'),
          ('dayPeriod', 'PM'),
        ],
      );
    });

    test('resolve to a value with the date and its options', () {
      final value = _declared(
          r'.local $d = {|2006-01-02T15:04:06Z| :date length=long timeZone=UTC}'
          r' {{{$d :peek}}}');
      expect(value, isA<MessageValue>());
      value as MessageValue;
      expect(value.value, DateTime.utc(2006, 1, 2, 15, 4, 6));
      expect(value.options, {'length': 'long', 'timeZone': 'UTC'});
      expect(
        (_declared(r'.local $d = {|2006-01-02T15:04:06| :time} {{{$d :peek}}}')
                as MessageValue)
            .value,
        DateTime(2006, 1, 2, 15, 4, 6),
      );
    });

    test('keep only the override options of a date/time operand', () {
      expect(
        _ok(r'.local $d = {|2006-01-02T15:04:06Z| :datetime timeZone=UTC '
            r'hour12=false dateLength=long} {{{$d :time}}}'),
        '15:04',
      );
      expect(
        _ok(r'.local $d = {|2006-01-02T15:04:06| :date length=long} '
            r'{{{$d :datetime}}}'),
        'Jan 2, 2006, 3:04\u202fPM',
      );
      expect(
        _ok(r'.local $d = {|2006-01-02T15:04:06| :time hour12=false} '
            r'{{{$d :time hour12=true}}}'),
        '3:04\u202fPM',
      );
    });

    test('accept a date/time literal from another value', () {
      expect(_ok(r'.local $d = {|2006-01-02| :string} {{{$d :date}}}'),
          'Jan 2, 2006');
      expect(_ok(r'{$x :date}', x: '2006-01-02'), 'Jan 2, 2006');
    });

    test('report a bad operand', () {
      for (final (source, x) in <(String, Object?)>[
        ('{:date}', null),
        ('{|2006-02-29| :date}', null),
        ('{|2006-01-02T15:04| :datetime}', null),
        ('{|2006-1-2| :date}', null),
        ('{|0000-01-02| :date}', null),
        ('{|2006-01-02T15:04:06+15:00| :time}', null),
        (r'{$x :time}', 1136214246000),
        (r'{$x :time}', true),
        (r'{$y :time}', null),
        (r'.local $n = {1 :number} {{{$n :date}}}', null),
      ]) {
        final (_, errors) =
            _format(source, params: x == null ? null : {'x': x});
        expect(errors, contains('bad-operand'), reason: source);
      }
      expect(_format('{|2024-02-29| :date}').$2, '');
    });

    test('report bad options and ignore them', () {
      for (final (source, expected) in [
        ('{|2006-01-02| :date length=huge}', 'Jan 2, 2006'),
        ('{|2006-01-02| :date fields=year}', 'Jan 2, 2006'),
        (
          r'.local $l = {long} {{{|2006-01-02| :date length=$l}}}',
          'Jan 2, 2006'
        ),
        ('{|2006-01-02T15:04:06| :time precision=minutes}', '3:04\u202fPM'),
        ('{|2006-01-02T15:04:06| :time hour12=yes}', '3:04\u202fPM'),
        ('{|2006-01-02T15:04:06| :time calendar=buddhist}', '3:04\u202fPM'),
        ('{|2006-01-02T15:04:06| :time timeZone=|not a zone|}', '3:04\u202fPM'),
        ('{|2006-01-02T15:04:06| :time timeZone=|Not/AZone|}', '3:04\u202fPM'),
      ]) {
        expect(_format(source), (expected, 'bad-option'), reason: source);
      }
      expect(_ok('{|2006-01-02T15:04:06| :time calendar=gregory}'),
          '3:04\u202fPM');
      // Options of other functions are ignored.
      expect(
          _ok('{|2006-01-02T15:04:06| :date precision=second}'), 'Jan 2, 2006');
    });

    test('report timeZone=input for a floating time and use the default', () {
      expect(_format('{|2006-01-02T15:04:06| :time timeZone=input}'),
          ('3:04\u202fPM', 'bad-operand'));
    });

    test('fall back for a time zone that cannot be converted to', () {
      expect(
        _format('{|2006-01-02T15:04:06Z| :time timeZone=|Asia/Tokyo|}'),
        ('{|2006-01-02T15:04:06Z|}', 'bad-option'),
      );
      expect(
        _format('{|2006-01-02T15:04:06| :time timeZone=|Asia/Tokyo| '
            'timeZoneStyle=short}'),
        ('{|2006-01-02T15:04:06|}', 'bad-option'),
      );
    });

    test('do not support selection', () {
      expect(
        _format('.local \$d = {|2006-01-02| :date} .match \$d * {{x}}'),
        ('x', 'bad-selector'),
      );
    });
  });
}
