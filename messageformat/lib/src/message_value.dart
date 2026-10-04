import 'errors.dart';
import 'parts.dart';

/// A text direction, used for a message's base direction and for the
/// directionality of a formatted value.
///
/// It corresponds to the `'ltr' | 'rtl' | 'auto'` strings of the JS
/// `messageformat` package.
enum MessageDirection {
  /// Left-to-right.
  ltr,

  /// Right-to-left.
  rtl,

  /// Determined from the content: the specification's `'unknown'`
  /// directionality. The Default Bidi Strategy isolates such a value with
  /// U+2068 FIRST STRONG ISOLATE.
  auto,
}

/// The resolved value of an expression whose function handler succeeded.
///
/// A [MessageFunction] returns one. Formatting calls [formatToString] or
/// [formatToParts] when the value is used in a placeholder, and passes the
/// value itself to another function handler when the value is used, through
/// a variable, as an operand or an option value.
///
/// A value that can be used as a selector extends [SelectableMessageValue].
///
/// This is the *resolved value* of the specification and corresponds to
/// `MessageValue` in the JS `messageformat` package.
abstract class MessageValue {
  /// Allows subclasses to be constant.
  const MessageValue();

  /// The kind of value, such as `string` or `number`, used as the type of
  /// its [MessageExpressionPart].
  String get type;

  /// The value that another function handler should work with, such as the
  /// number a `:number` value holds. It corresponds to `unwrap()` in the
  /// specification and `valueOf()` in the JS package.
  Object? get value;

  /// The options this value was resolved with, which a function handler
  /// given this value as its operand can take into account. It corresponds
  /// to `resolvedOptions()` in the specification and `options` in the JS
  /// package.
  Map<String, Object?> get options => const {};

  /// The directionality of the formatted value.
  ///
  /// The Default Bidi Strategy uses it to decide how to isolate the value.
  /// A `u:dir` option on the expression overrides it.
  MessageDirection get dir => MessageDirection.auto;

  /// The locale the value was formatted with, if any.
  String? get locale => null;

  /// The value formatted as a string.
  ///
  /// Throw a [MessageFunctionError] if the value cannot be formatted; the
  /// placeholder then formats as its fallback value.
  String formatToString();

  /// The value formatted as a sequence of parts, such as the integer and
  /// fraction of a number, or `null` to use [formatToString] as a single
  /// value.
  ///
  /// The parts are returned in the `parts` of the value's
  /// [MessageExpressionPart], whose `value` is their concatenation. Throw a
  /// [MessageFunctionError] if the value cannot be formatted.
  List<MessageValuePart>? formatToParts() => null;
}

/// A [MessageValue] that can be used as a selector.
///
/// *Pattern Selection* calls [match] and [betterThan] with keys that have
/// been normalized to NFC. If either throws, the selector reports a
/// *Bad Selector* error and matches only the catch-all key `*`.
abstract class SelectableMessageValue extends MessageValue {
  /// Allows subclasses to be constant.
  const SelectableMessageValue();

  /// Match(`rv`, [key]): whether [key] matches this value.
  bool match(String key);

  /// BetterThan(`rv`, [key1], [key2]): whether [key1] is a better match
  /// than [key2]. It is only called with two different keys that both
  /// [match].
  bool betterThan(String key1, String key2);
}

/// A part of a formatted [MessageValue], such as the `integer` part of a
/// number.
final class MessageValuePart {
  /// Creates a part of the given [type] with the formatted [value].
  const MessageValuePart(this.type, this.value);

  /// The kind of part, such as `integer`, `decimal`, or `fraction`.
  final String type;

  /// The formatted text of the part.
  final String value;

  @override
  bool operator ==(Object other) =>
      other is MessageValuePart && type == other.type && value == other.value;

  @override
  int get hashCode => Object.hash(MessageValuePart, type, value);

  @override
  String toString() => 'MessageValuePart($type, $value)';
}

/// A function handler: resolves an expression with a function, such as
/// `{$x :number}`, to a [MessageValue].
///
/// [options] maps each option name to its resolved value: the [String] of
/// a literal, the input value of an undeclared variable, or the resolved
/// value of a declared one, which is a [MessageValue] when that declaration
/// called a function. Options whose value failed to resolve are left out,
/// and the `u:dir` and `u:id` options are passed in [context] instead.
///
/// [operand] is the resolved value of the operand in the same forms, or
/// `null` when the expression has none. An operand that fails to resolve
/// never reaches the handler: formatting reports a *Bad Operand* error
/// itself.
///
/// Throw a [MessageFunctionError] to make the expression resolve to a
/// fallback value, and use [MessageFunctionContext.onError] to report an
/// error that the handler recovers from. Anything else thrown is reported
/// as a [MessageFunctionError] of type
/// [MessageFunctionError.functionErrorType].
///
/// This corresponds to `MessageFunction` in the JS `messageformat` package.
typedef MessageFunction = MessageValue Function(
  MessageFunctionContext context,
  Map<String, Object?> options,
  Object? operand,
);

/// What a [MessageFunction] knows about the expression it resolves: the
/// specification's *function context*.
///
/// It corresponds to `MessageFunctionContext` in the JS `messageformat`
/// package.
final class MessageFunctionContext {
  /// Creates a context. Formatting creates one for each function call; this
  /// constructor lets a function handler be called in tests.
  const MessageFunctionContext({
    required this.locales,
    required this.source,
    this.dir,
    this.id,
    this.literalOptionKeys = const {},
    void Function(MessageFunctionError error)? onError,
  }) : _onError = onError;

  /// The message's locales, most preferred first.
  final List<String> locales;

  /// The expression's fallback representation, such as `$x` or `|42|`.
  final String source;

  /// The base direction set by the expression's `u:dir` option, or `null`
  /// when it inherits the message's direction.
  final MessageDirection? dir;

  /// The value of the expression's `u:id` option, if any.
  final String? id;

  /// The names of the options whose value is a literal rather than a
  /// variable, for options that must be set with a literal.
  final Set<String> literalOptionKeys;

  final void Function(MessageFunctionError error)? _onError;

  /// Reports [error] without failing the expression.
  void onError(MessageFunctionError error) => _onError?.call(error);
}
