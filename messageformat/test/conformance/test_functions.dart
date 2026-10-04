/// The suite's test-only functions `:test:function`, `:test:select`, and
/// `:test:format`, as the "Test Functions" section of the vendored
/// `README.md` specifies them.
///
/// This file holds their behaviour independently of the public API, which
/// #5 defines. The subject adapter wraps [TestFunctionValue] in the public
/// custom-function interface, so the functions are registered only in the
/// harness and through the public API, never through private hooks.
library;

/// One of the three test functions.
enum TestFunction {
  /// `:test:function`, a selector and a formatter.
  function('test:function', canFormat: true, canSelect: true),

  /// `:test:select`, a selector that cannot format.
  select('test:select', canFormat: false, canSelect: true),

  /// `:test:format`, a formatter that cannot select.
  format('test:format', canFormat: true, canSelect: false);

  const TestFunction(
    this.functionName, {
    required this.canFormat,
    required this.canSelect,
  });

  /// The name used in messages, without the leading colon.
  final String functionName;

  /// Whether a placeholder with this function can be formatted. If not, the
  /// runtime emits an error and formats a fallback value.
  final bool canFormat;

  /// Whether this function can be used as a selector. If not, the runtime
  /// follows step 2.iii of *Resolve Selectors* (a Bad Selector error).
  final bool canSelect;
}

/// An error a test function reports, named as in the suite's schema.
final class TestFunctionError implements Exception {
  const TestFunctionError(this.type, this.message);

  /// The error type, such as `bad-operand` or `bad-option`.
  final String type;

  final String message;

  @override
  String toString() => 'TestFunctionError($type): $message';
}

/// A part of a formatted test value.
typedef TestFunctionPart = ({String type, String value});

/// The resolved value of an expression annotated with a test function.
final class TestFunctionValue {
  const TestFunctionValue._(
    this.function, {
    required this.input,
    required this.decimalPlaces,
    required this.failsFormat,
    required this.failsSelect,
  });

  /// Resolves [function] with its [operand] and resolved [options].
  ///
  /// [options] holds only the options that resolved; option resolution
  /// leaves out the ones that did not. An error that the README says to emit
  /// while resolution continues is passed to [onError]. An error after which
  /// the expression resolves to a fallback value is thrown as a
  /// [TestFunctionError].
  ///
  /// The README calls the operand error "bad-input", but the suite expects
  /// `bad-operand` (see `fallback.json`), so that is the type used.
  factory TestFunctionValue.resolve(
    TestFunction function,
    Object? operand,
    Map<String, Object?> options, {
    required void Function(TestFunctionError error) onError,
  }) {
    var decimalPlaces = 0;
    var failsFormat = false;
    var failsSelect = false;
    final num input;
    if (operand is TestFunctionValue) {
      input = operand.input;
      decimalPlaces = operand.decimalPlaces;
      failsFormat = operand.failsFormat;
      failsSelect = operand.failsSelect;
    } else if (_numericValue(operand) case final value?) {
      input = value;
    } else {
      throw TestFunctionError(
        'bad-operand',
        'The operand of :${function.functionName} is not numeric: $operand',
      );
    }

    if (options.containsKey('decimalPlaces')) {
      final value = options['decimalPlaces'];
      decimalPlaces = switch (_optionValue(value)) {
        0 || '0' => 0,
        1 || '1' => 1,
        _ => throw TestFunctionError(
            'bad-option',
            'Invalid option decimalPlaces=$value',
          ),
      };
    }

    if (options.containsKey('fails')) {
      switch (_optionValue(options['fails'])) {
        case 'always':
          failsFormat = true;
          failsSelect = true;
        case 'format':
          failsFormat = true;
        case 'select':
          failsSelect = true;
        case 'never':
          break;
        case final value:
          onError(
              TestFunctionError('bad-option', 'Invalid option fails=$value'));
      }
    }

    return TestFunctionValue._(
      function,
      input: input,
      decimalPlaces: decimalPlaces,
      failsFormat: failsFormat,
      failsSelect: failsSelect,
    );
  }

