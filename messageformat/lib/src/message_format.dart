import 'data_model.dart';
import 'errors.dart';
import 'locale_direction.dart';
import 'message_value.dart';
import 'nfc.dart';
import 'parser.dart';
import 'parts.dart';
import 'validator.dart';

/// How formatting isolates placeholders from the surrounding text.
///
/// It corresponds to the `bidiIsolation` option of the JS `messageformat`
/// package, whose `'default'` is [defaultStrategy] here.
enum BidiIsolation {
  /// The specification's *Default Bidi Strategy*, which wraps placeholders
  /// in Unicode isolate controls (U+2066 to U+2069) unless they share the
  /// message's left-to-right direction. The specification requires it as
  /// the default when formatting to a string.
  defaultStrategy,

  /// No isolation: placeholders are formatted as they are, and
  /// `formatToParts` returns no [MessageBidiIsolationPart].
  none,
}

/// Options for a [MessageFormat]. JS: `MessageFormatOptions`.
final class MessageFormatOptions {
  /// Creates options; each one left out has its default.
  const MessageFormatOptions({
    this.bidiIsolation = BidiIsolation.defaultStrategy,
    this.dir,
    this.functions = const {},
  });

  /// The bidirectional isolation strategy.
  final BidiIsolation bidiIsolation;

  /// The base direction of the message. When `null`, it is the direction of
  /// the first locale. [MessageDirection.auto] makes it unknown, so that
  /// every placeholder is isolated.
  final MessageDirection? dir;

  /// Custom functions by identifier, without the `:` sigil and including any
  /// namespace, such as `ns:upper`. They are added to the default
  /// functions, and replace a default function of the same name.
  final Map<String, MessageFunction> functions;
}

/// The default functions that every [MessageFormat] has, by identifier.
///
/// The default functions of the specification are added by #6 and #7.
const Map<String, MessageFunction> _defaultFunctions = {};

/// A MessageFormat 2.0 message, ready to be formatted.
///
/// ```dart
/// final mf = MessageFormat('en', r'Hello, {$name}!');
/// mf.format({'name': 'World'}); // 'Hello, \u2068World\u2069!'
/// mf.format(); // 'Hello, \u2068{$name}\u2069!'
/// ```
///
/// A message is parsed and checked once, when it is created. Formatting
/// then never throws for a problem in the message or its inputs: it reports
/// each *Resolution Error* and *Message Function Error* to `onError` and
/// still returns a result, in which a placeholder that failed is replaced by
/// its fallback value, such as `{$name}`. Without `onError`, those errors
/// are ignored.
///
/// This corresponds to `MessageFormat` in the JS `messageformat` package and
/// to the TC39 `Intl.MessageFormat` proposal.
final class MessageFormat {
  /// Parses [source] as a message to format for [locales].
  ///
  /// [locales] is a BCP 47 language tag, a list of them in order of
  /// preference, or `null` for the root locale `und`.
  ///
  /// Throws a [MessageSyntaxError] if [source] is not well-formed, and a
  /// [MessageDataModelError] if it is not valid.
  MessageFormat(Object? locales, String source, {MessageFormatOptions? options})
      : this._(_localeList(locales), parseMessage(source), options);

  /// Creates a formatter for a [message] built in code, which corresponds
  /// to passing a data model object to the JS constructor.
  ///
  /// Throws a [MessageDataModelError] if [message] is not valid.
  MessageFormat.fromMessage(Object? locales, Message message,
      {MessageFormatOptions? options})
      : this._(_localeList(locales), _validated(message), options);

  MessageFormat._(
    this._locales,
    this._message,
    MessageFormatOptions? options,
  )   : _bidiIsolation =
            options?.bidiIsolation ?? BidiIsolation.defaultStrategy,
        _dir = options?.dir ?? localeDirection(_locales.first),
        _functions = {
          for (final MapEntry(:key, :value) in {
            ..._defaultFunctions,
            ...?options?.functions,
          }.entries)
            toNfc(key): value,
        };

  final List<String> _locales;
  final Message _message;
  final BidiIsolation _bidiIsolation;
  final MessageDirection _dir;
  final Map<String, MessageFunction> _functions;

