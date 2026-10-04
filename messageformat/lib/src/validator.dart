import 'data_model.dart';
import 'errors.dart';
import 'nfc.dart';

/// Checks [message] for Data Model Errors.
///
/// Without [onError], the first error is thrown as a
/// [MessageDataModelError]. With [onError], each error is passed to it.
///
/// A data model built in code has no source, so the errors carry no
/// location. Duplicate option names cannot occur in the data model, whose
/// options are a map; `parseMessage` reports those from the source.
void validateMessage(
  Message message, {
  void Function(MessageDataModelError error)? onError,
}) {
  validate(message, onError ?? (error) => throw error);
}

/// Reports every Data Model Error in [message] to [onError], locating each
/// with [spans] when the message was parsed.
void validate(
  Message message,
  void Function(MessageDataModelError error) onError, {
  Map<Object, (int, int)> spans = const {},
}) {
  void report(DataModelErrorKind kind, String text, Object node) {
    final span = spans[node];
    onError(MessageDataModelError(kind, text, start: span?.$1, end: span?.$2));
  }

  final declarations = message.declarations;
  _checkDeclarations(declarations, report);

  if (message case SelectMessage(:final selectors, :final variants)) {
    for (final selector in selectors) {
      if (!_isAnnotated(selector.name, declarations)) {
        report(
          DataModelErrorKind.missingSelectorAnnotation,
          'The selector \$${selector.name} does not reference a declaration '
          'with a function',
          selector,
        );
      }
    }

    var hasFallback = false;
    final keyLists = <String>{};
    for (final variant in variants) {
      if (variant.keys.length != selectors.length) {
        report(
          DataModelErrorKind.variantKeyMismatch,
          'The variant has ${variant.keys.length} keys '
          'but there are ${selectors.length} selectors',
          variant,
        );
      }
      if (variant.keys.every((key) => key is CatchallKey)) hasFallback = true;
      if (!keyLists.add(_keyListId(variant.keys))) {
        report(
          DataModelErrorKind.duplicateVariant,
          'Another variant has the same keys',
          variant,
        );
      }
    }
    if (!hasFallback) {
      report(
        DataModelErrorKind.missingFallbackVariant,
        'No variant has only catch-all keys',
        message,
      );
    }
  }
}

/// Reports each declaration that binds a variable which an earlier
/// declaration, or its own expression, already uses.
void _checkDeclarations(
  List<Declaration> declarations,
  void Function(DataModelErrorKind, String, Object) report,
) {
  final used = <String>{};
  for (final declaration in declarations) {
    final name = toNfc(declaration.name);
    final value = declaration.value;
    final optionVariables = {
      for (final option in value.function?.options.values ?? const <Operand>[])
        if (option is VariableRef) toNfc(option.name),
    };
    final ownVariables = {
      ...optionVariables,
      if (value.arg case VariableRef(name: final argName)) toNfc(argName),
    };
    // An input declaration's operand is the variable it declares.
    final selfReference = switch (declaration) {
      InputDeclaration() => optionVariables.contains(name),
      LocalDeclaration() => ownVariables.contains(name),
    };
    if (used.contains(name) || selfReference) {
      report(
        DataModelErrorKind.duplicateDeclaration,
        'The variable \$${declaration.name} is already declared or used',
        declaration,
      );
    }
    used
      ..add(name)
      ..addAll(ownVariables);
  }
}

/// Whether the variable [name] is bound, directly or through other local
/// variables, to an expression with a function.
bool _isAnnotated(String name, List<Declaration> declarations) {
  var target = toNfc(name);
  // Each step looks only at declarations before the previous one, so a
  // malformed chain cannot loop.
  var end = declarations.length;
  while (true) {
    final index = declarations.lastIndexWhere(
      (declaration) => toNfc(declaration.name) == target,
      end - 1,
    );
    if (index < 0) return false;
    final declaration = declarations[index];
    if (declaration.value.function != null) return true;
    if (declaration is! LocalDeclaration) return false;
    final arg = declaration.value.arg;
    if (arg is! VariableRef) return false;
    target = toNfc(arg.name);
    end = index;
  }
}

/// A string that is equal for two key lists exactly when the specification
/// considers them the same: literals compare by their NFC value, and the
/// catch-all key differs from the literal `*`.
String _keyListId(List<VariantKey> keys) => [
      for (final key in keys)
        switch (key) {
          CatchallKey() => '*',
          Literal(:final value) => _literalId(toNfc(value)),
        },
    ].join(',');

String _literalId(String value) => '${value.length}|$value';
