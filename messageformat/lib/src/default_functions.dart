import 'decimal.dart';
import 'errors.dart';
import 'locale_direction.dart';
import 'message_value.dart';
import 'nfc.dart';
import 'number_data.dart';
import 'number_format.dart';
import 'number_locale.dart';

/// The default functions that LDML 48.2 marks Stable, by identifier.
const Map<String, MessageFunction> stableFunctions = {
  'currency': _currency,
  'integer': _integer,
  'number': _number,
  'offset': _offset,
  'percent': _percent,
  'string': _string,
};

// :string

MessageValue _string(
  MessageFunctionContext context,
  Map<String, Object?> options,
  Object? operand,
) {
  final value = _stringOf(operand);
  if (value == null) {
    throw MessageFunctionError.badOperand(
      ':string needs an operand that converts to a string',
      source: context.source,
    );
  }
  return _StringValue(value, context.locales.first);
}

/// The string value of a `:string` operand: a string as it is, the value
/// of a [MessageValue], or any other value converted with `toString()`.
String? _stringOf(Object? operand) => switch (operand) {
      null => null,
      String() => operand,
      // As in the JS implementation, which the conformance suite follows.
      MessageFallbackValue() => operand.formatToString(),
      MessageValue(:final value) => _stringOf(value),
      _ => operand.toString(),
    };

/// The resolved value of `:string`.
final class _StringValue extends SelectableMessageValue {
  _StringValue(this.value, this.locale);

  @override
  final String value;

  @override
  final String locale;

  @override
  String get type => 'string';

  @override
  String formatToString() => value;

  @override
  bool match(String key) => toNfc(value) == key;

  @override
  bool betterThan(String key1, String key2) => false;
}

// Numbers

/// The number functions, which differ in their options and in how they
/// format and select.
enum _Kind {
  number('number', {
    'select',
    'signDisplay',
    'useGrouping',
    'minimumIntegerDigits',
    'minimumFractionDigits',
    'maximumFractionDigits',
    'minimumSignificantDigits',
    'maximumSignificantDigits',
    'trailingZeroDisplay',
    'roundingPriority',
    'roundingIncrement',
    'roundingMode',
  }, {}),
  integer('integer', {
    'select',
    'signDisplay',
    'useGrouping',
    'minimumIntegerDigits',
    'maximumSignificantDigits',
  }, {
    'minimumFractionDigits',
    'maximumFractionDigits',
    'minimumSignificantDigits',
  }),
  percent('percent', {
    'signDisplay',
    'useGrouping',
    'minimumFractionDigits',
    'maximumFractionDigits',
    'minimumSignificantDigits',
    'maximumSignificantDigits',
    'trailingZeroDisplay',
    'roundingPriority',
    'roundingMode',
  }, {
    'minimumIntegerDigits',
    'roundingIncrement',
    'select',
  }),
  currency('currency', {
    'currency',
    'currencySign',
    'currencyDisplay',
    'useGrouping',
    'minimumIntegerDigits',
    'fractionDigits',
    'minimumSignificantDigits',
    'maximumSignificantDigits',
    'trailingZeroDisplay',
    'roundingPriority',
    'roundingIncrement',
    'roundingMode',
  }, {});

  const _Kind(this.function, this.options, this.discarded);

  /// The function's identifier.
  final String function;

  /// The options the function accepts.
  final Set<String> options;

  /// The options left out when inherited from the operand.
  final Set<String> discarded;
}

MessageValue _number(
  MessageFunctionContext context,
  Map<String, Object?> options,
  Object? operand,
) =>
    _resolveNumber(_Kind.number, context, options, operand);

MessageValue _integer(
  MessageFunctionContext context,
  Map<String, Object?> options,
  Object? operand,
) =>
    _resolveNumber(_Kind.integer, context, options, operand);

MessageValue _percent(
  MessageFunctionContext context,
  Map<String, Object?> options,
  Object? operand,
) =>
    _resolveNumber(_Kind.percent, context, options, operand);

