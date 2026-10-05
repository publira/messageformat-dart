import 'date_locale.dart';
import 'message_value.dart';

/// The fields of a date and time as they are shown: in the time zone it is
/// formatted in, whose offset from UTC is [offset].
final class DateTimeFields {
  DateTimeFields(
    this.year,
    this.month,
    this.day,
    this.hour,
    this.minute,
    this.second,
    this.millisecond, {
    required this.offset,
  });

  /// The fields of the wall-clock time of [dateTime], shown with [offset].
  DateTimeFields.of(DateTime dateTime, {required Duration offset})
      : this(
          dateTime.year,
          dateTime.month,
          dateTime.day,
          dateTime.hour,
          dateTime.minute,
          dateTime.second,
          dateTime.millisecond,
          offset: offset,
        );

  /// The ISO year, in which 0 is 1 BCE.
  final int year;
  final int month;
  final int day;
  final int hour;
  final int minute;
  final int second;
  final int millisecond;
  final Duration offset;

  /// The day of the week, from 0 for Sunday to 6 for Saturday.
  int get weekday => DateTime.utc(year, month, day).weekday % 7;
}

/// The date fields of `:datetime` and `:date`.
enum DateFields {
  weekday('weekday', hasDay: false, hasWeekday: true),
  dayWeekday('day-weekday', hasWeekday: true),
  monthDay('month-day', hasMonth: true),
  monthDayWeekday('month-day-weekday', hasMonth: true, hasWeekday: true),
  yearMonthDay('year-month-day', hasYear: true, hasMonth: true),
  yearMonthDayWeekday('year-month-day-weekday',
      hasYear: true, hasMonth: true, hasWeekday: true);

  const DateFields(
    this.keyword, {
    this.hasYear = false,
    this.hasMonth = false,
    this.hasDay = true,
    this.hasWeekday = false,
  });

  /// The option value.
  final String keyword;

  final bool hasYear;
  final bool hasMonth;
  final bool hasDay;
  final bool hasWeekday;
}

/// The length of a date or time zone.
enum DateLength { long, medium, short }

/// The precision of a time.
enum TimePrecision { hour, minute, second }

/// A date/time format: the CLDR pattern that a *semantic skeleton* (UTS #35,
/// Part 4, Semantic Skeletons) maps to in a locale.
///
/// A date has [date] fields and a [length]; a time has a [precision], an
/// hour cycle chosen by [hour12] or the locale, and, with [zone], a time
/// zone, which is formatted as an offset from GMT.
final class DateTimeFormat {
  DateTimeFormat(
    this._locale, {
    this.date,
    this.length = DateLength.medium,
    this.precision,
    this.zone,
    this.hour12,
  });

  final DateLocale _locale;
  final DateFields? date;
  final DateLength length;
  final TimePrecision? precision;
  final DateLength? zone;
  final bool? hour12;

  /// [value] formatted as parts of the types of ECMA-402
  /// `Intl.DateTimeFormat.prototype.formatToParts`, such as `month` and
  /// `literal`.
  List<MessageValuePart> formatToParts(DateTimeFields value) =>
      _Formatter(_locale, value).format(_pattern(value));

  /// The pattern for [value], whose year can make the era necessary.
  String _pattern(DateTimeFields value) {
    final request = <_Field>[];
    if (date case final date?) {
      final skeleton = _parse(
          _locale.field('dateSkeleton.${length.name}') ?? _defaultSkeleton);
      _Field? from(_Type type, String fallback) =>
          skeleton[type] ?? _parse(fallback)[type];
      if (date.hasYear) {
        if (value.year < 1000) {
          // Years before 1000 are shown in full and with their era (UTS #35,
          // Part 4, Year Style).
          request.add(skeleton[_Type.era] ?? const _Field('G', 1));
          request.add(const _Field('y', 1));
        } else {
          if (skeleton[_Type.era] case final era?) request.add(era);
          request.add(from(_Type.year, 'y')!);
        }
      }
      if (date.hasMonth) {
        request.add(from(
            _Type.month,
            switch (length) {
              DateLength.long => 'MMMM',
              DateLength.medium => 'MMM',
              DateLength.short => 'M',
            })!);
      }
      if (date.hasDay) request.add(from(_Type.day, 'd')!);
      if (date.hasWeekday) {
        final standalone = date == DateFields.weekday && precision == null;
        request.add(_Field(
            'E',
            switch (length) {
              DateLength.long => 4,
              DateLength.medium => 3,
              DateLength.short => standalone ? 5 : 3,
            }));
      }
    }
    if (precision case final precision?) {
      final format = _hourFormat();
      request.add(_Field(format[0], 1));
      if (format.length > 1) request.add(_Field(format[1], 1));
      if (precision != TimePrecision.hour) request.add(const _Field('m', 1));
      if (precision == TimePrecision.second) {
        request.add(const _Field('s', 1));
      }
      if (zone case final zone?) {
        request.add(_Field('z', zone == DateLength.long ? 4 : 1));
      }
    }
    final key = request.join();
    final patterns = _patterns[_locale] ??= {};
    return patterns[key] ??= _patternFor(_locale, {
      for (final field in request) field.type!: field,
    });
  }

