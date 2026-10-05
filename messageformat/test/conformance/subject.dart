/// The boundary between the conformance harness and the implementation.
///
/// The harness talks to the implementation only through [ConformanceSubject].
/// [subject] adapts the public API: [ConformanceSubject.parse] calls
/// `parseMessage`, and the formatting methods create a `MessageFormat` with
/// `:test:function`, `:test:select`, and `:test:format` (built from
/// `test_functions.dart`) and the date/time functions of
/// `package:messageformat_datetime` registered through the public
/// custom-function API.
library;

import 'package:messageformat/messageformat.dart';
import 'package:messageformat_datetime/messageformat_datetime.dart';

import 'test_functions.dart';

/// The outcome of formatting a message to a string.
typedef FormatOutcome = ({
  /// The formatted string, or `null` when the implementation produced none,
  /// for example because the message failed to parse.
  String? value,

  /// The error types reported, using the suite's names such as
  /// `unresolved-variable`.
  List<String> errors,
});

/// The outcome of formatting a message to parts.
typedef PartsOutcome = ({
  /// The parts as JSON-like maps in the shape of the suite's `expParts`, or
  /// `null` when the implementation produced none.
  List<Map<String, Object?>>? parts,

  /// The error types reported, using the suite's names.
  List<String> errors,
});

/// What the harness needs from an implementation.
///
/// Implementations must report errors instead of throwing them, so that the
/// harness can compare them to `expErrors`. A Syntax Error or Data Model
/// Error that prevents formatting is reported with a `null` result.
abstract interface class ConformanceSubject {
  /// Parses [src] without formatting it, returning the types of the Syntax
  /// Errors and Data Model Errors reported.
  List<String> parse(String src);

  /// Formats [src] to a string.
  ///
  /// [bidiIsolation] is `'default'`, `'none'`, or `null` for the
  /// implementation's default.
  FormatOutcome format({
    required String locale,
    required String src,
    required String? bidiIsolation,
    required Map<String, Object?>? params,
  });

  /// Formats [src] to parts, with the same arguments as [format].
  PartsOutcome formatToParts({
    required String locale,
    required String src,
    required String? bidiIsolation,
    required Map<String, Object?>? params,
  });
}

/// The implementation under test.
const ConformanceSubject subject = _Subject();

final class _Subject implements ConformanceSubject {
  const _Subject();

  @override
  List<String> parse(String src) {
    final errors = <String>[];
    try {
      parseMessage(src, onError: (error) => errors.add(error.type));
    } on MessageSyntaxError catch (error) {
      errors.add(error.type);
    }
    return errors;
  }

  @override
  FormatOutcome format({
    required String locale,
    required String src,
    required String? bidiIsolation,
    required Map<String, Object?>? params,
  }) {
    final errors = parse(src);
    if (errors.isNotEmpty) return (value: null, errors: errors);
    final value = _create(locale, src, bidiIsolation)
        .format(params, (error) => errors.add(error.type));
    return (value: value, errors: errors);
  }

  @override
  PartsOutcome formatToParts({
    required String locale,
    required String src,
    required String? bidiIsolation,
    required Map<String, Object?>? params,
  }) {
    final errors = parse(src);
    if (errors.isNotEmpty) return (parts: null, errors: errors);
    final parts = _create(locale, src, bidiIsolation)
        .formatToParts(params, (error) => errors.add(error.type));
    return (parts: parts.map(_partToJson).toList(), errors: errors);
  }

  static MessageFormat _create(
    String locale,
    String src,
    String? bidiIsolation,
  ) =>
      MessageFormat(
        locale,
        src,
        options: MessageFormatOptions(
          bidiIsolation: switch (bidiIsolation) {
            null || 'default' => BidiIsolation.defaultStrategy,
            'none' => BidiIsolation.none,
            _ => throw ArgumentError.value(bidiIsolation, 'bidiIsolation'),
          },
          functions: _functions,
        ),
      );

  static Map<String, Object?> _partToJson(MessagePart part) => switch (part) {
        MessageTextPart(:final value) ||
        MessageBidiIsolationPart(:final value) =>
          {'type': part.type, 'value': value},
        MessageFallbackPart(:final source) => {
            'type': part.type,
            'source': source,
          },
        MessageMarkupPart() => {
            'type': part.type,
            'kind': part.kind.name,
            'name': part.name,
            'options': part.options,
            if (part.id case final id?) 'id': id,
          },
        MessageExpressionPart() => {
            'type': part.type,
            'source': part.source,
            'value': part.value,
            'dir': part.dir.name,
            if (part.locale case final locale?) 'locale': locale,
            if (part.id case final id?) 'id': id,
            if (part.parts case final parts?)
              'parts': [
                for (final part in parts)
                  {'type': part.type, 'value': part.value},
              ],
          },
      };
}

/// The test functions, by identifier.
/// The functions that every message can use beyond the core's default
/// ones.
final Map<String, MessageFunction> _functions = {
  ...dateTimeFunctions,
  ..._testFunctions,
};

final Map<String, MessageFunction> _testFunctions = {
  for (final function in TestFunction.values)
    function.functionName: (context, options, operand) {
      void onError(TestFunctionError error) =>
          context.onError(_publicError(error, context.source));
      try {
        final value = TestFunctionValue.resolve(
          function,
          _unwrap(operand),
          options.map((name, value) => MapEntry(name, _unwrap(value))),
          onError: onError,
        );
        return function.canSelect
            ? _SelectableTestValue(value)
            : _TestValue(value);
      } on TestFunctionError catch (error) {
        throw _publicError(error, context.source);
      }
    },
};

/// The [TestFunctionValue] of a test function's result, or the
/// [MessageValue.value] of another function's.
Object? _unwrap(Object? value) => switch (value) {
      _TestValue(:final testValue) => testValue,
      MessageValue(:final value) => value,
      _ => value,
    };

MessageFunctionError _publicError(TestFunctionError error, String source) =>
    MessageFunctionError(error.type, error.message, source: source);

/// The resolved value of a test function that cannot select.
class _TestValue extends MessageValue {
  _TestValue(this.testValue);

  final TestFunctionValue testValue;

  @override
  String get type => 'test';

  @override
  Object? get value => testValue.input;

  @override
  String formatToString() => formatToParts().map((part) => part.value).join();

  @override
  List<MessageValuePart> formatToParts() {
    final function = testValue.function;
    if (!function.canFormat) {
      // The README names this error but leaves it out of the schema.
      throw MessageFunctionError(
        'not-formattable',
        ':${function.functionName} cannot format',
      );
    }
    try {
      return [
        for (final (:type, :value) in testValue.formatToParts())
          MessageValuePart(type, value),
      ];
    } on TestFunctionError catch (error) {
      throw MessageFunctionError(error.type, error.message);
    }
  }
}

/// The resolved value of a test function that can select.
final class _SelectableTestValue extends _TestValue
    implements SelectableMessageValue {
  _SelectableTestValue(super.testValue);

  @override
  bool match(String key) => testValue.match(key);

  @override
  bool betterThan(String key1, String key2) => testValue.betterThan(key1, key2);
}
