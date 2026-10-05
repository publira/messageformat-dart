import 'package:messageformat/messageformat.dart';

import 'date_data.dart';
import 'date_format.dart';
import 'date_locale.dart';
import 'version.dart';

/// The date/time functions `:datetime`, `:date`, and `:time` by identifier,
/// to register with `MessageFormatOptions.functions`.
///
/// ```dart
/// final mf = MessageFormat(
///   'en',
///   r'Updated {$when :datetime}',
///   options: MessageFormatOptions(functions: dateTimeFunctions),
/// );
/// mf.format({'when': DateTime(2006, 1, 2, 15, 4)});
/// // 'Updated Jan 2, 2006, 3:04 PM'
/// ```
///
/// LDML 48.2 marks these default functions **Draft**: their options and
/// output can change in a minor release of this package when a later
/// version of the specification changes them. They format a [DateTime] or
/// an ISO 8601 date/time literal value, such as `2006-01-02T15:04:06`, with
/// the CLDR [dateTimeCldrVersion] patterns that the *semantic skeleton* of
/// their options maps to (UTS #35, Part 4, Semantic Skeletons). Once they
/// are registered, a [DateTime] in a placeholder without a function, such as
/// `{$when}`, is formatted with `:datetime`. They have these limits:
///
/// - Dates use the Gregorian calendar in every locale, and the option
///   `calendar` accepts only `gregory`.
/// - The default time zone is the platform's local time zone. The option
///   `timeZone` accepts `input` and the time zone identifiers that CLDR
///   knows, such as `UTC` or `America/New_York`. Since time zone data is
///   not included, a value with an offset cannot be converted to a zone
///   other than UTC, and its expression formats as its fallback value with
///   a *Bad Option* error.
/// - The option `timeZoneStyle` shows the offset from GMT, such as
///   `GMT-8`, since time zone names are not included.
const Map<String, MessageFunction> dateTimeFunctions = {
  'date': _date,
  'datetime': _datetime,
  'time': _time,
};

/// The date/time functions, which differ in their options.
enum _Kind {
  datetime({'dateFields', 'dateLength', 'timePrecision', 'timeZoneStyle'},
      hour12: true),
  date({'fields', 'length'}, hour12: false),
  time({'precision', 'timeZoneStyle'}, hour12: true);

  const _Kind(this.literalOptions, {required this.hour12});

  /// The options that must be set with a literal.
  final Set<String> literalOptions;

  /// Whether the function has the option `hour12`.
  final bool hour12;
}

MessageValue _datetime(
  MessageFunctionContext context,
  Map<String, Object?> options,
  Object? operand,
) =>
    _resolve(_Kind.datetime, context, options, operand);

MessageValue _date(
  MessageFunctionContext context,
  Map<String, Object?> options,
  Object? operand,
) =>
    _resolve(_Kind.date, context, options, operand);

MessageValue _time(
  MessageFunctionContext context,
  Map<String, Object?> options,
  Object? operand,
) =>
    _resolve(_Kind.time, context, options, operand);

MessageValue _resolve(
  _Kind kind,
  MessageFunctionContext context,
  Map<String, Object?> options,
  Object? operand,
) {
  final input = _DateTimeInput.read(operand, kind, context);
  // The date/time override options of the operand, and the expression's
  // own options, which take priority.
  final merged = {...input.options, ...options};
  for (final name in kind.literalOptions) {
    if (options.containsKey(name) &&
        !context.literalOptionKeys.contains(name)) {
      merged.remove(name);
      context.onError(MessageFunctionError.badOption(
        'The option $name must be set with a literal',
        source: context.source,
      ));
    }
  }
  final reader = _OptionReader(context, merged);

  final DateFields? date;
  final DateLength length;
  final TimePrecision? precision;
  final DateLength? zone;
  switch (kind) {
    case _Kind.datetime:
      date = reader.keyword(
              'dateFields', DateFields.values, (value) => value.keyword) ??
          DateFields.yearMonthDay;
      length =
          reader.keyword('dateLength', DateLength.values) ?? DateLength.medium;
      precision = reader.keyword('timePrecision', TimePrecision.values) ??
          TimePrecision.minute;
      zone = reader.keyword('timeZoneStyle', _zoneStyles);
    case _Kind.date:
      date = reader.keyword(
              'fields', DateFields.values, (value) => value.keyword) ??
          DateFields.yearMonthDay;
      length = reader.keyword('length', DateLength.values) ?? DateLength.medium;
      precision = null;
      zone = null;
    case _Kind.time:
      date = null;
      length = DateLength.medium;
      precision = reader.keyword('precision', TimePrecision.values) ??
          TimePrecision.minute;
      zone = reader.keyword('timeZoneStyle', _zoneStyles);
  }
  final hour12 = kind.hour12 ? reader.hour12() : null;
  reader.calendar();
  final timeZone = reader.timeZone();

  final fields = _inTimeZone(input, timeZone, zone != null, context, reader);
  final locale = DateLocale(context.locales);
  final format = DateTimeFormat(
    locale,
    date: date,
    length: length,
    precision: precision,
    zone: zone,
    hour12: hour12,
  );
  return _DateTimeValue(
    input,
    format,
    fields,
    Map.unmodifiable(reader.valid),
    locale.tag,
    locale.cldr.dir,
  );
}