  /// Formats the message to a string with the values in [params], the
  /// specification's *input mapping*, keyed by variable name.
  ///
  /// Markup formats to an empty string. Each error is passed to [onError]
  /// if given; see [MessageFormat] for how errors are handled.
  String format([
    Map<String, Object?>? params,
    void Function(MessageError error)? onError,
  ]) {
    final buffer = StringBuffer();
    final formatter = _Formatter(this, params, onError);
    for (final item in formatter.resolvePattern()) {
      switch (item) {
        case _TextItem(:final text):
          buffer.write(text);
        case _MarkupItem():
          break;
        case _ExpressionItem(:final resolved, :final source):
          final (text, dir, isolate) = switch (resolved) {
            _Fallback() => ('{$source}', MessageDirection.auto, false),
            _Value() => formatter.formatValue(resolved, source),
          };
          switch (_isolation(dir, isolate)) {
            case final start?:
              buffer
                ..write(start)
                ..write(text)
                ..write(_pdi);
            case null:
              buffer.write(text);
          }
      }
    }
    return buffer.toString();
  }

  /// Formats the message to a list of parts, with the same [params] and
  /// [onError] as [format].
  ///
  /// Markup becomes a [MessageMarkupPart], and the Default Bidi Strategy
  /// adds a [MessageBidiIsolationPart] before and after each placeholder it
  /// isolates.
  List<MessagePart> formatToParts([
    Map<String, Object?>? params,
    void Function(MessageError error)? onError,
  ]) {
    final parts = <MessagePart>[];
    final formatter = _Formatter(this, params, onError);
    for (final item in formatter.resolvePattern()) {
      switch (item) {
        case _TextItem(:final text):
          parts.add(MessageTextPart(text));
        case _MarkupItem(:final part):
          parts.add(part);
        case _ExpressionItem(:final resolved, :final source):
          final (part, dir, isolate) = switch (resolved) {
            _Fallback() => (
                MessageFallbackPart(source),
                MessageDirection.auto,
                false
              ),
            _Value() => formatter.formatValueToPart(resolved, source),
          };
          switch (_isolation(dir, isolate)) {
            case final start?:
              parts
                ..add(MessageBidiIsolationPart(start))
                ..add(part)
                ..add(const MessageBidiIsolationPart(_pdi));
            case null:
              parts.add(part);
          }
      }
    }
    return parts;
  }

  /// The isolate control that the bidi strategy puts before a placeholder
  /// with direction [dir], or `null` when it is not isolated.
  ///
  /// [isolate] is whether the placeholder has a `u:dir` other than
  /// `inherit`.
  String? _isolation(MessageDirection dir, bool isolate) {
    if (_bidiIsolation == BidiIsolation.none) return null;
    return switch (dir) {
      MessageDirection.ltr =>
        _dir == MessageDirection.ltr && !isolate ? null : _lri,
      MessageDirection.rtl => _rli,
      MessageDirection.auto => _fsi,
    };
  }

  static Message _validated(Message message) {
    validateMessage(message);
    return message;
  }

  static List<String> _localeList(Object? locales) {
    final list = switch (locales) {
      null => const <String>[],
      final String locale => [locale],
      final Iterable<Object?> list => [
          for (final locale in list)
            locale is String
                ? locale
                : throw ArgumentError.value(
                    locales, 'locales', 'Must contain only strings'),
        ],
      _ => throw ArgumentError.value(
          locales, 'locales', 'Must be a string, a list of strings, or null'),
    };
    return List.unmodifiable(list.isEmpty ? const ['und'] : list);
  }
}

const _lri = '\u2066';
const _rli = '\u2067';
const _fsi = '\u2068';
const _pdi = '\u2069';

/// The resolved value of a variable or an expression.
sealed class _Resolved {
  const _Resolved();
}

/// A *fallback value*.
final class _Fallback extends _Resolved {
  const _Fallback();
}

/// A resolved value that is not a fallback value.
final class _Value extends _Resolved {
  const _Value(this.value, {this.dir, this.id});

  /// A literal's [String], an input value, or a [MessageValue].
  final Object value;

  /// The direction set by `u:dir`, or `null` for `inherit`.
  final MessageDirection? dir;

  /// The value of `u:id`.
  final String? id;
}

/// An element of the selected pattern, resolved.
sealed class _Item {}

final class _TextItem extends _Item {
  _TextItem(this.text);

  final String text;
}

final class _MarkupItem extends _Item {
  _MarkupItem(this.part);

  final MessageMarkupPart part;
}

final class _ExpressionItem extends _Item {
  _ExpressionItem(this.resolved, this.source);

  final _Resolved resolved;

  /// The fallback representation of the placeholder.
  final String source;
}

/// One formatting of a message: the input mapping, the error callback, and
/// the values of the declarations resolved so far.
final class _Formatter {
  _Formatter(this._format, this._params, this._onError) {
    for (final declaration in _format._message.declarations) {
      _declarations[toNfc(declaration.name)] = declaration;
    }
  }

  final MessageFormat _format;
  final Map<String, Object?>? _params;
  final void Function(MessageError error)? _onError;

