/// An error defined by the MessageFormat 2.0 specification.
///
/// [type] is the error's name in the conformance suite, such as
/// `syntax-error` or `duplicate-declaration`. When the error comes from
/// message source, [start] and [end] locate the offending text as UTF-16
/// code unit offsets into that source.
abstract class MessageError implements Exception {
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
  MessageDataModelError(this.kind, super.message, {super.start, super.end});

  final DataModelErrorKind kind;

  @override
  String get type => kind.type;
}
