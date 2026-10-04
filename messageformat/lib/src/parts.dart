import 'data_model.dart';
import 'message_value.dart';

/// A part of a message formatted by `MessageFormat.formatToParts`.
///
/// The [type] strings are those of the JS `messageformat` package, where
/// the parts are `MessagePart` objects.
sealed class MessagePart {
  const MessagePart();

  /// `text`, `bidiIsolation`, `markup`, `fallback`, or the type of an
  /// expression's [MessageValue].
  String get type;
}

/// Literal text from the pattern. JS: `MessageTextPart`.
final class MessageTextPart extends MessagePart {
  /// Creates a text part.
  const MessageTextPart(this.value);

  /// The text.
  final String value;

  @override
  String get type => 'text';

  @override
  bool operator ==(Object other) =>
      other is MessageTextPart && value == other.value;

  @override
  int get hashCode => Object.hash(MessageTextPart, value);

  @override
  String toString() => 'MessageTextPart($value)';
}

/// A bidi isolation control character that the Default Bidi Strategy
/// inserts around a placeholder: U+2066, U+2067, or U+2068 before it, and
/// U+2069 after it. JS: `MessageBiDiIsolationPart`.
final class MessageBidiIsolationPart extends MessagePart {
  /// Creates a part holding the isolate control [value].
  const MessageBidiIsolationPart(this.value);

  /// The control character.
  final String value;

  @override
  String get type => 'bidiIsolation';

  @override
  bool operator ==(Object other) =>
      other is MessageBidiIsolationPart && value == other.value;

  @override
  int get hashCode => Object.hash(MessageBidiIsolationPart, value);

  @override
  String toString() =>
      'MessageBidiIsolationPart(U+${value.codeUnitAt(0).toRadixString(16)})';
}

/// A markup placeholder, such as `{#b}`, `{/b}`, or `{#img/}`. It formats
/// to nothing in a string. JS: `MessageMarkupPart`.
final class MessageMarkupPart extends MessagePart {
  /// Creates a markup part.
  const MessageMarkupPart(
    this.kind,
    this.name, {
    this.options = const {},
    this.id,
  });

  /// Whether the markup opens, closes, or stands alone.
  final MarkupKind kind;

  /// The markup's identifier, including any namespace.
  final String name;

  /// The resolved options, with a [MessageValue] replaced by its
  /// [MessageValue.value]. The `u:` options are not included.
  final Map<String, Object?> options;

  /// The value of the `u:id` option, if any.
  final String? id;

  @override
  String get type => 'markup';

  @override
  bool operator ==(Object other) =>
      other is MessageMarkupPart &&
      kind == other.kind &&
      name == other.name &&
      id == other.id &&
      _mapEquals(options, other.options);

  @override
  int get hashCode => Object.hash(
        MessageMarkupPart,
        kind,
        name,
        id,
        Object.hashAllUnordered([
          for (final MapEntry(:key, :value) in options.entries)
            Object.hash(key, value),
        ]),
      );

  @override
  String toString() => 'MessageMarkupPart(${kind.name}, $name, $options'
      '${id == null ? '' : ', id: $id'})';
}

/// The fallback value of a placeholder that failed to resolve or to
/// format, which formats to a string as `{` [source] `}`.
/// JS: `MessageFallbackPart`.
final class MessageFallbackPart extends MessagePart {
  /// Creates a fallback part for the representation [source].
  const MessageFallbackPart(this.source);

  /// The fallback representation, such as `$x`, `|42|`, or `:ns:func`.
  final String source;

  @override
  String get type => 'fallback';

  @override
  bool operator ==(Object other) =>
      other is MessageFallbackPart && source == other.source;

  @override
  int get hashCode => Object.hash(MessageFallbackPart, source);

  @override
  String toString() => 'MessageFallbackPart($source)';
}

/// A formatted expression placeholder. JS: `MessageExpressionPart`.
final class MessageExpressionPart extends MessagePart {
  /// Creates an expression part.
  const MessageExpressionPart(
    this.type, {
    required this.source,
    required this.value,
    required this.dir,
    this.locale,
    this.id,
    this.parts,
  });

  /// The [MessageValue.type] of the resolved value, such as `string`.
  @override
  final String type;

  /// The expression's fallback representation, such as `$x` or `|42|`.
  final String source;

  /// The formatted value: the concatenation of [parts] when there are any.
  final String value;

  /// The directionality of the formatted value, which the expression's
  /// `u:dir` option sets when it is not `inherit`.
  final MessageDirection dir;

  /// The locale the value was formatted with, if the value reports one.
  final String? locale;

  /// The value of the `u:id` option, if any.
  final String? id;

  /// The parts of the formatted value, if its [MessageValue] provides them.
  final List<MessageValuePart>? parts;

  @override
  bool operator ==(Object other) =>
      other is MessageExpressionPart &&
      type == other.type &&
      source == other.source &&
      value == other.value &&
      dir == other.dir &&
      locale == other.locale &&
      id == other.id &&
      _listEquals(parts, other.parts);

  @override
  int get hashCode => Object.hash(MessageExpressionPart, type, source, value,
      dir, locale, id, parts == null ? null : Object.hashAll(parts!));

  @override
  String toString() => 'MessageExpressionPart($type, $value, '
      'source: $source, dir: ${dir.name}'
      '${locale == null ? '' : ', locale: $locale'}'
      '${id == null ? '' : ', id: $id'}'
      '${parts == null ? '' : ', parts: $parts'})';
}

bool _listEquals(List<Object?>? a, List<Object?>? b) {
  if (a == null || b == null) return a == b;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

bool _mapEquals(Map<String, Object?> a, Map<String, Object?> b) {
  if (a.length != b.length) return false;
  for (final MapEntry(:key, :value) in a.entries) {
    if (!b.containsKey(key) || b[key] != value) return false;
  }
  return true;
}
