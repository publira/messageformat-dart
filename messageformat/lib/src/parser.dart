import 'characters.dart';
import 'data_model.dart';
import 'errors.dart';
import 'nfc.dart';
import 'validator.dart';

/// Parses MessageFormat 2.0 [source] into the data model.
///
/// A source that is not well-formed throws a [MessageSyntaxError] for the
/// first problem found; the specification defines no data model for it.
///
/// A well-formed source is then checked for Data Model Errors. Without
/// [onError], the first one is thrown as a [MessageDataModelError]. With
/// [onError], each one is passed to it instead and the message is returned,
/// even though it is not valid.
///
/// Every error carries the location of the offending source text.
Message parseMessage(
  String source, {
  void Function(MessageDataModelError error)? onError,
}) {
  final parser = _Parser(source);
  final message = parser.parse();
  final errors = [...parser.errors];
  validate(message, errors.add, spans: parser.spans);
  if (onError != null) {
    errors.forEach(onError);
  } else if (errors.isNotEmpty) {
    throw errors.first;
  }
  return message;
}

/// A recursive-descent parser over the ABNF of the specification.
///
/// Positions are UTF-16 code unit offsets. Characters that the grammar
/// restricts to scalar values, such as name characters, are read as code
/// points, so an unpaired surrogate never matches them. Text and quoted
/// literals accept any code unit other than the ones the grammar excludes,
/// which lets unpaired surrogates through as the specification allows.
final class _Parser {
  _Parser(this._source);

  final String _source;

  int _pos = 0;

  /// Data Model Errors that can only be found while parsing, because the
  /// data model cannot represent them: duplicate option names.
  final errors = <MessageDataModelError>[];

  /// The source spans of nodes that a Data Model Error can point to.
  final spans = Map<Object, (int, int)>.identity();

  Message parse() {
    _skipOptionalWhitespace();
    final complex = _peek() == $period || _lookingAt('{{');
    if (!complex) {
      // Leading whitespace is part of a simple message's text.
      _pos = 0;
      return PatternMessage(_parsePattern(quoted: false));
    }

    final declarations = <Declaration>[];
    while (true) {
      if (_lookingAt('.input')) {
        declarations.add(_parseInputDeclaration());
      } else if (_lookingAt('.local')) {
        declarations.add(_parseLocalDeclaration());
      } else {
        break;
      }
      _skipOptionalWhitespace();
    }

    final Message message;
    if (_lookingAt('.match')) {
      message = _parseMatcher(List.unmodifiable(declarations));
    } else if (_lookingAt('{{')) {
      message = PatternMessage(
        _parseQuotedPattern(),
        declarations: List.unmodifiable(declarations),
      );
    } else {
      throw _error('Expected .input, .local, .match, or a quoted pattern');
    }
    _skipOptionalWhitespace();
    if (_pos < _source.length) {
      throw _error('Unexpected text after the message');
    }
    return message;
  }

  // Declarations and matchers

  InputDeclaration _parseInputDeclaration() {
    final start = _pos;
    _pos += '.input'.length;
    _skipOptionalWhitespace();
    final expressionStart = _pos;
    final expression = _parseExpression();
    if (expression is! VariableExpression) {
      throw _error(
        'An .input declaration needs a variable operand',
        at: expressionStart,
      );
    }
    final declaration = InputDeclaration(expression);
    spans[declaration] = (start, _pos);
    return declaration;
  }

  LocalDeclaration _parseLocalDeclaration() {
    final start = _pos;
    _pos += '.local'.length;
    _requireWhitespace();
    if (_peek() != $dollar) throw _error('Expected a variable');
    final variable = _parseVariable();
    _skipOptionalWhitespace();
    _expect($equals, '=');
    _skipOptionalWhitespace();
    final declaration = LocalDeclaration(variable.name, _parseExpression());
    spans[declaration] = (start, _pos);
    return declaration;
  }

  SelectMessage _parseMatcher(List<Declaration> declarations) {
    final start = _pos;
    _pos += '.match'.length;
    final keywordEnd = _pos;
    final selectors = <VariableRef>[];
    while (true) {
      final before = _pos;
      if (!_skipWhitespace() || _peek() != $dollar) {
        _pos = before;
        break;
      }
      final selectorStart = _pos;
      final selector = _parseVariable();
      spans[selector] = (selectorStart, _pos);
      selectors.add(selector);
    }
    if (selectors.isEmpty) {
      _skipWhitespace();
      throw _error('Expected a selector');
    }
    _requireWhitespace();

    final variants = <Variant>[];
    do {
      variants.add(_parseVariant());
      _skipOptionalWhitespace();
    } while (_pos < _source.length);

    final message = SelectMessage(
      List.unmodifiable(selectors),
      List.unmodifiable(variants),
      declarations: declarations,
    );
    spans[message] = (start, keywordEnd);
    return message;
  }

