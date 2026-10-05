import 'decimal.dart';
import 'message_value.dart';
import 'number_locale.dart';
import 'plural_rules.dart';

/// How a number is formatted: as a plain number, a percentage, or an amount
/// of money.
enum NumberStyle { decimal, percent, currency }

/// The `roundingMode` option values, as in ECMA-402.
enum RoundingMode {
  ceil,
  floor,
  expand,
  trunc,
  halfCeil,
  halfFloor,
  halfExpand,
  halfTrunc,
  halfEven;

  /// ECMA-402 GetUnsignedRoundingMode.
  UnsignedRounding unsigned({required bool negative}) => switch (this) {
        ceil => negative ? UnsignedRounding.zero : UnsignedRounding.infinity,
        floor => negative ? UnsignedRounding.infinity : UnsignedRounding.zero,
        expand => UnsignedRounding.infinity,
        trunc => UnsignedRounding.zero,
        halfCeil =>
          negative ? UnsignedRounding.halfZero : UnsignedRounding.halfInfinity,
        halfFloor =>
          negative ? UnsignedRounding.halfInfinity : UnsignedRounding.halfZero,
        halfExpand => UnsignedRounding.halfInfinity,
        halfTrunc => UnsignedRounding.halfZero,
        halfEven => UnsignedRounding.halfEven,
      };
}

/// The `roundingPriority` option values, as in ECMA-402.
enum RoundingPriority { auto, morePrecision, lessPrecision }

/// The `signDisplay` option values, as in ECMA-402.
enum SignDisplay { auto, always, exceptZero, negative, never }

/// The `useGrouping` option values, as in ECMA-402.
enum UseGrouping { auto, always, never, min2 }

/// The `currencyDisplay` option values. `never` is ICU's `hidden`.
enum CurrencyDisplay { narrowSymbol, symbol, name, code, never }

/// The `currencySign` option values.
enum CurrencySign { accounting, standard }

/// The rounding increments that `roundingIncrement` accepts.
const roundingIncrements = {
  1,
  2,
  5,
  10,
  20,
  25,
  50,
  100,
  200,
  250,
  500,
  1000,
  2000,
  2500,
  5000,
};

/// The digit options of a number format before ECMA-402's
/// SetNumberFormatDigitOptions resolves them: each is `null` when unset.
final class DigitOptions {
  DigitOptions({
    this.minimumIntegerDigits,
    this.minimumFractionDigits,
    this.maximumFractionDigits,
    this.minimumSignificantDigits,
    this.maximumSignificantDigits,
    this.roundingIncrement,
    this.roundingPriority,
  });

  int? minimumIntegerDigits;
  int? minimumFractionDigits;
  int? maximumFractionDigits;
  int? minimumSignificantDigits;
  int? maximumSignificantDigits;
  int? roundingIncrement;
  RoundingPriority? roundingPriority;
}

enum _RoundingType {
  fractionDigits,
  significantDigits,
  morePrecision,
  lessPrecision,
}

