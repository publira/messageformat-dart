/// An exact decimal number, an infinity, or NaN: the numeric value of a
/// numeric operand.
///
/// A finite value is `±coefficient × 10^exponent`. Keeping numbers in
/// decimal lets the number functions round them exactly as written, so
/// that `{0.125 :number maximumFractionDigits=2}` formats as `0.13` with
/// the default `halfExpand` rounding, where a [double] would hold slightly
/// less than 0.125.
final class Decimal {
  const Decimal._(this.negative, this.coefficient, this.exponent, this._kind);

  /// A finite value.
  Decimal.finite(this.negative, this.coefficient, this.exponent)
      : _kind = _Kind.finite;

  /// Positive or negative infinity.
  const Decimal.infinity({this.negative = false})
      : coefficient = null,
        exponent = 0,
        _kind = _Kind.infinity;

  /// Not a number.
  const Decimal.nan()
      : negative = false,
        coefficient = null,
        exponent = 0,
        _kind = _Kind.nan;

  /// The value of [value], a Dart number.
  factory Decimal.fromNum(num value) {
    if (value is int) return Decimal.fromBigInt(BigInt.from(value));
    if (value.isNaN) return const Decimal.nan();
    if (value.isInfinite) return Decimal.infinity(negative: value < 0);
    // The shortest string that reads back as the same double, as the JS
    // Intl.NumberFormat would format it.
    final text = value.toString();
    final match = _doubleString.firstMatch(text)!;
    final fraction = match[3] ?? '';
    return Decimal.finite(
      match[1] != null,
      BigInt.parse('${match[2]}$fraction'),
      int.parse(match[4] ?? '0') - fraction.length,
    );
  }

  /// The value of [value].
  factory Decimal.fromBigInt(BigInt value) =>
      Decimal.finite(value.isNegative, value.abs(), 0);

  /// The value of a string that matches the `number-literal` production of
  /// the specification, or `null` if [literal] does not.
  ///
  /// An exponent too large for an [int] is kept as [maxExponent], which is
  /// beyond any number that can be formatted.
  static Decimal? tryParse(String literal) {
    final match = _numberLiteral.firstMatch(literal);
    if (match == null) return null;
    final fraction = match[3] ?? '';
    final exponentText = match[4];
    var exponent = 0;
    if (exponentText != null) {
      exponent = int.tryParse(exponentText) ??
          (exponentText.startsWith('-') ? -maxExponent : maxExponent);
      exponent = exponent.clamp(-maxExponent, maxExponent);
    }
    return Decimal.finite(
      match[1] != null,
      BigInt.parse('${match[2]}$fraction'),
      exponent - fraction.length,
    );
  }

  /// A bound on exponents, far beyond any number that can be formatted.
  static const maxExponent = 1 << 30;

  /// Whether the value is negative, including negative zero.
  final bool negative;

  /// The coefficient of a finite value, which is never negative.
  final BigInt? coefficient;

  /// The exponent of a finite value.
  final int exponent;

  final _Kind _kind;

  bool get isFinite => _kind == _Kind.finite;

  bool get isNaN => _kind == _Kind.nan;

  bool get isInfinite => _kind == _Kind.infinity;

  bool get isZero => isFinite && coefficient == BigInt.zero;

  /// Whether the value is finite and has no fraction.
  bool get isInteger {
    if (!isFinite) return false;
    if (exponent >= 0 || isZero) return true;
    return _trailingZeros(coefficient!) >= -exponent;
  }

  /// The exponent of the value's most significant digit, such as 2 for 123
  /// and -2 for 0.012, or `null` for zero and non-finite values.
  int? get magnitude => isFinite && !isZero
      ? coefficient!.toString().length - 1 + exponent
      : null;

  /// The absolute value.
  Decimal abs() =>
      negative ? Decimal._(false, coefficient, exponent, _kind) : this;

  /// The value with the opposite sign.
  Decimal operator -() =>
      isNaN ? this : Decimal._(!negative, coefficient, exponent, _kind);

  /// The value times 10^[places].
  Decimal scaleByPowerOfTen(int places) => isFinite
      ? Decimal.finite(negative, coefficient!, exponent + places)
      : this;

  /// The sum of the value and [other].
  Decimal operator +(Decimal other) {
    if (isNaN || other.isNaN) return const Decimal.nan();
    if (isInfinite) {
      return other.isInfinite && other.negative != negative
          ? const Decimal.nan()
          : this;
    }
    if (other.isInfinite) return other;
    final exponent =
        this.exponent < other.exponent ? this.exponent : other.exponent;
    final sum =
        _signedCoefficient(exponent) + other._signedCoefficient(exponent);
    if (sum == BigInt.zero) {
      // As in IEEE 754, x + -x is +0 and -0 + -0 is -0.
      return Decimal.finite(negative && other.negative, BigInt.zero, exponent);
    }
    return Decimal.finite(sum.isNegative, sum.abs(), exponent);
  }