MessageValue _currency(
  MessageFunctionContext context,
  Map<String, Object?> options,
  Object? operand,
) =>
    _resolveNumber(_Kind.currency, context, options, operand);

MessageValue _resolveNumber(
  _Kind kind,
  MessageFunctionContext context,
  Map<String, Object?> options,
  Object? operand,
) {
  final source = _NumericOperand.read(operand, kind.function, context);
  final ownOptions = {...options};
  if (kind == _Kind.currency &&
      source.kind == _Kind.currency &&
      ownOptions.containsKey('currency')) {
    // The currency of a currency value cannot be overridden.
    ownOptions.remove('currency');
    context.onError(MessageFunctionError.badOption(
      'The option currency cannot change the currency of a currency value',
      source: context.source,
    ));
  }
  final inherited = {
    for (final MapEntry(:key, :value) in source.options.entries)
      if (!kind.discarded.contains(key)) key: value,
  };
  return _NumberValue.resolve(
    kind,
    context,
    kind == _Kind.integer
        ? source.value.round(0, _roundHalfExpand(source.value))
        : source.value,
    inherited: inherited,
    options: ownOptions,
  );
}

UnsignedRounding _roundHalfExpand(Decimal value) =>
    RoundingMode.halfExpand.unsigned(negative: value.negative);

// :offset

MessageValue _offset(
  MessageFunctionContext context,
  Map<String, Object?> options,
  Object? operand,
) {
  final source = _NumericOperand.read(operand, 'offset', context);
  final add = options.containsKey('add');
  final subtract = options.containsKey('subtract');
  if (add == subtract) {
    throw MessageFunctionError.badOption(
      ':offset needs exactly one of the options add and subtract',
      source: context.source,
    );
  }
  final name = add ? 'add' : 'subtract';
  final amount = _digitSize(options[name]);
  if (amount == null) {
    throw MessageFunctionError.badOption(
      'The option $name of :offset must be a digit size option',
      source: context.source,
    );
  }
  final delta = Decimal.fromBigInt(BigInt.from(add ? amount : -amount));
  // The result formats and selects like its operand, with the operand's
  // options, but not with those of :offset.
  return _NumberValue.resolve(
    source.kind ?? _Kind.number,
    context,
    source.value + delta,
    inherited: source.options,
    options: const {},
  );
}

// Operands and options

/// A numeric operand: its value and the options it brings.
final class _NumericOperand {
  _NumericOperand(this.value, this.options, this.kind);

  /// Reads [operand] for [function], or throws a Bad Operand error.
  factory _NumericOperand.read(
    Object? operand,
    String function,
    MessageFunctionContext context,
  ) {
    MessageFunctionError bad() => MessageFunctionError.badOperand(
          ':$function needs a numeric operand',
          source: context.source,
        );
    final _NumericOperand result;
    switch (operand) {
      case _NumberValue():
        result = _NumericOperand(operand.number, operand.options, operand.kind);
      case MessageValue():
        final Object? value;
        try {
          value = operand.value;
        } catch (_) {
          throw bad();
        }
        final number = _decimalOf(value) ?? (throw bad());
        result = _NumericOperand(number, operand.options, null);
      case _:
        result = _NumericOperand(
            _decimalOf(operand) ?? (throw bad()), const {}, null);
    }
    if (result.value.magnitude case final magnitude?
        when magnitude.abs() > _maxMagnitude) {
      throw MessageFunctionError.unsupportedOperation(
        'The operand of :$function is too large or too small to format',
        source: context.source,
      );
    }
    return result;
  }

  final Decimal value;
  final Map<String, Object?> options;

  /// The number function that resolved the operand, if any.
  final _Kind? kind;
}

/// The largest power of ten that a numeric operand can be formatted at:
/// numbers beyond it would format to thousands of digits.
const _maxMagnitude = 1000;