  /// The hour symbol and, for a 12-hour clock, the day period symbol.
  ///
  /// As in the mapping of semantic skeletons, [hour12] chooses `h` or `H`.
  /// Otherwise the `hc` keyword of the locale chooses the hour symbol, and
  /// without it the locale's region does, with its first allowed hour
  /// format (`C`).
  String _hourFormat() {
    final format = switch (hour12) {
      true => 'h',
      false => 'H',
      null => switch (_locale.numbers.hourCycle) {
          'h11' => 'K',
          'h12' => 'h',
          'h23' => 'H',
          'h24' => 'k',
          _ => _locale.hourFormats.first,
        },
    };
    return format.length == 1 && 'hK'.contains(format) ? '${format}a' : format;
  }

  static final _patterns = Expando<Map<String, String>>();
}

/// The skeleton of a date when the locale has none.
const _defaultSkeleton = 'yMMMd';

/// The kinds of fields in skeletons and patterns, in the canonical order of
/// skeletons.
enum _Type {
  era('Era'),
  year('Year'),
  month(null),
  day(null),
  weekday('Day-Of-Week'),
  dayPeriod(null),
  hour(null),
  minute(null),
  second(null),
  fraction(null),
  zone('Timezone');

  const _Type(this.appendItem);

  /// The `appendItem` that appends a missing field of this type, if the
  /// locale data has it.
  final String? appendItem;

  bool get isDate => index <= weekday.index;

  static _Type? of(String symbol) => switch (symbol) {
        'G' => era,
        'y' || 'Y' || 'u' => year,
        'M' || 'L' => month,
        'd' => day,
        'E' || 'c' || 'e' => weekday,
        'a' || 'b' || 'B' => dayPeriod,
        'h' || 'H' || 'K' || 'k' => hour,
        'm' => minute,
        's' => second,
        'S' => fraction,
        'z' || 'Z' || 'O' || 'v' || 'V' || 'X' || 'x' => zone,
        _ => null,
      };
}

/// A field of a skeleton or pattern: a symbol repeated [length] times.
final class _Field {
  const _Field(this.symbol, this.length);

  final String symbol;
  final int length;

  _Type? get type => _Type.of(symbol);

  /// Whether the field is shown as text rather than as a number.
  bool get isText => switch (symbol) {
        'M' || 'L' || 'c' || 'e' => length >= 3,
        'G' || 'E' || 'a' || 'b' || 'B' => true,
        _ => type == _Type.zone,
      };

  @override
  String toString() => symbol * length;
}

/// The fields of [skeleton] by type. A 12-hour clock without a day period
/// has an implicit `a`, and a 24-hour clock has none.
Map<_Type, _Field> _parse(String skeleton) {
  final fields = <_Type, _Field>{};
  for (final (symbol, length) in _runs(skeleton)) {
    final field = _Field(symbol, length);
    if (field.type case final type?) fields[type] = field;
  }
  switch (fields[_Type.hour]?.symbol) {
    case 'h' || 'K':
      fields[_Type.dayPeriod] ??= const _Field('a', 1);
    case 'H' || 'k':
      fields.remove(_Type.dayPeriod);
  }
  return fields;
}

/// The runs of the same character in [text].
Iterable<(String, int)> _runs(String text) sync* {
  for (var i = 0; i < text.length;) {
    var end = i + 1;
    while (end < text.length && text[end] == text[i]) {
      end++;
    }
    yield (text[i], end - i);
    i = end;
  }
}