  Variant _parseVariant() {
    final start = _pos;
    final keys = <VariantKey>[_parseKey()];
    while (true) {
      final separated = _skipOptionalWhitespace();
      if (_peek() == $lbrace) break;
      if (!separated) throw _error('Expected whitespace or a quoted pattern');
      keys.add(_parseKey());
    }
    final variant = Variant(List.unmodifiable(keys), _parseQuotedPattern());
    spans[variant] = (start, _pos);
    return variant;
  }

  VariantKey _parseKey() {
    if (_peek() != $asterisk) return _parseLiteral();
    _pos++;
    return const CatchallKey();
  }

  // Patterns

  List<PatternElement> _parseQuotedPattern() {
    if (!_lookingAt('{{')) throw _error('Expected a quoted pattern');
    _pos += 2;
    final pattern = _parsePattern(quoted: true);
    if (!_lookingAt('}}')) throw _error('Expected }} to end the pattern');
    _pos += 2;
    return pattern;
  }

  /// Parses a pattern up to the end of the source, or for a quoted pattern
  /// up to the first unescaped `}`.
  List<PatternElement> _parsePattern({required bool quoted}) {
    final elements = <PatternElement>[];
    final text = StringBuffer();
    void flushText() {
      if (text.isEmpty) return;
      elements.add(TextElement(text.toString()));
      text.clear();
    }

    while (_pos < _source.length) {
      final unit = _source.codeUnitAt(_pos);
      if (unit == $backslash) {
        text.writeCharCode(_parseEscape());
      } else if (unit == $lbrace) {
        flushText();
        elements.add(_parsePlaceholder());
      } else if (unit == $rbrace) {
        if (quoted) break;
        throw _error('Unescaped } in text');
      } else if (unit == 0) {
        throw _error('NULL is not allowed in text');
      } else {
        text.writeCharCode(unit);
        _pos++;
      }
    }
    if (quoted && _pos >= _source.length) {
      throw _error('Expected }} to end the pattern');
    }
    flushText();
    return List.unmodifiable(elements);
  }

  int _parseEscape() {
    _pos++;
    final unit = _peek();
    if (unit != $backslash &&
        unit != $lbrace &&
        unit != $pipe &&
        unit != $rbrace) {
      throw _error(r'Only \\, \{, \|, and \} are escape sequences');
    }
    _pos++;
    return unit;
  }

  // Expressions and markup

  /// Parses an expression or markup.
  PatternElement _parsePlaceholder() {
    final start = _pos;
    _pos++;
    _skipOptionalWhitespace();
    final sigil = _peek();
    if (sigil == $hash || sigil == $slash) return _parseMarkup();
    _pos = start;
    return _parseExpression();
  }

  /// Parses an expression; markup is a syntax error here.
  Expression _parseExpression() {
    _expect($lbrace, '{');
    _skipOptionalWhitespace();
    final Operand? arg;
    final unit = _peek();
    if (unit == $dollar) {
      arg = _parseVariable();
    } else if (unit == $pipe || isNameChar(_codePointAt(_pos))) {
      arg = _parseLiteral();
    } else if (unit == $colon) {
      arg = null;
    } else if (unit == $hash || unit == $slash) {
      throw _error('Markup is not allowed in a declaration');
    } else {
      throw _error('Expected a literal, a variable, or a function');
    }

    FunctionRef? function;
    if (arg == null) {
      function = _parseFunction();
    } else {
      final before = _pos;
      if (_skipWhitespace() && _peek() == $colon) {
        function = _parseFunction();
      } else {
        _pos = before;
      }
    }
    final attributes = _parseAttributes();
    _skipOptionalWhitespace();
    _expect($rbrace, '}');

    return switch (arg) {
      null => FunctionExpression(function!, attributes: attributes),
      final Literal literal =>
        LiteralExpression(literal, function: function, attributes: attributes),
      final VariableRef variable => VariableExpression(variable,
          function: function, attributes: attributes),
    };
  }

  FunctionRef _parseFunction() {
    _pos++; // :
    final name = _parseIdentifier();
    return FunctionRef(name, options: _parseOptions());
  }

  Markup _parseMarkup() {
    final open = _peek() == $hash;
    _pos++;
    final name = _parseIdentifier();
    final options = _parseOptions();
    final attributes = _parseAttributes();
    _skipOptionalWhitespace();
    var kind = open ? MarkupKind.open : MarkupKind.close;
    if (open && _peek() == $slash) {
      _pos++;
      kind = MarkupKind.standalone;
    }
    _expect($rbrace, '}');
    return Markup(kind, name, options: options, attributes: attributes);
  }