  /// The function that produced this value. A value passed as the operand
  /// of another test function keeps that function's settings but takes on
  /// the new function's [TestFunction.canFormat] and
  /// [TestFunction.canSelect].
  final TestFunction function;

  /// The numeric input. When the value is used as an option value, its
  /// resolved value is this input.
  final num input;

  /// 0 or 1.
  final int decimalPlaces;

  final bool failsFormat;

  final bool failsSelect;

  /// Match(`rv`, [key]) from *Pattern Selection*.
  ///
  /// Throws a `bad-option` [TestFunctionError] when the value fails
  /// selection. The runtime reports a selection failure as a Bad Selector.
  bool match(String key) {
    _checkCan(function.canSelect, 'select');
    if (failsSelect) {
      throw const TestFunctionError('bad-option', 'Selection failed');
    }
    if (input != 1) return false;
    return key == '1' || (decimalPlaces == 1 && key == '1.0');
  }

  /// BetterThan(`rv`, [key1], [key2]) from *Pattern Selection*.
  bool betterThan(String key1, String key2) {
    _checkCan(function.canSelect, 'select');
    return key1 == '1.0';
  }

  /// The formatted parts: an optional `-`, the integer digits, and with one
  /// decimal place a `.` and the first fraction digit.
  ///
  /// Throws a `bad-option` [TestFunctionError] when the value fails
  /// formatting.
  List<TestFunctionPart> formatToParts() {
    _checkCan(function.canFormat, 'format');
    if (failsFormat) {
      throw const TestFunctionError('bad-option', 'Formatting failed');
    }
    final (integer, tenths) = _truncatedDigits(input.abs());
    return [
      if (input < 0) (type: 'neg', value: '-'),
      (type: 'int', value: integer),
      if (decimalPlaces == 1) ...[
        (type: 'dot', value: '.'),
        (type: 'frac', value: tenths),
      ],
    ];
  }

  /// The integer digits and the first fraction digit of [value], which is
  /// finite and not negative, truncated as written in decimal.
  ///
  /// The digits come from the shortest decimal representation of a double
  /// rather than from arithmetic: `(1.2 - 1) * 10` is just below 2, and
  /// `floor()` of a double of 2^63 or more does not fit in an `int`.
  static (String, String) _truncatedDigits(num value) {
    if (value is int) return ('$value', '0');
    // Dart writes doubles of 1e21 or more and below 1e-6 with an exponent.
    final [mantissa, ...exponent] = value.toString().split('e');
    final [whole, ...fraction] = mantissa.split('.');
    final digits = whole + (fraction.isEmpty ? '' : fraction.single);
    final point =
        whole.length + (exponent.isEmpty ? 0 : int.parse(exponent.single));
    if (point <= 0) return ('0', '0');
    return (
      digits.padRight(point, '0').substring(0, point),
      point < digits.length ? digits[point] : '0',
    );
  }

  /// The concatenation of [formatToParts].
  String format() => formatToParts().map((part) => part.value).join();

  void _checkCan(bool can, String operation) {
    if (!can) {
      throw StateError(':${function.functionName} cannot $operation');
    }
  }

  /// The numeric value of [operand] if it is a finite number or a string
  /// matching the `number-literal` production, otherwise `null`.
  static num? _numericValue(Object? operand) {
    final value = switch (operand) {
      final num number => number,
      final String text when _numberLiteral.hasMatch(text) => num.parse(text),
      _ => null,
    };
    return value != null && value.isFinite ? value : null;
  }

  /// A test value used as an option value resolves to its input.
  static Object? _optionValue(Object? value) {
    final unwrapped = value is TestFunctionValue ? value.input : value;
    // An integral double such as 1.0 is the numerical integer value 1.
    if (unwrapped is double &&
        unwrapped.isFinite &&
        unwrapped == unwrapped.truncateToDouble()) {
      return unwrapped.toInt();
    }
    return unwrapped;
  }
}

/// The `number-literal` production from *Number Operands* in the spec.
final _numberLiteral =
    RegExp(r'^-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?(?:[eE][-+]?[0-9]+)?$');