  BigInt _signedCoefficient(int exponent) {
    final scaled = coefficient! * BigInt.from(10).pow(this.exponent - exponent);
    return negative ? -scaled : scaled;
  }

  /// The value rounded to a multiple of [increment] × 10^[magnitude], as
  /// ECMA-402 rounds with an *unsigned rounding mode*: the result is the
  /// same sign as this value and [mode] applies to its absolute value.
  Decimal round(int magnitude, UnsignedRounding mode, {int increment = 1}) {
    if (!isFinite) return this;
    final coefficient = this.coefficient!;
    final unit = BigInt.from(increment);
    final shift = exponent - magnitude;
    // The absolute value is (quotient + remainder / divisor) units.
    BigInt quotient;
    BigInt remainder;
    BigInt divisor;
    if (shift >= 0) {
      final scaled = coefficient * BigInt.from(10).pow(shift);
      quotient = scaled ~/ unit;
      remainder = scaled.remainder(unit);
      divisor = unit;
    } else if (-shift > coefficient.toString().length + 1) {
      // Less than a tenth of a unit, so below half of one.
      quotient = BigInt.zero;
      remainder = coefficient == BigInt.zero ? BigInt.zero : BigInt.one;
      divisor = BigInt.from(4);
    } else {
      divisor = BigInt.from(10).pow(-shift) * unit;
      quotient = coefficient ~/ divisor;
      remainder = coefficient.remainder(divisor);
    }
    if (remainder != BigInt.zero) {
      final half = (remainder * BigInt.two).compareTo(divisor);
      final up = switch (mode) {
        UnsignedRounding.zero => false,
        UnsignedRounding.infinity => true,
        _ when half != 0 => half > 0,
        UnsignedRounding.halfZero => false,
        UnsignedRounding.halfInfinity => true,
        UnsignedRounding.halfEven => quotient.isOdd,
      };
      if (up) quotient += BigInt.one;
    }
    return Decimal.finite(negative, quotient * unit, magnitude);
  }

  /// The value as an integer, or a decimal number without an exponent or
  /// trailing fraction zeros, such as `-12` or `0.025`, or `null` if it is
  /// not finite or that string would be longer than [maxLength].
  ///
  /// Negative zero is `0`.
  String? toPlainString(int maxLength) {
    if (!isFinite) return null;
    if (isZero) return '0';
    var coefficient = this.coefficient!;
    var exponent = this.exponent;
    if (exponent < 0) {
      final zeros = _trailingZeros(coefficient);
      final drop = zeros < -exponent ? zeros : -exponent;
      coefficient = coefficient ~/ BigInt.from(10).pow(drop);
      exponent += drop;
    }
    final digits = coefficient.toString();
    final length = (negative ? 1 : 0) +
        (exponent >= 0
            ? digits.length + exponent
            : (digits.length > -exponent ? digits.length : -exponent + 1) + 1);
    if (length > maxLength) return null;
    final sign = negative ? '-' : '';
    if (exponent >= 0) return '$sign$digits${'0' * exponent}';
    final point = digits.length + exponent;
    return point > 0
        ? '$sign${digits.substring(0, point)}.${digits.substring(point)}'
        : '${sign}0.${'0' * -point}$digits';
  }

  @override
  String toString() => switch (_kind) {
        _Kind.nan => 'NaN',
        _Kind.infinity => negative ? '-Infinity' : 'Infinity',
        _Kind.finite => '${negative ? '-' : ''}${coefficient}e$exponent',
      };

  static int _trailingZeros(BigInt value) {
    if (value == BigInt.zero) return 0;
    final digits = value.toString();
    var count = 0;
    while (digits.codeUnitAt(digits.length - 1 - count) == 0x30) {
      count++;
    }
    return count;
  }

  static final _numberLiteral =
      RegExp(r'^(-)?(0|[1-9][0-9]*)(?:\.([0-9]+))?(?:[eE]([-+]?[0-9]+))?$');

  static final _doubleString =
      RegExp(r'^(-)?([0-9]+)(?:\.([0-9]+))?(?:e([-+]?[0-9]+))?$');
}

enum _Kind { finite, infinity, nan }

/// An ECMA-402 *unsigned rounding mode*: how to round an absolute value
/// that lies between two candidates.
enum UnsignedRounding {
  /// Toward zero.
  zero,

  /// Away from zero.
  infinity,

  /// To the nearer candidate, toward zero on a tie.
  halfZero,

  /// To the nearer candidate, away from zero on a tie.
  halfInfinity,

  /// To the nearer candidate, to the even one on a tie.
  halfEven,
}
