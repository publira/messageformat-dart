/// The *Interchange Data Model* of MessageFormat 2.0, under Dart naming.
///
/// Each type mirrors an interface of the specification's data model. The
/// specification's `type` discriminators become Dart subtypes, and the union
/// `string | Expression | Markup` of a pattern becomes [PatternElement].
///
/// Instances are immutable values with structural equality. Constructors do
/// not copy the lists and maps they are given, so callers must not modify
/// them afterwards; the parser passes unmodifiable collections.
library;

/// A message: a [PatternMessage] or a [SelectMessage].
sealed class Message {
  const Message(this.declarations);

  /// The message's `.input` and `.local` declarations, in source order.
  final List<Declaration> declarations;
}

/// A message without selectors, consisting of a single [pattern].
final class PatternMessage extends Message {
  const PatternMessage(this.pattern,
      {List<Declaration> declarations = const []})
      : super(declarations);

  final List<PatternElement> pattern;

  @override
  bool operator ==(Object other) =>
      other is PatternMessage &&
      _listEquals(declarations, other.declarations) &&
      _listEquals(pattern, other.pattern);

  @override
  int get hashCode => Object.hash(
      PatternMessage, Object.hashAll(declarations), Object.hashAll(pattern));

  @override
  String toString() => 'PatternMessage($declarations, $pattern)';
}

/// A message with a `.match` statement.
final class SelectMessage extends Message {
  const SelectMessage(
    this.selectors,
    this.variants, {
    List<Declaration> declarations = const [],
  }) : super(declarations);

  /// The variables the message selects on.
  final List<VariableRef> selectors;

  final List<Variant> variants;

  @override
  bool operator ==(Object other) =>
      other is SelectMessage &&
      _listEquals(declarations, other.declarations) &&
      _listEquals(selectors, other.selectors) &&
      _listEquals(variants, other.variants);

  @override
  int get hashCode => Object.hash(SelectMessage, Object.hashAll(declarations),
      Object.hashAll(selectors), Object.hashAll(variants));

  @override
  String toString() => 'SelectMessage($declarations, $selectors, $variants)';
}

/// A declaration: an [InputDeclaration] or a [LocalDeclaration].
sealed class Declaration {
  const Declaration();

  /// The name of the declared variable, without the `$` sigil.
  String get name;

  /// The expression whose value the variable is bound to.
  Expression get value;
}

/// An `.input` declaration, which binds the external variable named by its
/// expression's operand.
final class InputDeclaration extends Declaration {
  const InputDeclaration(this.value);

  @override
  final VariableExpression value;

  @override
  String get name => value.arg.name;

  @override
  bool operator ==(Object other) =>
      other is InputDeclaration && value == other.value;

  @override
  int get hashCode => Object.hash(InputDeclaration, value);

  @override
  String toString() => 'InputDeclaration($value)';
}

/// A `.local` declaration.
final class LocalDeclaration extends Declaration {
  const LocalDeclaration(this.name, this.value);

  @override
  final String name;

  @override
  final Expression value;

  @override
  bool operator ==(Object other) =>
      other is LocalDeclaration && name == other.name && value == other.value;

  @override
  int get hashCode => Object.hash(LocalDeclaration, name, value);

  @override
  String toString() => 'LocalDeclaration(\$$name, $value)';
}

/// One variant of a [SelectMessage]: a list of keys and the pattern used
/// when they match.
final class Variant {
  const Variant(this.keys, this.value);

  final List<VariantKey> keys;

  final List<PatternElement> value;

  @override
  bool operator ==(Object other) =>
      other is Variant &&
      _listEquals(keys, other.keys) &&
      _listEquals(value, other.value);

  @override
  int get hashCode =>
      Object.hash(Variant, Object.hashAll(keys), Object.hashAll(value));

  @override
  String toString() => 'Variant($keys, $value)';
}

/// A variant key: a [Literal] or a [CatchallKey].
sealed class VariantKey {}

/// The catch-all key `*`, which matches any value.
final class CatchallKey implements VariantKey {
  const CatchallKey([this.value]);

  /// An identifier retained from another format. The MessageFormat syntax
  /// always writes `*`, and the parser leaves this `null`.
  final String? value;

  @override
  bool operator ==(Object other) =>
      other is CatchallKey && value == other.value;

  @override
  int get hashCode => Object.hash(CatchallKey, value);

  @override
  String toString() => value == null ? '*' : 'CatchallKey($value)';
}

/// An element of a pattern: a [TextElement], an [Expression], or a [Markup].
sealed class PatternElement {
  const PatternElement();
}

/// Literal text in a pattern, with escape sequences already processed.
final class TextElement extends PatternElement {
  const TextElement(this.value);

  /// The text. The parser never produces an empty value.
  final String value;

  @override
  bool operator ==(Object other) =>
      other is TextElement && value == other.value;

  @override
  int get hashCode => Object.hash(TextElement, value);