  /// The declarations by NFC name. A valid message declares each name once.
  final _declarations = <String, Declaration>{};

  /// The resolved values of the declarations evaluated so far, so that each
  /// is evaluated at most once.
  final _declared = <String, _Resolved>{};

  void _report(MessageError error) => _onError?.call(error);

  /// Selects the pattern and resolves each of its elements, in order.
  Iterable<_Item> resolvePattern() sync* {
    final pattern = switch (_format._message) {
      PatternMessage(:final pattern) => pattern,
      final SelectMessage message => _select(message),
    };
    for (final element in pattern) {
      yield switch (element) {
        TextElement(:final value) => _TextItem(value),
        Markup() => _MarkupItem(_resolveMarkup(element)),
        Expression() =>
          _ExpressionItem(_resolveExpression(element), _source(element)),
      };
    }
  }

  // Pattern Selection

  List<PatternElement> _select(SelectMessage message) {
    final selectors = [
      for (final selector in message.selectors) _resolveSelector(selector),
    ];
    // A selector that fails while comparing must match only `*`, which
    // can change variants already compared, so compare again until no
    // selector fails. Each failure is final, which bounds the passes.
    while (true) {
      final failures = selectors.where((s) => s.failed).length;
      final best = _compareVariants(message.variants, selectors);
      if (selectors.where((s) => s.failed).length == failures) {
        return best.value;
      }
    }
  }

  /// *Resolve Selectors* for one selector.
  _Selector _resolveSelector(VariableRef selector) {
    final resolved = _resolveVariable(selector.name);
    final selectable = switch (resolved) {
      _Value(value: final SelectableMessageValue value) => value,
      _ => null,
    };
    final result = _Selector(this, selectable, '\$${selector.name}');
    if (selectable == null) result.fail();
    return result;
  }

  /// *Compare Variants*.
  Variant _compareVariants(List<Variant> variants, List<_Selector> selectors) {
    Variant? best;
    for (final variant in variants) {
      if (!_selectorsMatch(selectors, variant.keys)) continue;
      if (best == null ||
          _selectorsCompare(selectors, variant.keys, best.keys)) {
        best = variant;
      }
    }
    // A valid message has a variant of catch-all keys, which always matches.
    return best!;
  }

  /// SelectorsMatch(`selectors`, `keys`).
  static bool _selectorsMatch(
      List<_Selector> selectors, List<VariantKey> keys) {
    for (var i = 0; i < keys.length; i++) {
      final key = keys[i];
      if (key is Literal && !selectors[i].match(_normalizeKey(key))) {
        return false;
      }
    }
    return true;
  }

  /// SelectorsCompare(`selectors`, `keys1`, `keys2`).
  static bool _selectorsCompare(
    List<_Selector> selectors,
    List<VariantKey> keys1,
    List<VariantKey> keys2,
  ) {
    for (var i = 0; i < keys1.length; i++) {
      switch ((keys1[i], keys2[i])) {
        case (CatchallKey(), Literal()):
          return false;
        case (Literal(), CatchallKey()):
          return true;
        case (CatchallKey(), CatchallKey()):
          continue;
        case (final Literal key1, final Literal key2):
          final k1 = _normalizeKey(key1);
          final k2 = _normalizeKey(key2);
          if (k1 == k2) continue;
          return selectors[i].betterThan(k1, k2);
      }
    }
    return false;
  }

  /// NormalizeKey(`key`).
  static String _normalizeKey(Literal key) => toNfc(key.value);

  // Expression and Markup Resolution

  /// The value of the variable [name], from its declaration or from the
  /// input mapping.
  _Resolved _resolveVariable(String name) {
    final key = toNfc(name);
    final declaration = _declarations[key];
    if (declaration == null) return _resolveInput(name);
    final resolved = _declared[key] ??= _resolveExpression(
      declaration.value,
      input: declaration is InputDeclaration,
    );
    return resolved;
  }

  /// The value of [name] in the input mapping. An absent or `null` value is
  /// an Unresolved Variable.
  _Resolved _resolveInput(String name) {
    final params = _params;
    Object? value;
    if (params != null) {
      value = params[name];
      if (value == null) {
        final key = toNfc(name);
        for (final MapEntry(key: param, value: paramValue) in params.entries) {
          if (paramValue != null && toNfc(param) == key) {
            value = paramValue;
            break;
          }
        }
      }
    }
    if (value == null) {
      _report(MessageResolutionError(
        ResolutionErrorKind.unresolvedVariable,
        'The variable \$$name has no value',
        source: '\$$name',
      ));
      return const _Fallback();
    }
    return _Value(value);
  }

