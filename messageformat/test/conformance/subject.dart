/// The boundary between the conformance harness and the implementation.
///
/// The harness talks to the implementation only through [ConformanceSubject].
/// [subject] adapts the public API: [ConformanceSubject.parse] calls
/// `parseMessage`. The public formatting API is defined by #5, so until then
/// the formatting methods throw, and the files that need them are skipped or
/// checked with `parse` only (see `manifest.dart`). #5 implements them over
/// the public API and registers `:test:function`, `:test:select`, and
/// `:test:format` (built from `test_functions.dart`) through the public
/// custom-function API.
library;

import 'package:messageformat/messageformat.dart';

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