/// The value of a Dart number or a `number-literal` string, or `null`.
Decimal? _decimalOf(Object? value) => switch (value) {
      num() => Decimal.fromNum(value),
      BigInt() => Decimal.fromBigInt(value),
      String() => Decimal.tryParse(value),
      _ => null,
    };

/// The value of a *digit size option*: a string matching the
/// `digit-size-option` production, or a non-negative [int], possibly as the
/// value of a [MessageValue]. `null` if it is neither.
int? _digitSize(Object? option) {
  final Object? value;
  try {
    value = option is MessageValue ? option.value : option;
  } catch (_) {
    return null;
  }
  return switch (value) {
    final String text when _digitSizeOption.hasMatch(text) => int.parse(text),
    final int number when number >= 0 => number,
    _ => null,
  };
}

final _digitSizeOption = RegExp(r'^(0|[1-9][0-9]?)$');

/// The string value of an option, or `null` if it has none.
String? _keywordOf(Object? option) {
  try {
    final value = option is MessageValue ? option.value : option;
    return value is String ? value : null;
  } catch (_) {
    return null;
  }
}

/// Reads and checks the options of a number function, reporting each bad
/// one and leaving it out.
final class _OptionReader {
  _OptionReader(this._kind, this._context, this._options);

  final _Kind _kind;
  final MessageFunctionContext _context;

  /// The options, inherited and own, by name.
  final Map<String, Object?> _options;

  /// The options that were read and are valid.
  final valid = <String, Object?>{};

  void _bad(String name, String expected) =>
      _context.onError(MessageFunctionError.badOption(
        'The option $name must be $expected',
        source: _context.source,
      ));

  /// The value of the keyword option [name] among [values].
  T? keyword<T extends Enum>(String name, List<T> values) {
    if (!_kind.options.contains(name) || !_options.containsKey(name)) {
      return null;
    }
    final option = _options[name];
    final text = _keywordOf(option);
    for (final value in values) {
      if (value.name == text) {
        valid[name] = option;
        return value;
      }
    }
    _bad(name, values.map((value) => value.name).join(', '));
    return null;
  }

  /// The value of the digit size option [name], between [min] and [max].
  int? digits(String name, {required int min, required int max}) {
    if (!_kind.options.contains(name) || !_options.containsKey(name)) {
      return null;
    }
    final option = _options[name];
    final value = _digitSize(option);
    if (value == null || value < min || value > max) {
      _bad(name, 'a digit size option from $min to $max');
      return null;
    }
    valid[name] = option;
    return value;
  }

  /// The value of `roundingIncrement`.
  int? increment() {
    const name = 'roundingIncrement';
    if (!_kind.options.contains(name) || !_options.containsKey(name)) {
      return null;
    }
    final option = _options[name];
    final value = _digitSizeOrNumber(option);
    if (value == null || !roundingIncrements.contains(value)) {
      _bad(name, 'one of ${roundingIncrements.join(', ')}');
      return null;
    }
    valid[name] = option;
    return value;
  }

  static int? _digitSizeOrNumber(Object? option) {
    final Object? value;
    try {
      value = option is MessageValue ? option.value : option;
    } catch (_) {
      return null;
    }
    return switch (value) {
      final String text when RegExp(r'^[1-9][0-9]{0,3}$').hasMatch(text) =>
        int.parse(text),
      final int number => number,
      _ => null,
    };
  }

  /// The value of `currency`, uppercased, if it is a well-formed currency
  /// code.
  String? currency() {
    const name = 'currency';
    if (!_options.containsKey(name)) return null;
    final option = _options[name];
    final text = _keywordOf(option);
    if (text == null || !RegExp(r'^[A-Za-z]{3}$').hasMatch(text)) {
      _bad(name, 'a three-letter currency code');
      return null;
    }
    valid[name] = option;
    return text.toUpperCase();
  }