  /// *Expression Resolution*. With [input], the expression is that of an
  /// `.input` declaration, whose variable comes from the input mapping.
  _Resolved _resolveExpression(Expression expression, {bool input = false}) {
    final operand = switch (expression.arg) {
      null => null,
      Literal(:final value) => _Value(value),
      VariableRef(:final name) =>
        input ? _resolveInput(name) : _resolveVariable(name),
    };
    final function = expression.function;
    if (function != null) {
      return _resolveFunction(function, operand, _source(expression));
    }
    // An expression without a function has an operand.
    if (operand case _Value(value: final value) when value is! MessageValue) {
      // Format numbers and dates as `:number` and `:datetime` would, which
      // the specification allows for an expression of only a variable.
      final implicit = switch (value) {
        num() => 'number',
        DateTime() => 'datetime',
        _ => null,
      };
      if (implicit != null &&
          expression is VariableExpression &&
          _format._functions.containsKey(implicit)) {
        return _resolveFunction(
            FunctionRef(implicit), operand, _source(expression));
      }
    }
    return operand!;
  }

  /// *Function Resolution*.
  _Resolved _resolveFunction(
    FunctionRef function,
    _Resolved? operand,
    String source,
  ) {
    final handler = _format._functions[toNfc(function.name)];
    if (handler == null) {
      _report(MessageResolutionError(
        ResolutionErrorKind.unknownFunction,
        'Unknown function :${function.name}',
        source: source,
      ));
      return const _Fallback();
    }
    if (operand is _Fallback) {
      // The handler cannot accept a fallback value as its operand.
      _report(MessageFunctionError.badOperand(
        'The operand of :${function.name} failed to resolve',
        source: source,
      ));
      return const _Fallback();
    }

    final (options, literalKeys) = _resolveOptions(function.options);
    final dir = _takeDir(options, source);
    final id = _takeId(options, source);
    literalKeys.removeAll(const [_uDir, _uId]);
    final context = MessageFunctionContext(
      locales: _format._locales,
      source: source,
      dir: dir,
      id: id,
      literalOptionKeys: literalKeys,
      onError: _report,
    );
    try {
      final value = handler(context, options, (operand as _Value?)?.value);
      return _Value(value, dir: dir, id: id);
    } on MessageFunctionError catch (error) {
      _report(error);
    } catch (error) {
      _report(_wrap(error, source));
    }
    return const _Fallback();
  }

  /// *Option Resolution*: the resolved options, and the names of those
  /// set with a literal.
  (Map<String, Object?>, Set<String>) _resolveOptions(
    Map<String, Operand> options,
  ) {
    final resolved = <String, Object?>{};
    final literalKeys = <String>{};
    for (final MapEntry(key: name, :value) in options.entries) {
      switch (value) {
        case Literal(:final value):
          resolved[name] = value;
          literalKeys.add(name);
        case VariableRef(name: final variable):
          switch (_resolveVariable(variable)) {
            case _Value(:final value):
              resolved[name] = value;
            case _Fallback():
              _report(MessageFunctionError.badOption(
                'The value of the option $name failed to resolve',
                source: '\$$variable',
              ));
          }
      }
    }
    return (resolved, literalKeys);
  }

  /// Removes the `u:dir` option from [options] and returns its direction,
  /// or `null` for `inherit` or an invalid value.
  MessageDirection? _takeDir(Map<String, Object?> options, String source) {
    if (!options.containsKey(_uDir)) return null;
    final value = _optionString(options.remove(_uDir));
    switch (value) {
      case 'ltr':
        return MessageDirection.ltr;
      case 'rtl':
        return MessageDirection.rtl;
      case 'auto':
        return MessageDirection.auto;
      case 'inherit':
        return null;
    }
    _report(MessageFunctionError.badOption(
      'The option u:dir must be ltr, rtl, auto, or inherit',
      source: source,
    ));
    return null;
  }

  /// Removes the `u:id` option from [options] and returns its value, or
  /// `null` if it is not a string.
  String? _takeId(Map<String, Object?> options, String source) {
    if (!options.containsKey(_uId)) return null;
    final value = options.remove(_uId);
    final id = switch (value) {
      String() => value,
      MessageValue() => _tryFormat(value),
      _ => null,
    };
    if (id == null) {
      _report(MessageFunctionError.badOption(
        'The option u:id must be a string',
        source: source,
      ));
    }
    return id;
  }

  String? _tryFormat(MessageValue value) {
    try {
      return value.formatToString();
    } catch (_) {
      return null;
    }
  }

  static Object? _optionString(Object? value) =>
      value is MessageValue ? value.value : value;