const _zoneStyles = [DateLength.long, DateLength.short];

/// The fields of [input] as shown in the time zone of the option
/// `timeZone`, [timeZone], or in the default time zone, which is the local
/// time zone of the platform.
DateTimeFields _inTimeZone(
  _DateTimeInput input,
  String? timeZone,
  bool showsZone,
  MessageFunctionContext context,
  _OptionReader reader,
) {
  final offset = input.offset;
  if (timeZone == 'input') {
    if (offset != null) return input.fields(offset);
    reader.valid.remove('timeZone');
    context.onError(MessageFunctionError.badOperand(
      'The option timeZone=input needs an operand with a time zone offset',
      source: context.source,
    ));
    timeZone = null;
  }
  final utc = timeZone != null && _utcIds.contains(timeZone.toLowerCase());
  if (timeZone != null && !utc) {
    // Without time zone data, only a floating time can be shown in another
    // time zone, and only without its offset.
    if (offset != null || showsZone) {
      throw MessageFunctionError.badOption(
        'The time zone $timeZone is not supported',
        source: context.source,
      );
    }
    return input.fields(Duration.zero);
  }
  if (offset == null) {
    // A floating time is shown as it is, in the given time zone.
    return input
        .fields(utc ? Duration.zero : input.localDateTime.timeZoneOffset);
  }
  final instant = input.instant;
  if (utc) return DateTimeFields.of(instant, offset: Duration.zero);
  final local = instant.toLocal();
  return DateTimeFields.of(local, offset: local.timeZoneOffset);
}

/// The time zone identifiers of CLDR, and those of UTC, in lowercase, since
/// identifiers are matched without regard to case.
final _timeZoneIds = {for (final id in timeZoneIds) id.toLowerCase()};
final _utcIds = {for (final id in utcTimeZoneIds) id.toLowerCase()};

/// The operand of a date/time function: a date and time, with the offset
/// from UTC of its time zone unless it is a floating time.
final class _DateTimeInput {
  _DateTimeInput(
    this.year,
    this.month,
    this.day,
    this.hour,
    this.minute,
    this.second,
    this.millisecond, {
    required this.offset,
    this.dateTime,
    this.options = const {},
  });

  _DateTimeInput.of(DateTime dateTime)
      : this(
          dateTime.year,
          dateTime.month,
          dateTime.day,
          dateTime.hour,
          dateTime.minute,
          dateTime.second,
          dateTime.millisecond,
          offset: dateTime.isUtc ? Duration.zero : dateTime.timeZoneOffset,
          dateTime: dateTime,
        );

  /// Reads [operand] for [kind], or throws a Bad Operand error.
  factory _DateTimeInput.read(
    Object? operand,
    _Kind kind,
    MessageFunctionContext context,
  ) {
    MessageFunctionError bad() => MessageFunctionError.badOperand(
          ':${kind.name} needs a date/time or a date/time literal operand',
          source: context.source,
        );
    switch (operand) {
      case _DateTimeValue(:final input, :final options):
        // Only the date/time override options of the operand apply.
        return input._withOptions({
          for (final MapEntry(:key, :value) in options.entries)
            if (_overrideOptions.contains(key)) key: value,
        });
      case MessageFallbackValue():
        throw bad();
      case MessageValue():
        final Object? value;
        try {
          value = operand.value;
        } catch (_) {
          throw bad();
        }
        return _of(value) ?? (throw bad());
      case _:
        return _of(operand) ?? (throw bad());
    }
  }

  static _DateTimeInput? _of(Object? value) => switch (value) {
        DateTime() => _DateTimeInput.of(value),
        String() => _parse(value),
        _ => null,
      };

  /// The value of a *date/time literal value*, or `null` if [text] is not
  /// one.
  static _DateTimeInput? _parse(String text) {
    final match = _literal.firstMatch(text);
    if (match == null) return null;
    int number(int group) => int.parse(match[group] ?? '0');
    final year = number(1);
    final month = number(2);
    final day = number(3);
    if (day > DateTime.utc(year, month + 1, 0).day) return null;
    final Duration? offset;
    switch (match[8]) {
      case null:
        offset = null;
      case 'Z':
        offset = Duration.zero;
      case final text:
        final minutes =
            int.parse(text.substring(1, 3)) * 60 + int.parse(text.substring(4));
        offset = Duration(minutes: text.startsWith('-') ? -minutes : minutes);
    }
    return _DateTimeInput(
      year,
      month,
      day,
      number(4),
      number(5),
      number(6),
      int.parse((match[7] ?? '').padRight(3, '0')),
      offset: offset,
    );
  }

  final int year;
  final int month;
  final int day;
  final int hour;
  final int minute;
  final int second;
  final int millisecond;

  /// The offset from UTC, or `null` for a floating time.
  final Duration? offset;

  /// The [DateTime] that the operand was, if any.
  final DateTime? dateTime;