/// A number format for one locale and set of options, which corresponds
/// to an ECMA-402 `Intl.NumberFormat` with the same options.
final class NumberFormat {
  /// Creates a format, resolving [digits] as ECMA-402
  /// SetNumberFormatDigitOptions does with the default fraction digits
  /// [minimumFractionDigitsDefault] and [maximumFractionDigitsDefault].
  ///
  /// Where ECMA-402 throws, because the options conflict, the conflicting
  /// option is left out and its name is passed to [onConflict].
  NumberFormat(
    this.locale, {
    required DigitOptions digits,
    required int minimumFractionDigitsDefault,
    required int maximumFractionDigitsDefault,
    this.style = NumberStyle.decimal,
    this.roundingMode = RoundingMode.halfExpand,
    this.stripIfInteger = false,
    this.signDisplay = SignDisplay.auto,
    this.useGrouping = UseGrouping.auto,
    this.currency,
    this.currencyDisplay = CurrencyDisplay.symbol,
    this.currencySign = CurrencySign.standard,
    required void Function(String option) onConflict,
  }) : minimumIntegerDigits = digits.minimumIntegerDigits ?? 1 {
    var increment = digits.roundingIncrement ?? 1;
    final priority = digits.roundingPriority ?? RoundingPriority.auto;
    final mnfdDefault = minimumFractionDigitsDefault;
    final mxfdDefault =
        increment == 1 ? maximumFractionDigitsDefault : mnfdDefault;
    var mnfd = digits.minimumFractionDigits;
    var mxfd = digits.maximumFractionDigits;
    final mnsd = digits.minimumSignificantDigits;
    final mxsd = digits.maximumSignificantDigits;
    final hasSd = mnsd != null || mxsd != null;
    final hasFd = mnfd != null || mxfd != null;
    final needSd = priority != RoundingPriority.auto || hasSd;
    final needFd = priority != RoundingPriority.auto || !hasSd;
    // Without needSd or needFd, the digits it would set are never used.
    minimumSignificantDigits = mnsd ?? 1;
    if (mxsd != null && mxsd < minimumSignificantDigits) {
      onConflict('maximumSignificantDigits');
      maximumSignificantDigits = 21;
    } else {
      maximumSignificantDigits = mxsd ?? 21;
    }
    if (needFd && hasFd) {
      if (mnfd != null && mxfd != null && mnfd > mxfd) {
        onConflict('minimumFractionDigits');
        mnfd = null;
      }
      if (mnfd == null) {
        mnfd = mnfdDefault < mxfd! ? mnfdDefault : mxfd;
      } else {
        mxfd ??= mxfdDefault > mnfd ? mxfdDefault : mnfd;
      }
      minimumFractionDigits = mnfd;
      maximumFractionDigits = mxfd;
    } else {
      minimumFractionDigits = mnfdDefault;
      maximumFractionDigits = mxfdDefault;
    }
    _roundingType = switch (priority) {
      RoundingPriority.auto =>
        needSd ? _RoundingType.significantDigits : _RoundingType.fractionDigits,
      RoundingPriority.morePrecision => _RoundingType.morePrecision,
      RoundingPriority.lessPrecision => _RoundingType.lessPrecision,
    };
    if (increment != 1 &&
        (_roundingType != _RoundingType.fractionDigits ||
            maximumFractionDigits != minimumFractionDigits)) {
      onConflict('roundingIncrement');
      increment = 1;
    }
    roundingIncrement = increment;
  }

  final NumberLocale locale;
  final NumberStyle style;
  final int minimumIntegerDigits;
  late final int minimumFractionDigits;
  late final int maximumFractionDigits;
  late final int minimumSignificantDigits;
  late final int maximumSignificantDigits;
  late final _RoundingType _roundingType;
  late final int roundingIncrement;
  final RoundingMode roundingMode;

  /// Whether `trailingZeroDisplay` is `stripIfInteger`.
  final bool stripIfInteger;
  final SignDisplay signDisplay;
  final UseGrouping useGrouping;

  /// The uppercase ISO 4217 code of a currency format.
  final String? currency;
  final CurrencyDisplay currencyDisplay;
  final CurrencySign currencySign;

  /// [value] rounded and formatted in ASCII digits without grouping or
  /// sign, as ECMA-402 FormatNumericToString does, such as `1234.50`.
  ///
  /// The returned value is rounded, and has the sign of [value].
  (String, Decimal) toRawString(Decimal value) {
    final x = value.abs();
    final mode = roundingMode.unsigned(negative: value.negative);
    final _RawResult result;
    switch (_roundingType) {
      case _RoundingType.significantDigits:
        result = _toRawPrecision(x, mode);
      case _RoundingType.fractionDigits:
        result = _toRawFixed(x, mode);
      case _RoundingType.morePrecision || _RoundingType.lessPrecision:
        final precision = _toRawPrecision(x, mode);
        final fixed = _toRawFixed(x, mode);
        final significantFirst = precision.magnitude <= fixed.magnitude;
        result =
            (_roundingType == _RoundingType.morePrecision) == significantFirst
                ? precision
                : fixed;
    }
    var string = result.string;
    if (stripIfInteger && result.rounded.isInteger) {
      final point = string.indexOf('.');
      if (point >= 0) string = string.substring(0, point);
    }
    final point = string.indexOf('.');
    final integerDigits = point < 0 ? string.length : point;
    if (integerDigits < minimumIntegerDigits) {
      string = '${'0' * (minimumIntegerDigits - integerDigits)}$string';
    }
    return (string, value.negative ? -result.rounded : result.rounded);
  }