/// A pattern of a locale and the skeleton it is for.
typedef _Candidate = (Map<_Type, _Field> skeleton, String pattern);

final _candidates = Expando<List<_Candidate>>();

/// The patterns that requests are matched against: those of the locale's
/// `availableFormats`, then its standard date and time formats.
List<_Candidate> _candidatesOf(DateLocale locale) => _candidates[locale] ??= [
      for (final MapEntry(:key, :value) in locale.availableFormats.entries)
        (_parse(key), value),
      for (final kind in ['date', 'time'])
        for (final length in ['full', 'long', 'medium', 'short'])
          if ((
            locale.field('${kind}Skeleton.$length'),
            locale.field('${kind}Format.$length'),
          )
              case (final skeleton?, final pattern?))
            (_parse(skeleton), pattern),
    ];

/// The cost of a requested field that a pattern lacks.
const _missing = 0x1000;

/// The pattern for the [request]ed fields: that of the closest skeleton,
/// adjusted to the requested field lengths, as described in UTS #35, Part 4,
/// Matching Skeletons and Missing Skeleton Fields.
String _patternFor(DateLocale locale, Map<_Type, _Field> request) {
  _Candidate? best;
  var bestDistance = -1;
  for (final candidate in _candidatesOf(locale)) {
    final distance = _distance(request, candidate.$1);
    if (distance != null && (best == null || distance < bestDistance)) {
      best = candidate;
      bestDistance = distance;
    }
  }
  final complete = best != null && bestDistance < _missing;
  final types = request.keys;
  if (!complete &&
      types.any((type) => type.isDate) &&
      types.any((type) => !type.isDate)) {
    // Format the date and the time separately, and combine them.
    final date = {
      for (final MapEntry(:key, :value) in request.entries)
        if (key.isDate) key: value,
    };
    final datePattern = _patternFor(locale, date);
    final timePattern = _patternFor(locale, {
      for (final MapEntry(:key, :value) in request.entries)
        if (!key.isDate) key: value,
    });
    final month = date[_Type.month];
    final length = switch (month?.length) {
      final length? when length >= 4 && month!.isText =>
        date.containsKey(_Type.weekday) ? 'full' : 'long',
      3 => 'medium',
      _ => 'short',
    };
    final combining = locale.field('dateTimeFormat.atTime.$length') ??
        locale.field('dateTimeFormat.$length')!;
    return combining.replaceAllMapped(
      _placeholder,
      (match) => match[1] == '1' ? datePattern : timePattern,
    );
  }
  var pattern = best == null ? '' : _adjust(best.$2, best.$1, request);
  for (final type in _Type.values) {
    final field = request[type];
    if (field == null || (best?.$1.containsKey(type) ?? false)) continue;
    pattern = pattern.isEmpty
        ? '$field'
        : (type.appendItem == null
                ? '{0} {1}'
                : locale.field('appendItem.${type.appendItem}')!)
            .replaceAllMapped(
            _placeholder,
            (match) => match[1] == '0' ? pattern : '$field',
          );
  }
  return pattern;
}

final _placeholder = RegExp(r'\{([01])\}');

/// The distance from the [request]ed fields to those of [skeleton], or
/// `null` if [skeleton] has a field that was not requested.
int? _distance(Map<_Type, _Field> request, Map<_Type, _Field> skeleton) {
  if (skeleton.keys.any((type) => !request.containsKey(type))) return null;
  var distance = 0;
  for (final MapEntry(key: type, value: requested) in request.entries) {
    final field = skeleton[type];
    if (field == null) {
      distance += _missing;
    } else if (field.isText != requested.isText ||
        (type == _Type.dayPeriod &&
            field.symbol != 'a' &&
            requested.symbol != 'a' &&
            field.symbol != requested.symbol)) {
      // A day period `b` or `B` matches an `a` rather than the other one.
      distance += 0x100;
    } else {
      if (field.symbol != requested.symbol) distance += 0x10;
      if (field.length != requested.length) distance += 1;
    }
  }
  return distance;
}

