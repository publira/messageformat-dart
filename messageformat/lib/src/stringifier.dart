import 'characters.dart';
import 'data_model.dart';

/// Serializes [message] as MessageFormat 2.0 source.
///
/// The result parses back to a message equal to [message]. A message
/// without declarations or selectors is written as a simple message when
/// its pattern allows it, and otherwise as a quoted pattern. Literals are
/// written unquoted when they can be.
///
/// The serializer does not validate [message]: names that are not valid
/// MessageFormat names, or text and literals containing U+0000, produce
/// source that does not parse. Every message returned by `parseMessage` can
/// be serialized.
String stringifyMessage(Message message) {
  final buffer = StringBuffer();
  for (final declaration in message.declarations) {
    switch (declaration) {
      case InputDeclaration(:final value):
        buffer.write('.input ');
        _writeExpression(buffer, value);
      case LocalDeclaration(:final name, :final value):
        buffer.write('.local \$$name = ');
        _writeExpression(buffer, value);
    }
    buffer.write('\n');
  }

  switch (message) {
    case PatternMessage(:final pattern):
      if (message.declarations.isEmpty && _canBeSimple(pattern)) {
        _writePattern(buffer, pattern);
      } else {
        _writeQuotedPattern(buffer, pattern);
      }
    case SelectMessage(:final selectors, :final variants):
      buffer.write('.match');
      for (final selector in selectors) {
        buffer.write(' \$${selector.name}');
      }
      for (final variant in variants) {
        buffer.write('\n');
        for (final key in variant.keys) {
          switch (key) {
            case CatchallKey():
              buffer.write('*');
            case Literal():
              _writeLiteral(buffer, key);
          }
          buffer.write(' ');
        }
        _writeQuotedPattern(buffer, variant.value);
      }
  }
  return buffer.toString();
}

/// Whether [pattern] can be written as a simple message: its first
/// character other than whitespace and bidi marks must not be a `.`, which
/// would start a complex message.
bool _canBeSimple(List<PatternElement> pattern) {
  if (pattern.firstOrNull case TextElement(:final value)) {
    for (final unit in value.codeUnits) {
      if (isWhitespace(unit) || isBidi(unit)) continue;
      return unit != $period;
    }
  }
  return true;
}

void _writeQuotedPattern(StringBuffer buffer, List<PatternElement> pattern) {
  buffer.write('{{');
  _writePattern(buffer, pattern);
  buffer.write('}}');
}

void _writePattern(StringBuffer buffer, List<PatternElement> pattern) {
  for (final element in pattern) {
    switch (element) {
      case TextElement(:final value):
        _writeEscaped(buffer, value, const {$backslash, $lbrace, $rbrace});
      case Expression():
        _writeExpression(buffer, element);
      case Markup():
        _writeMarkup(buffer, element);
    }
  }
}

void _writeExpression(StringBuffer buffer, Expression expression) {
  buffer.write('{');
  var separate = false;
  switch (expression.arg) {
    case final Literal literal:
      _writeLiteral(buffer, literal);
      separate = true;
    case VariableRef(:final name):
      buffer.write('\$$name');
      separate = true;
    case null:
      break;
  }
  if (expression.function case FunctionRef(:final name, :final options)) {
    if (separate) buffer.write(' ');
    buffer.write(':$name');
    _writeOptions(buffer, options);
  }
  _writeAttributes(buffer, expression.attributes);
  buffer.write('}');
}

void _writeMarkup(StringBuffer buffer, Markup markup) {
  buffer
    ..write(markup.kind == MarkupKind.close ? '{/' : '{#')
    ..write(markup.name);
  _writeOptions(buffer, markup.options);
  _writeAttributes(buffer, markup.attributes);
  buffer.write(markup.kind == MarkupKind.standalone ? '/}' : '}');
}

void _writeOptions(StringBuffer buffer, Map<String, Operand> options) {
  for (final MapEntry(:key, :value) in options.entries) {
    buffer.write(' $key=');
    switch (value) {
      case Literal():
        _writeLiteral(buffer, value);
      case VariableRef(:final name):
        buffer.write('\$$name');
    }
  }
}

void _writeAttributes(StringBuffer buffer, Map<String, Literal?> attributes) {
  for (final MapEntry(:key, :value) in attributes.entries) {
    buffer.write(' @$key');
    if (value != null) {
      buffer.write('=');
      _writeLiteral(buffer, value);
    }
  }
}

void _writeLiteral(StringBuffer buffer, Literal literal) {
  final value = literal.value;
  if (value.isNotEmpty && value.runes.every(isNameChar)) {
    buffer.write(value);
  } else {
    buffer.write('|');
    _writeEscaped(buffer, value, const {$backslash, $pipe});
    buffer.write('|');
  }
}

void _writeEscaped(StringBuffer buffer, String text, Set<int> special) {
  for (final unit in text.codeUnits) {
    if (special.contains(unit)) buffer.write(r'\');
    buffer.writeCharCode(unit);
  }
}