  /// ECMA-402 ToRawPrecision, for a non-negative [x].
  _RawResult _toRawPrecision(Decimal x, UnsignedRounding mode) {
    final p = maximumSignificantDigits;
    String digits;
    int e;
    Decimal rounded;
    if (x.isZero) {
      digits = '0' * p;
      e = 0;
      rounded = x;
    } else {
      e = x.magnitude!;
      rounded = x.round(e - p + 1, mode);
      digits = rounded.coefficient.toString();
      if (digits.length > p) {
        // Rounding carried into a new digit, as from 999 to 1000.
        e++;
        digits = digits.substring(0, p);
      }
    }
    String string;
    if (e >= p - 1) {
      string = digits + '0' * (e - p + 1);
    } else if (e >= 0) {
      string = '${digits.substring(0, e + 1)}.${digits.substring(e + 1)}';
    } else {
      string = '0.${'0' * -(e + 1)}$digits';
    }
    if (string.contains('.')) {
      string = _cut(string, p - minimumSignificantDigits);
    }
    return _RawResult(string, rounded, e - p + 1);
  }

  /// ECMA-402 ToRawFixed, for a non-negative [x].
  _RawResult _toRawFixed(Decimal x, UnsignedRounding mode) {
    final f = maximumFractionDigits;
    final rounded = x.round(-f, mode, increment: roundingIncrement);
    var string = rounded.coefficient.toString();
    if (f != 0) {
      var k = string.length;
      if (k <= f) {
        string = '${'0' * (f + 1 - k)}$string';
        k = f + 1;
      }
      string = '${string.substring(0, k - f)}.${string.substring(k - f)}';
      string = _cut(string, maximumFractionDigits - minimumFractionDigits);
    }
    return _RawResult(string, rounded, -f);
  }

  /// [string] with up to [cut] trailing zeros removed from its fraction,
  /// and without a trailing decimal point.
  static String _cut(String string, int cut) {
    var end = string.length;
    while (cut > 0 && string.codeUnitAt(end - 1) == 0x30) {
      end--;
      cut--;
    }
    if (string.codeUnitAt(end - 1) == 0x2e) end--;
    return string.substring(0, end);
  }

  /// The plural category of [value] as this format rounds it, as ECMA-402
  /// `Intl.PluralRules` with the same options selects it.
  String pluralCategory(Decimal value, {required bool ordinal}) =>
      value.isFinite
          ? _pluralCategory(
              locale.pluralLocales,
              PluralOperands(toRawString(value.abs()).$1),
              ordinal: ordinal,
            )
          : 'other';

  /// [value] formatted as parts, with the part types of ECMA-402
  /// `formatToParts`.
  List<MessageValuePart> formatToParts(Decimal value) {
    final parts = _Parts();
    final (body, rounded) = value.isFinite ? toRawString(value) : (null, value);
    final sign = _sign(rounded);
    final display = currencyDisplay;
    if (style == NumberStyle.currency && display == CurrencyDisplay.name) {
      // Without currency names, the name is the currency code, in the
      // locale's pattern for a number and a unit.
      final category = rounded.isFinite
          ? _pluralCategory(locale.pluralLocales, PluralOperands(body!),
              ordinal: false)
          : 'other';
      final pattern = locale.symbol('unitPattern.$category') ??
          locale.symbol('unitPattern.other') ??
          '{0} {1}';
      final number = _Pattern.parse(_currencyPattern(noCurrency: true));
      for (final piece in RegExp(r'\{[01]\}|[^{]+|\{').allMatches(pattern)) {
        switch (piece[0]) {
          case '{0}':
            _number(parts, number, sign, body, value);
          case '{1}':
            parts.add('currency', currency!);
          case final text:
            parts.add('literal', text!);
        }
      }
      return parts.list;
    }
    final String patternText;
    String? symbol;
    switch (style) {
      case NumberStyle.decimal:
        patternText = locale.symbol('decimalFormat') ?? '#,##0.###';
      case NumberStyle.percent:
        patternText = locale.symbol('percentFormat') ?? '#,##0%';
      case NumberStyle.currency:
        symbol = switch (display) {
          CurrencyDisplay.symbol => locale.currencySymbol(currency!),
          CurrencyDisplay.narrowSymbol =>
            locale.narrowCurrencySymbol(currency!),
          CurrencyDisplay.code => currency!,
          CurrencyDisplay.name || CurrencyDisplay.never => null,
        };
        patternText = _currencyPattern(noCurrency: symbol == null);
    }
    _number(parts, _Pattern.parse(patternText), sign, body, value,
        symbol: symbol);
    return parts.list;
  }