  Map<String, Operand> _parseOptions() {
    final options = <String, Operand>{};
    final seen = <String>{};
    while (true) {
      final before = _pos;
      if (!_skipWhitespace() || !isNameStart(_codePointAt(_pos))) {
        _pos = before;
        break;
      }
      final start = _pos;
      final name = _parseIdentifier();
      _skipOptionalWhitespace();
      _expect($equals, '=');
      _skipOptionalWhitespace();
      final value = _peek() == $dollar ? _parseVariable() : _parseLiteral();
      if (seen.add(toNfc(name))) {
        options[name] = value;
      } else {
        errors.add(MessageDataModelError(
          DataModelErrorKind.duplicateOptionName,
          'The option $name is already set',
          start: start,
          end: _pos,
        ));
      }
    }
    return Map.unmodifiable(options);
  }

  Map<String, Literal?> _parseAttributes() {
    final attributes = <String, Literal?>{};
    while (true) {
      final before = _pos;
      if (!_skipWhitespace() || _peek() != $at) {
        _pos = before;
        break;
      }
      _pos++;
      final name = _parseIdentifier();
      final afterName = _pos;
      _skipOptionalWhitespace();
      if (_peek() == $equals) {
        _pos++;
        _skipOptionalWhitespace();
        // Only the last of several attributes with the same name counts.
        attributes[name] = _parseLiteral();
      } else {
        _pos = afterName;
        attributes[name] = null;
      }
    }
    return Map.unmodifiable(attributes);
  }

  // Literals, variables, and names

  Literal _parseLiteral() {
    if (_peek() == $pipe) {
      _pos++;
      final value = StringBuffer();
      while (true) {
        final unit = _peek();
        if (unit == $pipe) break;
        if (unit == $backslash) {
          value.writeCharCode(_parseEscape());
        } else if (unit == -1) {
          throw _error('Expected | to end the literal');
        } else if (unit == 0) {
          throw _error('NULL is not allowed in a literal');
        } else {
          value.writeCharCode(unit);
          _pos++;
        }
      }
      _pos++;
      return Literal(value.toString());
    }

    final start = _pos;
    while (isNameChar(_codePointAt(_pos))) {
      _advanceCodePoint();
    }
    if (_pos == start) throw _error('Expected a literal');
    return Literal(_source.substring(start, _pos));
  }

  VariableRef _parseVariable() {
    _pos++; // $
    return VariableRef(_parseName());
  }

  String _parseIdentifier() {
    final name = _parseName();
    if (_peek() != $colon) return name;
    _pos++;
    return '$name:${_parseName()}';
  }

  /// Parses a name. A bidi mark before or after it is not part of its value.
  String _parseName() {
    if (isBidi(_peek())) _pos++;
    final start = _pos;
    if (!isNameStart(_codePointAt(_pos))) throw _error('Expected a name');
    _advanceCodePoint();
    while (isNameChar(_codePointAt(_pos))) {
      _advanceCodePoint();
    }
    final name = _source.substring(start, _pos);
    if (isBidi(_peek())) _pos++;
    return name;
  }

  // Whitespace

  /// Skips the production `o`, returning whether it contained whitespace
  /// other than bidi marks.
  bool _skipOptionalWhitespace() {
    var whitespace = false;
    while (true) {
      final unit = _peek();
      if (isWhitespace(unit)) {
        whitespace = true;
      } else if (!isBidi(unit)) {
        return whitespace;
      }
      _pos++;
    }
  }

  /// Skips the production `s` if it is present, returning whether it was.
  ///
  /// `s` is any run of whitespace and bidi marks with at least one
  /// whitespace character. When it is absent, nothing is skipped.
  bool _skipWhitespace() {
    final before = _pos;
    if (_skipOptionalWhitespace()) return true;
    _pos = before;
    return false;
  }

  void _requireWhitespace() {
    if (!_skipWhitespace()) throw _error('Expected whitespace');
  }

  // Low-level helpers

  /// The code unit at the current position, or -1 at the end.
  int _peek() => _pos < _source.length ? _source.codeUnitAt(_pos) : -1;

  bool _lookingAt(String text) => _source.startsWith(text, _pos);

  /// The code point at [index], or -1 at the end. An unpaired surrogate is
  /// returned as is.
  int _codePointAt(int index) {
    if (index >= _source.length) return -1;
    final unit = _source.codeUnitAt(index);
    if (isHighSurrogate(unit) && index + 1 < _source.length) {
      final next = _source.codeUnitAt(index + 1);
      if (isLowSurrogate(next)) return combineSurrogates(unit, next);
    }
    return unit;
  }

  void _advanceCodePoint() {
    _pos += _codePointAt(_pos) > 0xffff ? 2 : 1;
  }

  void _expect(int unit, String text) {
    if (_peek() != unit) throw _error('Expected $text');
    _pos++;
  }

  MessageSyntaxError _error(String message, {int? at}) {
    final start = at ?? _pos;
    final end = start < _source.length
        ? start + (_codePointAt(start) > 0xffff ? 2 : 1)
        : start;
    return MessageSyntaxError(message, start: start, end: end);
  }
}