  /// *Markup Resolution*, which always succeeds.
  MessageMarkupPart _resolveMarkup(Markup markup) {
    final (options, _) = _resolveOptions(markup.options);
    final source = switch (markup.kind) {
      MarkupKind.open || MarkupKind.standalone => '#${markup.name}',
      MarkupKind.close => '/${markup.name}',
    };
    if (options.containsKey(_uDir)) {
      options.remove(_uDir);
      _report(MessageFunctionError.badOption(
        'The option u:dir is not allowed on markup',
        source: source,
      ));
    }
    final id = _takeId(options, source);
    return MessageMarkupPart(
      markup.kind,
      markup.name,
      id: id,
      options: {
        for (final MapEntry(:key, :value) in options.entries)
          key: value is MessageValue ? value.value : value,
      },
    );
  }

  // Formatting

  /// Formats [resolved] to a string, returning it with its directionality
  /// and whether `u:dir` asks to isolate it.
  (String, MessageDirection, bool) formatValue(_Value resolved, String source) {
    try {
      final value = _messageValue(resolved.value);
      return (
        value.formatToString(),
        resolved.dir ?? value.dir,
        resolved.dir != null,
      );
    } catch (error) {
      _reportFormatError(error, source);
      return ('{$source}', MessageDirection.auto, false);
    }
  }

  /// Formats [resolved] to a part, returning it with its directionality and
  /// whether `u:dir` asks to isolate it.
  (MessagePart, MessageDirection, bool) formatValueToPart(
    _Value resolved,
    String source,
  ) {
    try {
      final value = _messageValue(resolved.value);
      final parts = value.formatToParts();
      final dir = resolved.dir ?? value.dir;
      final part = MessageExpressionPart(
        value.type,
        source: source,
        value: parts == null
            ? value.formatToString()
            : parts.map((part) => part.value).join(),
        dir: dir,
        locale: value.locale,
        id: resolved.id,
        parts: parts == null ? null : List.unmodifiable(parts),
      );
      return (part, dir, resolved.dir != null);
    } catch (error) {
      _reportFormatError(error, source);
      return (MessageFallbackPart(source), MessageDirection.auto, false);
    }
  }

  void _reportFormatError(Object error, String source) =>
      _report(error is MessageFunctionError ? error : _wrap(error, source));

  /// The [MessageValue] that formats [value]: [value] itself, or a string
  /// value for a literal or an input value without a function.
  ///
  /// It calls `toString()` on other input values, which can throw, so call
  /// it where the error is reported as a Message Function Error.
  MessageValue _messageValue(Object value) => switch (value) {
        MessageValue() => value,
        String() => _StringValue(value, 'string', _format._locales.first),
        _ => _StringValue('$value', 'unknown', _format._locales.first),
      };

  static MessageFunctionError _wrap(Object error, String source) =>
      MessageFunctionError(
        MessageFunctionError.functionErrorType,
        'A function handler failed: $error',
        source: source,
        cause: error,
      );

  /// The fallback representation of [expression].
  static String _source(Expression expression) => switch (expression.arg) {
        Literal(:final value) =>
          '|${value.replaceAll(r'\', r'\\').replaceAll('|', r'\|')}|',
        VariableRef(:final name) => '\$$name',
        null => ':${expression.function!.name}',
      };
}

const _uDir = 'u:dir';
const _uId = 'u:id';

/// A selector's resolved value, which reports a Bad Selector once and then
/// matches only `*` when it does not support selection or fails.
final class _Selector {
  _Selector(this._formatter, this._value, this._source);

  final _Formatter _formatter;
  final SelectableMessageValue? _value;
  final String _source;

  bool failed = false;

  void fail([Object? cause]) {
    if (failed) return;
    failed = true;
    _formatter._report(MessageResolutionError(
      ResolutionErrorKind.badSelector,
      cause == null
          ? 'The selector $_source does not support selection'
          : 'Selection with $_source failed: $cause',
      source: _source,
    ));
  }

  bool match(String key) {
    if (failed) return false;
    try {
      return _value!.match(key);
    } catch (error) {
      fail(error);
      return false;
    }
  }

  bool betterThan(String key1, String key2) {
    if (failed) return false;
    try {
      return _value!.betterThan(key1, key2);
    } catch (error) {
      fail(error);
      return false;
    }
  }
}

/// The resolved value of a literal, or of an input value without a
/// function, when it is formatted.
final class _StringValue extends MessageValue {
  const _StringValue(this.value, this.type, this.locale);

  @override
  final String value;

  @override
  final String type;

  @override
  final String locale;

  @override
  String formatToString() => value;
}