  /// The currency pattern. As in ICU, the `alphaNextToNumber` patterns are
  /// not used: currency spacing separates an alphabetic symbol from the
  /// digits.
  String _currencyPattern({required bool noCurrency}) {
    final accounting = currencySign == CurrencySign.accounting;
    final field = accounting ? 'accountingFormat' : 'currencyFormat';
    if (noCurrency) {
      return locale.symbol('${field}NoCurrency') ??
          locale.symbol('currencyFormatNoCurrency') ??
          '#,##0.00';
    }
    // As in ICU, a currency's own pattern replaces the accounting one too.
    return locale.currencyOverride(currency!, 'pattern') ??
        locale.symbol(field) ??
        '¤#,##0.00';
  }

  /// The decimal or grouping separator ([name] is `decimal` or `group`),
  /// which a currency format can replace.
  String _separator(String name, String fallback) {
    if (style == NumberStyle.currency) {
      final capitalized = '${name[0].toUpperCase()}${name.substring(1)}';
      final separator = locale.currencyOverride(currency!, name) ??
          locale.ownSymbol('currency$capitalized');
      if (separator != null) return separator;
    }
    return locale.symbol(name) ?? fallback;
  }

  /// Adds the parts of a number in [pattern], with [sign], the raw digits
  /// [body] (or `null` for an infinity or NaN), and the currency [symbol].
  void _number(
    _Parts parts,
    _Pattern pattern,
    _Sign sign,
    String? body,
    Decimal value, {
    String? symbol,
  }) {
    final (prefix, suffix) = pattern.affixes(sign);
    for (final token in prefix) {
      _affix(parts, token, symbol);
    }
    // Currency spacing between a symbol and the digits next to it.
    final spacingBefore = locale.symbol('currencySpacingBefore');
    if (body != null &&
        symbol != null &&
        prefix.isNotEmpty &&
        prefix.last.type == _Token.currency &&
        _spacedCurrency.hasMatch(_lastRune(symbol)) &&
        spacingBefore != null) {
      parts.add('literal', spacingBefore);
    }
    if (body == null) {
      parts.add(
        value.isNaN ? 'nan' : 'infinity',
        locale.symbol(value.isNaN ? 'nan' : 'infinity') ??
            (value.isNaN ? 'NaN' : '∞'),
      );
    } else {
      _digits(parts, pattern, body);
    }
    final spacingAfter = locale.symbol('currencySpacingAfter');
    if (body != null &&
        symbol != null &&
        suffix.isNotEmpty &&
        suffix.first.type == _Token.currency &&
        _spacedCurrency.hasMatch(_firstRune(symbol)) &&
        spacingAfter != null) {
      parts.add('literal', spacingAfter);
    }
    for (final token in suffix) {
      _affix(parts, token, symbol);
    }
  }

  void _affix(_Parts parts, _Affix affix, String? symbol) {
    switch (affix.type) {
      case _Token.literal:
        parts.add('literal', affix.text);
      case _Token.minus:
        parts.add('minusSign', locale.symbol('minusSign') ?? '-');
      case _Token.plus:
        parts.add('plusSign', locale.symbol('plusSign') ?? '+');
      case _Token.percent:
        parts.add('percentSign', locale.symbol('percentSign') ?? '%');
      case _Token.currency:
        if (symbol != null) parts.add('currency', symbol);
    }
  }