  /// The value of the currency option `fractionDigits`, a digit size
  /// option, or `null` for `auto`.
  int? fractionDigits() {
    const name = 'fractionDigits';
    if (_keywordOf(_options[name]) == 'auto') {
      valid[name] = _options[name];
      return null;
    }
    return digits(name, min: 0, max: 100);
  }
}

/// The selection modes of `select`.
enum _Select { plural, ordinal, exact }

/// The resolved value of a number function.
class _NumberValue extends MessageValue {
  _NumberValue(
    this.kind,
    this.number,
    this.options,
    this._format,
    this.locale,
    this.dir,
  );

  /// Resolves [number] with the [inherited] options of its operand and the
  /// expression's own [options].
  factory _NumberValue.resolve(
    _Kind kind,
    MessageFunctionContext context,
    Decimal number, {
    required Map<String, Object?> inherited,
    required Map<String, Object?> options,
  }) {
    final merged = {...inherited, ...options};
    final reader = _OptionReader(kind, context, merged);

    final digits = DigitOptions(
      minimumIntegerDigits:
          reader.digits('minimumIntegerDigits', min: 1, max: 21),
      minimumFractionDigits:
          reader.digits('minimumFractionDigits', min: 0, max: 100),
      maximumFractionDigits:
          reader.digits('maximumFractionDigits', min: 0, max: 100),
      minimumSignificantDigits:
          reader.digits('minimumSignificantDigits', min: 1, max: 21),
      maximumSignificantDigits:
          reader.digits('maximumSignificantDigits', min: 1, max: 21),
      roundingIncrement: reader.increment(),
      roundingPriority:
          reader.keyword('roundingPriority', RoundingPriority.values),
    );
    final roundingMode = reader.keyword('roundingMode', RoundingMode.values);
    final trailingZeroDisplay =
        reader.keyword('trailingZeroDisplay', _TrailingZeroDisplay.values);
    final signDisplay = reader.keyword('signDisplay', SignDisplay.values);
    final useGrouping = reader.keyword('useGrouping', UseGrouping.values);

    var minimumFractionDigitsDefault = 0;
    var maximumFractionDigitsDefault = kind == _Kind.number ? 3 : 0;
    String? currency;
    CurrencyDisplay? currencyDisplay;
    CurrencySign? currencySign;
    if (kind == _Kind.currency) {
      currency = reader.currency();
      if (currency == null) {
        throw MessageFunctionError.badOperand(
          ':currency needs a currency value or the option currency',
          source: context.source,
        );
      }
      currencyDisplay =
          reader.keyword('currencyDisplay', CurrencyDisplay.values);
      currencySign = reader.keyword('currencySign', CurrencySign.values);
      minimumFractionDigitsDefault = maximumFractionDigitsDefault =
          reader.fractionDigits() ?? currencyDigits[currency] ?? 2;
    }

    // `select` must be a literal on the expression itself.
    _Select? select;
    var selectable = kind != _Kind.currency;
    if (kind.options.contains('select')) {
      if (options.containsKey('select')) {
        if (!context.literalOptionKeys.contains('select')) {
          selectable = false;
          context.onError(MessageFunctionError.badOption(
            'The option select must be set with a literal',
            source: context.source,
          ));
        } else {
          select = reader.keyword('select', _Select.values);
        }
      } else if (inherited.containsKey('select')) {
        selectable = false;
        context.onError(MessageFunctionError.badOption(
          'The option select cannot come from the operand',
          source: context.source,
        ));
      }
    }

    final locale = NumberLocale(context.locales);
    final format = NumberFormat(
      locale,
      digits: digits,
      minimumFractionDigitsDefault: minimumFractionDigitsDefault,
      maximumFractionDigitsDefault: maximumFractionDigitsDefault,
      style: switch (kind) {
        _Kind.percent => NumberStyle.percent,
        _Kind.currency => NumberStyle.currency,
        _ => NumberStyle.decimal,
      },
      roundingMode: roundingMode ?? RoundingMode.halfExpand,
      stripIfInteger:
          trailingZeroDisplay == _TrailingZeroDisplay.stripIfInteger,
      signDisplay: signDisplay ?? SignDisplay.auto,
      useGrouping: useGrouping ?? UseGrouping.auto,
      currency: currency,
      currencyDisplay: currencyDisplay ?? CurrencyDisplay.symbol,
      currencySign: currencySign ?? CurrencySign.standard,
      onConflict: (name) {
        reader.valid.remove(name);
        context.onError(MessageFunctionError.badOption(
          'The option $name of :${kind.function} conflicts with another',
          source: context.source,
        ));
      },
    );

    // The valid options, and those of the operand that this function does
    // not use, which pass through to the next. A `select` that disabled
    // selection stays, so that a function given this value reports it too.
    final resolved = {
      for (final MapEntry(:key, :value) in inherited.entries)
        if (!kind.options.contains(key)) key: value,
      ...reader.valid,
      if (!selectable && kind != _Kind.currency) 'select': merged['select'],
    };
    // The locale whose data formats the number, which may not be the first.
    final tag = locale.tag;
    final dir = localeDirection(tag);
    return selectable
        ? _SelectableNumberValue(
            kind,
            number,
            Map.unmodifiable(resolved),
            format,
            tag,
            dir,
            select ?? _Select.plural,
            context.source,
          )
        : _NumberValue(
            kind, number, Map.unmodifiable(resolved), format, tag, dir);
  }

