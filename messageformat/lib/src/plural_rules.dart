import 'plural_rules_data.dart';

/// The CLDR plural rules of one locale and type, generated from CLDR data
/// into `plural_rules_data.dart`.
typedef PluralRule = String Function(PluralOperands operands);

/// The plural operands of a formatted number (UTS #35, Part 3, *Plural
/// Operand Meanings*).
///
/// The compact exponent operands `c` and `e` are always 0 and have no
/// fields, since numbers are never formatted in compact notation.
///
/// Integer operands too large for the rules to compare exactly are kept
/// congruent to their value modulo 10^6, which every modulus in CLDR's rules
/// divides, and greater than every value in them.
final class PluralOperands {
  /// The operands of [formatted], a non-negative number in ASCII digits with
  /// an optional `.` and fraction, such as `1.50`.
  factory PluralOperands(String formatted) {
    final point = formatted.indexOf('.');
    final integer = point < 0 ? formatted : formatted.substring(0, point);
    final fraction = point < 0 ? '' : formatted.substring(point + 1);
    var end = fraction.length;
    while (end > 0 && fraction.codeUnitAt(end - 1) == 0x30) {
      end--;
    }
    final trimmed = fraction.substring(0, end);
    return PluralOperands._(
      i: _bounded(integer),
      v: fraction.length,
      w: trimmed.length,
      f: _bounded(fraction),
      t: _bounded(trimmed),
    );
  }

  const PluralOperands._({
    required this.i,
    required this.v,
    required this.w,
    required this.f,
    required this.t,
  });

  /// The integer digits.
  final int i;

  /// The number of visible fraction digits, with trailing zeros.
  final int v;

  /// The number of visible fraction digits, without trailing zeros.
  final int w;

  /// The visible fraction digits, with trailing zeros, as an integer.
  final int f;

  /// The visible fraction digits, without trailing zeros, as an integer.
  final int t;

  /// The value of [digits], or one congruent to it modulo 10^6 and at least
  /// 10^15 if it has more than 15 significant digits.
  static int _bounded(String digits) {
    var start = 0;
    while (start < digits.length && digits.codeUnitAt(start) == 0x30) {
      start++;
    }
    if (start == digits.length) return 0;
    if (digits.length - start <= 15) return int.parse(digits.substring(start));
    return 1000000000000000 + int.parse(digits.substring(digits.length - 6));
  }
}

/// The plural category, such as `one` or `other`, of [operands] under the
/// rules of the first of [locales] in [rules] that has them, or `other`.
///
/// [locales] are CLDR locale identifiers, most specific first.
String pluralCategory(
  Iterable<String> locales,
  PluralOperands operands, {
  required bool ordinal,
}) {
  final rules = ordinal ? ordinalRules : cardinalRules;
  for (final locale in locales) {
    if (rules[locale] case final rule?) return rule(operands);
  }
  return 'other';
}
