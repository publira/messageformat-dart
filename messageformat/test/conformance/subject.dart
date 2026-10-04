/// The boundary between the conformance harness and the implementation.
///
/// The public formatting API is defined by #5. Until then the harness talks
/// to the implementation only through [ConformanceSubject], and [subject] is
/// a placeholder that every case is skipped around (see `notYetImplemented`
/// in `manifest.dart`). #5 replaces [subject] with an adapter over the public
/// API that registers `:test:function`, `:test:select`, and `:test:format`
/// (built from `test_functions.dart`) through the public custom-function API.
library;

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
const ConformanceSubject subject = _NotYetImplemented();

final class _NotYetImplemented implements ConformanceSubject {
  const _NotYetImplemented();

  @override
  FormatOutcome format({
    required String locale,
    required String src,
    required String? bidiIsolation,
    required Map<String, Object?>? params,
  }) =>
      throw UnimplementedError('The formatting API is added by #5.');

  @override
  PartsOutcome formatToParts({
    required String locale,
    required String src,
    required String? bidiIsolation,
    required Map<String, Object?>? params,
  }) =>
      throw UnimplementedError('The formatting API is added by #5.');
}