  @override
  String toString() => 'TextElement(${_quote(value)})';
}

/// An expression: a [LiteralExpression], a [VariableExpression], or a
/// [FunctionExpression].
sealed class Expression extends PatternElement {
  const Expression({this.attributes = const {}});

  /// The operand, or `null` for a [FunctionExpression].
  Operand? get arg;

  /// The function applied to [arg], or `null` when there is none.
  FunctionRef? get function;

  /// The attributes, keyed by identifier. An attribute without a value maps
  /// to `null`.
  final Map<String, Literal?> attributes;

  @override
  bool operator ==(Object other) =>
      other is Expression &&
      other.runtimeType == runtimeType &&
      arg == other.arg &&
      function == other.function &&
      _mapEquals(attributes, other.attributes);

  @override
  int get hashCode =>
      Object.hash(runtimeType, arg, function, _hashMap(attributes));

  @override
  String toString() => '$runtimeType($arg, $function, $attributes)';
}

/// An expression whose operand is a literal, such as `{|a| :string}`.
final class LiteralExpression extends Expression {
  const LiteralExpression(this.arg, {this.function, super.attributes});

  @override
  final Literal arg;

  @override
  final FunctionRef? function;
}

/// An expression whose operand is a variable, such as `{$x :number}`.
final class VariableExpression extends Expression {
  const VariableExpression(this.arg, {this.function, super.attributes});

  @override
  final VariableRef arg;

  @override
  final FunctionRef? function;
}

/// An expression without an operand, such as `{:f}`.
final class FunctionExpression extends Expression {
  const FunctionExpression(this.function, {super.attributes});

  @override
  Operand? get arg => null;

  @override
  final FunctionRef function;
}

/// An operand or option value: a [Literal] or a [VariableRef].
sealed class Operand {}

/// A quoted or unquoted literal. The data model does not record which.
final class Literal implements Operand, VariantKey {
  const Literal(this.value);

  /// The literal's value, with escape sequences already processed.
  final String value;

  @override
  bool operator ==(Object other) => other is Literal && value == other.value;

  @override
  int get hashCode => Object.hash(Literal, value);

  @override
  String toString() => '|$value|';
}

/// A reference to a variable.
final class VariableRef implements Operand {
  const VariableRef(this.name);

  /// The variable's name, without the `$` sigil.
  final String name;

  @override
  bool operator ==(Object other) => other is VariableRef && name == other.name;

  @override
  int get hashCode => Object.hash(VariableRef, name);

  @override
  String toString() => '\$$name';
}

/// A function annotation, such as `:number minimumFractionDigits=2`.
final class FunctionRef {
  const FunctionRef(this.name, {this.options = const {}});

  /// The function's identifier, including any namespace, without the `:`
  /// sigil.
  final String name;

  /// The options, keyed by identifier.
  final Map<String, Operand> options;

  @override
  bool operator ==(Object other) =>
      other is FunctionRef &&
      name == other.name &&
      _mapEquals(options, other.options);

  @override
  int get hashCode => Object.hash(FunctionRef, name, _hashMap(options));

  @override
  String toString() => ':$name $options';
}

/// The kind of a [Markup] placeholder.
enum MarkupKind {
  /// `{#name}`
  open,

  /// `{#name/}`
  standalone,

  /// `{/name}`
  close,
}

/// A markup placeholder, such as `{#b}`, `{#img/}`, or `{/b}`.
final class Markup extends PatternElement {
  const Markup(
    this.kind,
    this.name, {
    this.options = const {},
    this.attributes = const {},
  });

  final MarkupKind kind;

  /// The markup's identifier, without the `#`, `/`, or trailing `/` sigils.
  final String name;

  /// The options, keyed by identifier.
  final Map<String, Operand> options;

  /// The attributes, keyed by identifier. An attribute without a value maps
  /// to `null`.
  final Map<String, Literal?> attributes;

  @override
  bool operator ==(Object other) =>
      other is Markup &&
      kind == other.kind &&
      name == other.name &&
      _mapEquals(options, other.options) &&
      _mapEquals(attributes, other.attributes);

  @override
  int get hashCode =>
      Object.hash(Markup, kind, name, _hashMap(options), _hashMap(attributes));

  @override
  String toString() => 'Markup(${kind.name}, $name, $options, $attributes)';
}

bool _listEquals(List<Object?> a, List<Object?> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Compares maps by their entries, ignoring order, as the data model's
/// mappings are unordered.
bool _mapEquals(Map<String, Object?> a, Map<String, Object?> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (final MapEntry(:key, :value) in a.entries) {
    if (!b.containsKey(key) || b[key] != value) return false;
  }
  return true;
}

int _hashMap(Map<String, Object?> map) => Object.hashAllUnordered([
      for (final MapEntry(:key, :value) in map.entries) Object.hash(key, value)
    ]);

String _quote(String text) => "'${text.replaceAll("'", r"\'")}'";