/// [pattern], the pattern of [skeleton], with its fields changed to match
/// the [request]: the hour cycle and day period, the time zone, and the
/// lengths of other fields, unless the locale's skeleton already has the
/// requested length or the change would turn a number into text or text
/// into a number.
String _adjust(
  String pattern,
  Map<_Type, _Field> skeleton,
  Map<_Type, _Field> request,
) {
  final buffer = StringBuffer();
  for (final token in _tokens(pattern)) {
    if (token case (final String symbol, final int length)) {
      final field = _Field(symbol, length);
      final type = field.type;
      final requested = request[type];
      if (requested == null) {
        buffer.write(field);
        continue;
      }
      buffer.write(switch (type) {
        _Type.hour => requested.symbol * length,
        _Type.minute || _Type.second => field,
        _Type.dayPeriod when symbol == 'a' => requested.symbol * length,
        _Type.zone => requested,
        _ when skeleton[type]?.length == requested.length => field,
        _ when field.isText != requested.isText => field,
        _ => symbol * requested.length,
      });
    } else {
      buffer.write(_quote(token as String));
    }
  }
  return buffer.toString();
}

/// [text] as literal text in a pattern.
String _quote(String text) {
  if (text.isEmpty) return text;
  if (text == "'") return "''";
  if (!RegExp(r"[A-Za-z']").hasMatch(text)) return text;
  return "'${text.replaceAll("'", "''")}'";
}

/// The tokens of [pattern]: literal text as a [String], and a field as its
/// symbol and length.
Iterable<Object> _tokens(String pattern) sync* {
  final literal = StringBuffer();
  for (var i = 0; i < pattern.length;) {
    final char = pattern[i];
    if (char == "'") {
      if (i + 1 < pattern.length && pattern[i + 1] == "'") {
        literal.write("'");
        i += 2;
        continue;
      }
      // A quoted section, in which '' is a quote.
      i++;
      while (i < pattern.length) {
        if (pattern[i] == "'") {
          if (i + 1 < pattern.length && pattern[i + 1] == "'") {
            literal.write("'");
            i += 2;
            continue;
          }
          i++;
          break;
        }
        literal.write(pattern[i++]);
      }
    } else if (_letter.hasMatch(char)) {
      var end = i + 1;
      while (end < pattern.length && pattern[end] == char) {
        end++;
      }
      if (literal.isNotEmpty) {
        yield literal.toString();
        literal.clear();
      }
      yield (char, end - i);
      i = end;
    } else {
      literal.write(char);
      i++;
    }
  }
  if (literal.isNotEmpty) yield literal.toString();
}

final _letter = RegExp('[A-Za-z]');

/// Formats a pattern for one value in one locale.
final class _Formatter {
  _Formatter(this._locale, this._value);

  final DateLocale _locale;
  final DateTimeFields _value;

  List<MessageValuePart> format(String pattern) {
    final tokens = _tokens(pattern).toList();
    final symbols = {
      for (final token in tokens)
        if (token case (final String symbol, _)) symbol,
    };
    final parts = <MessageValuePart>[];
    void add(String type, String value) {
      if (type == 'literal' &&
          parts.isNotEmpty &&
          parts.last.type == 'literal') {
        parts.last = MessageValuePart(type, parts.last.value + value);
      } else if (value.isNotEmpty) {
        parts.add(MessageValuePart(type, value));
      }
    }

    for (final token in tokens) {
      switch (token) {
        case (final String symbol, final int length):
          final (type, value) = _field(symbol, length, symbols);
          add(type, value);
        case final String text:
          add('literal', text);
      }
    }
    return parts;
  }

