/// An error defined by the MessageFormat 2.0 specification.
///
/// [type] is the error's name in the conformance suite, such as
/// `syntax-error` or `unresolved-variable`. When the error comes from
/// message source, [start] and [end] locate the offending text as UTF-16
/// code unit offsets into that source.
abstract class MessageError implements Exception {
  /// Creates an error with a description and, for errors in source, its
  /// location.
  MessageError(this.message, {this.start, this.end});

  /// The error type, using the names of the conformance suite.
  String get type;

  /// A human-readable description of the error.
  final String message;

  /// The offset in the source at which the offending text starts, or `null`
  /// when the error does not come from source.
  final int? start;

  /// The offset in the source just after the offending text, or `null` when
  /// the error does not come from source.
  final int? end;

  @override
  String toString() {
    final location = start == null ? '' : ' at $start';
    return '$runtimeType ($type$location): $message';
  }
}

/// A *Syntax Error*: the source is not a well-formed message.
final class MessageSyntaxError extends MessageError {
  /// Creates a Syntax Error at [start] in the source.
  MessageSyntaxError(super.message, {required int super.start, super.end});

  @override
  String get type => 'syntax-error';
}

/// The kinds of *Data Model Error* the specification defines.
enum DataModelErrorKind {
  /// A variant does not have one key per selector.
  variantKeyMismatch('variant-key-mismatch'),

  /// No variant has only catch-all keys.
  missingFallbackVariant('missing-fallback-variant'),

  /// A selector does not reference a declaration with a function, directly
  /// or indirectly.
  missingSelectorAnnotation('missing-selector-annotation'),

  /// A variable is declared more than once, or is declared after a previous
  /// declaration used it.
  duplicateDeclaration('duplicate-declaration'),

  /// An option name appears more than once in a function or markup.
  duplicateOptionName('duplicate-option-name'),

  /// Two variants have the same list of keys.
  duplicateVariant('duplicate-variant');

  const DataModelErrorKind(this.type);

  /// The error type, using the names of the conformance suite.
  final String type;
}

/// A *Data Model Error*: the message is well-formed but not valid.
final class MessageDataModelError extends MessageError {
  /// Creates a Data Model Error of the given [kind].
  MessageDataModelError(this.kind, super.message, {super.start, super.end});

  /// Which Data Model Error this is.
  final DataModelErrorKind kind;

  @override
  String get type => kind.type;
}

/// The kinds of *Resolution Error* the specification defines.
enum ResolutionErrorKind {
  /// A variable has no declaration and no value in the input mapping.
  unresolvedVariable('unresolved-variable'),

  /// No function handler is registered for a function's identifier.
  unknownFunction('unknown-function'),

  /// A selector's resolved value does not support selection, or selecting
  /// with it failed.
  badSelector('bad-selector');

  const ResolutionErrorKind(this.type);

  /// The error type, using the names of the conformance suite.
  final String type;
}

/// A *Resolution Error*: the runtime value of part of a message cannot be
/// determined.
///
/// Formatting passes it to the `onError` callback and still produces a
/// result, with a fallback value where the error occurred. It corresponds
/// to `MessageResolutionError` in the JS `messageformat` package.
final class MessageResolutionError extends MessageError {
  /// Creates a Resolution Error of the given [kind].
  MessageResolutionError(this.kind, super.message, {required this.source});

  /// Which Resolution Error this is.
  final ResolutionErrorKind kind;

  /// The fallback representation of the variable or expression that
  /// failed, such as `$x` or `:ns:func`, without the surrounding braces.
  final String source;

  @override
  String get type => kind.type;
}

/// A *Message Function Error*: calling a function handler failed, or the
/// value it returned could not be formatted or used for selection.
///
/// A function handler throws one to make its expression resolve to a
/// fallback value, or passes one to `MessageFunctionContext.onError` to
/// report a problem it recovers from. The named constructors create the
/// types the specification defines; the unnamed one takes an
/// implementation-defined [type]. It corresponds to `MessageFunctionError`
/// in the JS `messageformat` package.
final class MessageFunctionError extends MessageError {
  /// An error of an implementation-defined [type], such as
  /// `not-formattable`.
  MessageFunctionError(this.type, super.message, {this.source, this.cause});

  /// A *Bad Operand*: the operand's type, value, or format is not one the
  /// function supports.
  MessageFunctionError.badOperand(String message, {String? source})
      : this('bad-operand', message, source: source);

  /// A *Bad Option*: an option is missing, conflicts with another, or has a
  /// value the function does not support.
  MessageFunctionError.badOption(String message, {String? source})
      : this('bad-option', message, source: source);

  /// A *Bad Variant Key*: a variant key does not have the format the
  /// selector expects.
  MessageFunctionError.badVariantKey(String message, {String? source})
      : this('bad-variant-key', message, source: source);

  /// An *Unsupported Operation*: the function does not support this
  /// combination of operand and options.
  MessageFunctionError.unsupportedOperation(String message, {String? source})
      : this('unsupported-operation', message, source: source);

  /// The type of an error that formatting creates when a function handler
  /// or a value it returned throws something other than a
  /// [MessageFunctionError]. The thrown object is the [cause].
  static const functionErrorType = 'function-error';

  @override
  final String type;

  /// The fallback representation of the expression whose function failed,
  /// such as `|42|` or `$x`, when it is known.
  final String? source;

  /// What a function handler threw, when it was not a
  /// [MessageFunctionError].
  final Object? cause;
}