  final _Kind kind;

  /// The numeric value, which for `:percent` is not yet multiplied by 100.
  final Decimal number;

  final NumberFormat _format;

  @override
  final Map<String, Object?> options;

  @override
  final String locale;

  @override
  final MessageDirection dir;

  @override
  String get type => 'number';

  /// The number as an [int] if it is an integer that a double can hold
  /// exactly, as a [BigInt] if it is a larger integer, and otherwise as a
  /// [double].
  @override
  Object get value {
    if (number.isNaN) return double.nan;
    if (number.isInfinite) {
      return number.negative ? double.negativeInfinity : double.infinity;
    }
    if (number.isInteger) {
      final integer = BigInt.parse(number.toPlainString(1 << 30)!);
      return integer.isValidInt && integer.abs() <= _maxSafeInteger
          ? integer.toInt()
          : integer;
    }
    return double.parse(number.toString());
  }

  static final _maxSafeInteger = BigInt.from(9007199254740991);

  /// The value that is formatted and selected: [number], times 100 for
  /// `:percent`.
  Decimal get _shown =>
      kind == _Kind.percent ? number.scaleByPowerOfTen(2) : number;

  @override
  String formatToString() => formatToParts().map((part) => part.value).join();

  @override
  List<MessageValuePart> formatToParts() => _format.formatToParts(_shown);
}

enum _TrailingZeroDisplay { auto, stripIfInteger }

/// The resolved value of a number function that supports selection.
final class _SelectableNumberValue extends _NumberValue
    implements SelectableMessageValue {
  _SelectableNumberValue(
    super.kind,
    super.number,
    super.options,
    super._format,
    super.locale,
    super.dir,
    this._select,
    this._source,
  );

  final _Select _select;
  final String _source;

  /// The plural or ordinal category, or `null` for exact selection.
  late final String? _keyword = _select == _Select.exact
      ? null
      : _format.pluralCategory(_shown, ordinal: _select == _Select.ordinal);

  @override
  bool match(String key) {
    if (Decimal.tryParse(key) != null) {
      return _shown.toPlainString(key.length) == key;
    }
    if (_pluralKeywords.contains(key)) return key == _keyword;
    throw MessageFunctionError.badVariantKey(
      'The key $key is neither a number nor a plural category',
      source: _source,
    );
  }

  @override
  bool betterThan(String key1, String key2) =>
      Decimal.tryParse(key1) != null && Decimal.tryParse(key2) == null;
}

const _pluralKeywords = {'zero', 'one', 'two', 'few', 'many', 'other'};