  /// The part type and text of a field.
  (String, String) _field(String symbol, int length, Set<String> symbols) {
    final value = _value;
    final era = value.year > 0 ? 1 : 0;
    return switch (symbol) {
      'G' => (
          'era',
          _names('eras.${length == 5 ? 'eraNarrow' : 'eraAbbr'}')[era]
        ),
      'y' || 'Y' || 'u' => (
          'year',
          _year(
              symbol == 'u' || era == 1 ? value.year : 1 - value.year, length),
        ),
      'M' || 'L' => (
          'month',
          length <= 2
              ? _number(value.month, length)
              : _locale.names(
                  'months',
                  symbol == 'L' ? 'stand-alone' : 'format',
                  length == 4 ? 'wide' : 'abbreviated',
                )![value.month - 1],
        ),
      'd' => ('day', _number(value.day, length)),
      'E' || 'c' || 'e' => (
          'weekday',
          _locale.names(
            'days',
            symbol == 'c' ? 'stand-alone' : 'format',
            switch (length) {
              4 => 'wide',
              5 => 'narrow',
              _ => 'abbreviated',
            },
          )![value.weekday],
        ),
      'a' || 'b' || 'B' => ('dayPeriod', _dayPeriod(symbol, symbols)),
      'h' => (
          'hour',
          _number(value.hour % 12 == 0 ? 12 : value.hour % 12, length)
        ),
      'H' => ('hour', _number(value.hour, length)),
      'K' => ('hour', _number(value.hour % 12, length)),
      'k' => ('hour', _number(value.hour == 0 ? 24 : value.hour, length)),
      'm' => ('minute', _number(value.minute, length)),
      's' => ('second', _number(value.second, length)),
      'S' => (
          'fractionalSecond',
          _digits(
            '${value.millisecond}'
                .padLeft(3, '0')
                .padRight(length, '0')
                .substring(0, length),
          ),
        ),
      // Without time zone names, every time zone field shows the offset.
      'z' || 'Z' || 'O' || 'v' || 'V' || 'X' || 'x' => (
          'timeZoneName',
          _gmt(long: length == 4),
        ),
      _ => ('literal', symbol * length),
    };
  }

  List<String> _names(String field) => _locale.field(field)!.split('\u001f');

  String _year(int year, int length) =>
      length == 2 ? _number(year % 100, 2) : _number(year, length);

  /// [number] in the locale's digits, with at least [length] digits.
  String _number(int number, int length) =>
      _digits('$number'.padLeft(length, '0'));

  String _digits(String ascii) {
    final digits = _locale.numbers.digits;
    final buffer = StringBuffer();
    for (final unit in ascii.codeUnits) {
      buffer.write(unit >= 0x30 && unit <= 0x39
          ? digits[unit - 0x30]
          : String.fromCharCode(unit));
    }
    return buffer.toString();
  }

  /// The day period: AM or PM for `a`, or noon or midnight for `b`, and
  /// for `B` noon or a period of the locale's rules, such as "in the
  /// evening". As in ICU, a time is at noon or midnight when the minutes
  /// and seconds that the pattern shows are zero.
  String _dayPeriod(String symbol, Set<String> symbols) {
    final value = _value;
    final rules = _locale.periodRules;
    String? name(String period) => _locale.field('dayPeriods.$period');
    final exact = (!symbols.contains('m') || value.minute == 0) &&
        (!symbols.contains('s') || value.second == 0);
    String? period;
    if (symbol == 'b' && exact) {
      period = switch (value.hour) {
        0 => name('midnight'),
        12 => name('noon'),
        _ => null,
      };
    } else if (symbol == 'B' &&
        exact &&
        value.hour == 12 &&
        rules.containsKey('noon')) {
      period = name('noon');
    }
    if (symbol == 'B' && period == null) {
      final minutes = value.hour * 60 + value.minute;
      for (final MapEntry(key: rule, value: (from, before)) in rules.entries) {
        if (from == before) continue;
        if (from < before
            ? minutes >= from && minutes < before
            : minutes >= from || minutes < before) {
          period = name(rule);
          break;
        }
      }
    }
    return period ?? name(value.hour < 12 ? 'am' : 'pm')!;
  }

  /// The offset in the localized GMT format, such as `GMT-8` or, when
  /// [long], `GMT-08:00`. As in the examples of UTS #35 and in ICU, a zero
  /// offset is `GMT+0` or `GMT+00:00`, and the short format of a whole hour
  /// ends after the hour.
  String _gmt({required bool long}) {
    final offset = _value.offset;
    final minutes = offset.inMinutes.abs();
    var hourFormat =
        _locale.field('hourFormat')!.split(';')[offset.isNegative ? 1 : 0];
    if (!long && minutes % 60 == 0) {
      hourFormat = hourFormat.substring(0, hourFormat.lastIndexOf('H') + 1);
    }
    final buffer = StringBuffer();
    for (final (char, length) in _runs(hourFormat)) {
      buffer.write(switch (char) {
        'H' => _number(minutes ~/ 60, long ? length : 1),
        'm' => _number(minutes % 60, 2),
        _ => char * length,
      });
    }
    return _locale.field('gmtFormat')!.replaceFirst('{0}', buffer.toString());
  }
}