  /// The date/time override options that the value came with.
  final Map<String, Object?> options;

  _DateTimeInput _withOptions(Map<String, Object?> options) => _DateTimeInput(
        year,
        month,
        day,
        hour,
        minute,
        second,
        millisecond,
        offset: offset,
        dateTime: dateTime,
        options: options,
      );

  /// The date and time as they are, shown with [offset].
  DateTimeFields fields(Duration offset) =>
      DateTimeFields(year, month, day, hour, minute, second, millisecond,
          offset: offset);

  /// The date and time in the local time zone.
  DateTime get localDateTime =>
      DateTime(year, month, day, hour, minute, second, millisecond);

  /// The instant of a value with an offset, as a UTC [DateTime].
  DateTime get instant =>
      DateTime.utc(year, month, day, hour, minute, second, millisecond)
          .subtract(offset!);
}

/// A *date/time literal value*, as matched by the regular expression of
/// the specification.
final _literal = RegExp(
  r'^(?!0000)([0-9]{4})-(0[1-9]|1[0-2])-(0[1-9]|[12][0-9]|3[01])'
  r'(?:T([01][0-9]|2[0-3]):([0-5][0-9]):([0-5][0-9])(?:\.([0-9]{1,3}))?'
  r'(Z|[+-](?:(?:0[0-9]|1[0-3]):[0-5][0-9]|14:00))?)?$',
);

/// The *date/time override options*.
const _overrideOptions = {'timeZone', 'hour12', 'calendar'};

/// Reads and checks the options of a date/time function, reporting each
/// bad one and leaving it out.
final class _OptionReader {
  _OptionReader(this._context, this._options);

  final MessageFunctionContext _context;
  final Map<String, Object?> _options;

  /// The options that were read and are valid.
  final valid = <String, Object?>{};

  void _bad(String name, String expected) =>
      _context.onError(MessageFunctionError.badOption(
        'The option $name must be $expected',
        source: _context.source,
      ));

  /// The string value of the option [name], or `null` if it has none.
  String? _string(String name) {
    try {
      final option = _options[name];
      final value = option is MessageValue ? option.value : option;
      return value is String ? value : null;
    } catch (_) {
      return null;
    }
  }

  /// The value of the keyword option [name] among [values], whose keywords
  /// are their names unless [keyword] gives them.
  T? keyword<T extends Enum>(
    String name,
    List<T> values, [
    String Function(T value)? keyword,
  ]) {
    if (!_options.containsKey(name)) return null;
    final text = _string(name);
    for (final value in values) {
      if ((keyword?.call(value) ?? value.name) == text) {
        valid[name] = _options[name];
        return value;
      }
    }
    _bad(name,
        values.map((value) => keyword?.call(value) ?? value.name).join(', '));
    return null;
  }

  /// The value of `hour12`.
  bool? hour12() {
    const name = 'hour12';
    if (!_options.containsKey(name)) return null;
    final option = _options[name];
    final Object? value;
    try {
      value = option is MessageValue ? option.value : option;
    } catch (_) {
      _bad(name, 'true or false');
      return null;
    }
    final hour12 = switch (value) {
      true || 'true' => true,
      false || 'false' => false,
      _ => null,
    };
    if (hour12 == null) {
      _bad(name, 'true or false');
    } else {
      valid[name] = option;
    }
    return hour12;
  }

  /// Checks `calendar`: only the Gregorian calendar is supported.
  void calendar() {
    const name = 'calendar';
    if (!_options.containsKey(name)) return;
    if (_string(name) == 'gregory') {
      valid[name] = _options[name];
    } else {
      _bad(name, 'gregory, the only supported calendar');
    }
  }

  /// The value of `timeZone`, if it is `input` or a time zone identifier
  /// that CLDR knows.
  String? timeZone() {
    const name = 'timeZone';
    if (!_options.containsKey(name)) return null;
    final text = _string(name);
    if (text != 'input' &&
        (text == null || !_timeZoneIds.contains(text.toLowerCase()))) {
      _bad(name, 'a time zone identifier or input');
      return null;
    }
    valid[name] = _options[name];
    return text;
  }
}

/// The resolved value of a date/time function.
final class _DateTimeValue extends MessageValue {
  _DateTimeValue(
    this.input,
    this._format,
    this._fields,
    this.options,
    this.locale,
    this.dir,
  );

  final _DateTimeInput input;
  final DateTimeFormat _format;
  final DateTimeFields _fields;

  @override
  final Map<String, Object?> options;

  @override
  final String locale;

  @override
  final MessageDirection dir;

  @override
  String get type => 'datetime';

  /// The operand as a [DateTime]: the one given, or for a date/time
  /// literal, the UTC instant of a time with an offset, or the local time
  /// of a floating one.
  @override
  DateTime get value =>
      input.dateTime ??
      (input.offset == null ? input.localDateTime : input.instant);

  late final List<MessageValuePart> _parts = _format.formatToParts(_fields);

  @override
  String formatToString() => _parts.map((part) => part.value).join();

  @override
  List<MessageValuePart> formatToParts() => _parts;
}