  void _digits(_Parts parts, _Pattern pattern, String body) {
    final point = body.indexOf('.');
    final integer = point < 0 ? body : body.substring(0, point);
    final minimumGrouping = switch (useGrouping) {
      UseGrouping.never => null,
      UseGrouping.always => 1,
      UseGrouping.min2 => 2,
      UseGrouping.auto => locale.minimumGroupingDigits,
    };
    final primary = pattern.primaryGrouping;
    if (minimumGrouping != null &&
        primary > 0 &&
        integer.length - primary >= minimumGrouping) {
      final secondary = pattern.secondaryGrouping;
      final groups = <String>[];
      var end = integer.length;
      groups.add(integer.substring(end - primary));
      end -= primary;
      while (end > 0) {
        final start = end > secondary ? end - secondary : 0;
        groups.add(integer.substring(start, end));
        end = start;
      }
      final group = _separator('group', ',');
      for (final (index, digits) in groups.reversed.indexed) {
        if (index > 0) parts.add('group', group);
        parts.add('integer', _localDigits(digits));
      }
    } else {
      parts.add('integer', _localDigits(integer));
    }
    if (point >= 0) {
      parts
        ..add('decimal', _separator('decimal', '.'))
        ..add('fraction', _localDigits(body.substring(point + 1)));
    }
  }

  String _localDigits(String ascii) {
    if (locale.numberingSystem == 'latn') return ascii;
    final digits = locale.digits;
    return [for (final unit in ascii.codeUnits) digits[unit - 0x30]].join();
  }

  _Sign _sign(Decimal rounded) {
    final negative = rounded.negative && !rounded.isNaN;
    final zero = rounded.isZero;
    return switch (signDisplay) {
      SignDisplay.never => _Sign.none,
      SignDisplay.auto => negative ? _Sign.minus : _Sign.none,
      SignDisplay.always => negative ? _Sign.minus : _Sign.plus,
      SignDisplay.exceptZero => zero || rounded.isNaN
          ? _Sign.none
          : negative
              ? _Sign.minus
              : _Sign.plus,
      SignDisplay.negative => negative && !zero ? _Sign.minus : _Sign.none,
    };
  }
}

String _pluralCategory(
  List<String> locales,
  PluralOperands operands, {
  required bool ordinal,
}) =>
    pluralCategory(locales, operands, ordinal: ordinal);

/// A currency symbol character that is separated from adjacent digits: one
/// that is neither a symbol nor a separator, as CLDR's `currencyMatch`
/// `[[:^S:]&[:^Z:]]` says.
final _spacedCurrency = RegExp(r'^[^\p{S}\p{Z}]$', unicode: true);

String _firstRune(String text) =>
    text.isEmpty ? '' : String.fromCharCode(text.runes.first);

String _lastRune(String text) =>
    text.isEmpty ? '' : String.fromCharCode(text.runes.last);

final class _RawResult {
  _RawResult(this.string, this.rounded, this.magnitude);

  final String string;
  final Decimal rounded;

  /// ECMA-402's `[[RoundingMagnitude]]`.
  final int magnitude;
}

enum _Sign { none, minus, plus }

/// The parts being built, with adjacent literals merged.
final class _Parts {
  final list = <MessageValuePart>[];

  int get length => list.length;

  void add(String type, String value) {
    if (value.isEmpty) return;
    if (type == 'literal' && list.isNotEmpty && list.last.type == 'literal') {
      list.last = MessageValuePart('literal', list.last.value + value);
    } else {
      list.add(MessageValuePart(type, value));
    }
  }
}

enum _Token { literal, minus, plus, percent, currency }

final class _Affix {
  const _Affix(this.type, [this.text = '']);

  final _Token type;
  final String text;
}

/// A parsed CLDR number pattern, such as `#,##0.00 ¤` or
/// `¤#,##0.00;(¤#,##0.00)`.
final class _Pattern {
  _Pattern._(
    this._prefix,
    this._suffix,
    this._negativePrefix,
    this._negativeSuffix,
    this.primaryGrouping,
    this.secondaryGrouping,
  );

  factory _Pattern.parse(String pattern) => _cache[pattern] ??= _parse(pattern);

  static final _cache = <String, _Pattern>{};

  static _Pattern _parse(String pattern) {
    final subpatterns = _splitSubpatterns(pattern);
    final (prefix, number, suffix) = _parseSubpattern(subpatterns.first);
    final negative =
        subpatterns.length > 1 ? _parseSubpattern(subpatterns[1]) : null;
    final integer = number.contains('.')
        ? number.substring(0, number.indexOf('.'))
        : number;
    final groups = integer.split(',');
    final primary = groups.length > 1 ? groups.last.length : 0;
    final secondary =
        groups.length > 2 ? groups[groups.length - 2].length : primary;
    return _Pattern._(
      prefix,
      suffix,
      negative?.$1,
      negative?.$3,
      primary,
      secondary,
    );
  }

  static List<String> _splitSubpatterns(String pattern) {
    var quoted = false;
    for (var i = 0; i < pattern.length; i++) {
      final char = pattern[i];
      if (char == "'") quoted = !quoted;
      if (char == ';' && !quoted) {
        return [pattern.substring(0, i), pattern.substring(i + 1)];
      }
    }
    return [pattern];
  }

  static (List<_Affix>, String, List<_Affix>) _parseSubpattern(String pattern) {
    final prefix = <_Affix>[];
    final suffix = <_Affix>[];
    final number = StringBuffer();
    var affixes = prefix;
    var quoted = false;
    final literal = StringBuffer();
    void flush() {
      if (literal.isNotEmpty) {
        affixes.add(_Affix(_Token.literal, literal.toString()));
        literal.clear();
      }
    }

    for (var i = 0; i < pattern.length; i++) {
      final char = pattern[i];
      if (quoted) {
        if (char == "'") {
          if (i + 1 < pattern.length && pattern[i + 1] == "'") {
            literal.write("'");
            i++;
          } else {
            quoted = false;
          }
        } else {
          literal.write(char);
        }
        continue;
      }
      if (affixes == prefix && '#0,.123456789@'.contains(char)) {
        number.write(char);
        continue;
      }
      if (number.isNotEmpty && affixes == prefix) {
        flush();
        affixes = suffix;
      }
      switch (char) {
        case "'":
          if (i + 1 < pattern.length && pattern[i + 1] == "'") {
            literal.write("'");
            i++;
          } else {
            quoted = true;
          }
        case '-':
          flush();
          affixes.add(const _Affix(_Token.minus));
        case '+':
          flush();
          affixes.add(const _Affix(_Token.plus));
        case '%':
          flush();
          affixes.add(const _Affix(_Token.percent));
        case '¤':
          flush();
          while (i + 1 < pattern.length && pattern[i + 1] == '¤') {
            i++;
          }
          affixes.add(const _Affix(_Token.currency));
        default:
          literal.write(char);
      }
    }
    if (number.isNotEmpty && affixes == prefix) {
      flush();
      affixes = suffix;
    }
    flush();
    return (prefix, number.toString(), suffix);
  }

  final List<_Affix> _prefix;
  final List<_Affix> _suffix;
  final List<_Affix>? _negativePrefix;
  final List<_Affix>? _negativeSuffix;

  /// The size of the group of digits before the decimal point, or 0 for no
  /// grouping.
  final int primaryGrouping;

  /// The size of the other groups.
  final int secondaryGrouping;

  /// The prefix and suffix for [sign].
  ///
  /// Without a negative subpattern, a sign goes before the prefix. A plus
  /// sign replaces the minus sign of a negative subpattern that has one.
  (List<_Affix>, List<_Affix>) affixes(_Sign sign) {
    final negativePrefix = _negativePrefix;
    final negativeSuffix = _negativeSuffix;
    final hasNegative = negativePrefix != null && negativeSuffix != null;
    final hasMinus = hasNegative &&
        [...negativePrefix, ...negativeSuffix]
            .any((affix) => affix.type == _Token.minus);
    switch (sign) {
      case _Sign.none:
        return (_prefix, _suffix);
      case _Sign.minus when hasNegative:
        return (negativePrefix, negativeSuffix);
      case _Sign.plus when hasMinus:
        _Affix plus(_Affix affix) =>
            affix.type == _Token.minus ? const _Affix(_Token.plus) : affix;
        return (
          negativePrefix.map(plus).toList(),
          negativeSuffix.map(plus).toList(),
        );
      case _Sign.minus:
        return ([const _Affix(_Token.minus), ..._prefix], _suffix);
      case _Sign.plus:
        return ([const _Affix(_Token.plus), ..._prefix], _suffix);
    }
  }
}
