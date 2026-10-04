import 'package:messageformat/messageformat.dart';
import 'package:test/test.dart';

/// A minimal `:string`, enough to exercise the runtime until #6 adds the
/// default one.
MessageValue _string(
  MessageFunctionContext context,
  Map<String, Object?> options,
  Object? operand,
) {
  final value = switch (operand) {
    final String text => text,
    final MessageValue value => '${value.value}',
    null => throw MessageFunctionError.badOperand('An operand is required'),
    _ => '$operand',
  };
  return _StringValue(value, context.locales.first, context.dir);
}

final class _StringValue extends SelectableMessageValue {
  _StringValue(this.value, this.locale, MessageDirection? dir)
      : dir = dir ?? MessageDirection.auto;

  @override
  final String value;

  @override
  final String locale;

  @override
  final MessageDirection dir;

  @override
  String get type => 'string';

  @override
  String formatToString() => value;

  @override
  bool match(String key) => key == value;

  @override
  bool betterThan(String key1, String key2) => false;
}

/// A value that formats as its number in LTR digits.
final class _NumberValue extends SelectableMessageValue {
  _NumberValue(this.value);

  @override
  final num value;

  @override
  String get type => 'number';

  @override
  MessageDirection get dir => MessageDirection.ltr;

  @override
  String formatToString() => '$value';

  @override
  List<MessageValuePart> formatToParts() =>
      [MessageValuePart('integer', '$value')];

  @override
  bool match(String key) => num.tryParse(key) == value;

  @override
  bool betterThan(String key1, String key2) => false;
}

const _functions = <String, MessageFunction>{'string': _string};

MessageFormat _mf(
  String source, {
  Object? locales = 'en-US',
  BidiIsolation bidiIsolation = BidiIsolation.defaultStrategy,
  MessageDirection? dir,
  Map<String, MessageFunction> functions = _functions,
}) =>
    MessageFormat(
      locales,
      source,
      options: MessageFormatOptions(
        bidiIsolation: bidiIsolation,
        dir: dir,
        functions: functions,
      ),
    );

/// Formats [mf] to a string, returning it with the error types reported.
(String, List<String>) _format(MessageFormat mf,
    [Map<String, Object?>? params]) {
  final errors = <String>[];
  final result = mf.format(params, (error) => errors.add(error.type));
  return (result, errors);
}

(List<MessagePart>, List<String>) _parts(MessageFormat mf,
    [Map<String, Object?>? params]) {
  final errors = <String>[];
  final result = mf.formatToParts(params, (error) => errors.add(error.type));
  return (result, errors);
}

/// Matches the result of [_format] or [_parts].
Matcher _yields(Object? result, List<String> errors) =>
    isA<(Object?, List<String>)>()
        .having((r) => r.$1, 'result', result)
        .having((r) => r.$2, 'errors', errors);

void main() {
  group('MessageFormat', () {
    test('throws for a message that is not well-formed or not valid', () {
      expect(
          () => MessageFormat('en', '{'), throwsA(isA<MessageSyntaxError>()));
      expect(
        () => MessageFormat('en', '.input {\$x :f} .input {\$x :f} {{}}'),
        throwsA(isA<MessageDataModelError>()),
      );
      expect(
        () => MessageFormat.fromMessage(
          'en',
          const SelectMessage([
            VariableRef('x')
          ], [
            Variant([Literal('a')], []),
          ]),
        ),
        throwsA(isA<MessageDataModelError>()),
      );
    });

    test('formats a message built in code', () {
      final mf = MessageFormat.fromMessage(
        'en',
        const PatternMessage([
          TextElement('Hello '),
          VariableExpression(VariableRef('name')),
        ]),
        options: const MessageFormatOptions(bidiIsolation: BidiIsolation.none),
      );
      expect(mf.format({'name': 'World'}), 'Hello World');
    });

    test('accepts a locale, a list of locales, or null', () {
      List<String> locales(Object? locales) {
        late List<String> seen;
        _mf('{:f}', locales: locales, functions: {
          'f': (context, options, operand) {
            seen = context.locales;
            return _StringValue('', 'und', null);
          },
        }).format();
        return seen;
      }

      expect(locales('fr'), ['fr']);
      expect(locales(['de-CH', 'de']), ['de-CH', 'de']);
      expect(locales(null), ['und']);
      expect(locales(<String>[]), ['und']);
      expect(() => MessageFormat(42, ''), throwsArgumentError);
      expect(() => MessageFormat([42], ''), throwsArgumentError);
    });
  });

  group('errors', () {
    test('produce fallback values and are reported to onError', () {
      final mf = _mf('{\$x} {|a\\|b| :nope} {:nope}',
          bidiIsolation: BidiIsolation.none);
      expect(
          _format(mf),
          _yields(
            r'{$x} {|a\|b|} {:nope}',
            ['unresolved-variable', 'unknown-function', 'unknown-function'],
          ));
      expect(_parts(mf).$1, [
        const MessageFallbackPart(r'$x'),
        const MessageTextPart(' '),
        const MessageFallbackPart(r'|a\|b|'),
        const MessageTextPart(' '),
        const MessageFallbackPart(':nope'),
      ]);
    });

    test('are ignored without onError', () {
      final mf = _mf('{\$x}', bidiIsolation: BidiIsolation.none);
      expect(mf.format(), r'{$x}');
      expect(mf.formatToParts(), [const MessageFallbackPart(r'$x')]);
    });

    test('carry their kind and source', () {
      final errors = <MessageError>[];
      _mf('{\$x} {:nope}').format(null, errors.add);
      expect(
        errors,
        [
          isA<MessageResolutionError>()
              .having(
                  (e) => e.kind, 'kind', ResolutionErrorKind.unresolvedVariable)
              .having((e) => e.source, 'source', r'$x'),
          isA<MessageResolutionError>()
              .having(
                  (e) => e.kind, 'kind', ResolutionErrorKind.unknownFunction)
              .having((e) => e.source, 'source', ':nope'),
        ],
      );
    });

    test('treat a null parameter as unresolved', () {
      expect(_format(_mf('{\$x}'), {'x': null}).$2, ['unresolved-variable']);
    });

    test('wrap anything else a function handler throws', () {
      final errors = <MessageError>[];
      final failure = StateError('boom');
      final mf =
          _mf('{1 :fail}', bidiIsolation: BidiIsolation.none, functions: {
        'fail': (context, options, operand) => throw failure,
      });
      expect(mf.format(null, errors.add), '{|1|}');
      expect(
        errors.single,
        isA<MessageFunctionError>()
            .having((e) => e.type, 'type', 'function-error')
            .having((e) => e.cause, 'cause', failure)
            .having((e) => e.source, 'source', '|1|'),
      );
    });

    test('wrap anything a value throws while formatting', () {
      final mf = _mf('{1 :bad}', bidiIsolation: BidiIsolation.none, functions: {
        'bad': (context, options, operand) => _ThrowingValue(),
      });
      expect(_format(mf), _yields('{|1|}', ['function-error']));
      expect(
          _parts(mf),
          _yields(
            [const MessageFallbackPart('|1|')],
            ['function-error'],
          ));
    });

    test('wrap an input value whose toString throws', () {
      final mf = _mf('{\$x}', bidiIsolation: BidiIsolation.none);
      final params = {'x': _ThrowingToString()};
      expect(_format(mf, params), _yields(r'{$x}', ['function-error']));
      expect(
        _parts(mf, params),
        _yields([const MessageFallbackPart(r'$x')], ['function-error']),
      );
    });

    test('report errors a function handler recovers from', () {
      final mf =
          _mf('{1 :warn}', bidiIsolation: BidiIsolation.none, functions: {
        'warn': (context, options, operand) {
          context.onError(MessageFunctionError.badOption('ignored'));
          return _StringValue('ok', 'en', null);
        },
      });
      expect(_format(mf), _yields('ok', ['bad-option']));
    });

    test('report an option whose variable is unresolved, and drop it', () {
      late Map<String, Object?> seen;
      final mf = _mf('{1 :f a=\$x b=c}', functions: {
        'f': (context, options, operand) {
          seen = options;
          return _StringValue('', 'en', null);
        },
      });
      expect(_format(mf).$2, ['unresolved-variable', 'bad-option']);
      expect(seen, {'b': 'c'});
    });
  });

  group('custom functions', () {
    test('receive the operand, options, and context', () {
      late MessageFunctionContext context;
      late Map<String, Object?> options;
      late Object? operand;
      final declared = _StringValue('v', 'en', null);
      final mf = _mf(
        '.local \$v = {v :g} {{{\$x :f a=1 b=\$v c=\$y u:id=id u:dir=rtl}}}',
        functions: {
          'f': (c, o, x) {
            context = c;
            options = o;
            operand = x;
            return _StringValue('', 'en', null);
          },
          'g': (c, o, x) => declared,
        },
      );
      expect(_format(mf, {'x': 42, 'y': 'why'}).$2, isEmpty);
      expect(operand, 42);
      expect(options, {'a': '1', 'b': declared, 'c': 'why'});
      expect(context.literalOptionKeys, {'a'});
      expect(context.id, 'id');
      expect(context.dir, MessageDirection.rtl);
      expect(context.source, r'$x');
      expect(context.locales, ['en-US']);
    });

    test('format a number without a function as the number function', () {
      final mf = _mf('.input {\$x} {{{\$x}}}', functions: {
        'number': (context, options, operand) => _NumberValue(operand as num),
      });
      expect(_parts(mf, {'x': 42}).$1, [
        isA<MessageExpressionPart>()
            .having((p) => p.type, 'type', 'number')
            .having((p) => p.value, 'value', '42')
            .having((p) => p.parts, 'parts',
                [const MessageValuePart('integer', '42')]),
      ]);
    });

    test('are looked up with NFC identifiers', () {
      final mf = _mf('{|x| :\u1e0c\u0307}', functions: {
        'D\u0323\u0307': (context, options, operand) =>
            _StringValue('ok', 'en', MessageDirection.ltr),
      });
      expect(_format(mf), _yields('ok', <String>[]));
    });

    test('see a fallback operand as a Bad Operand without being called', () {
      var called = false;
      final mf = _mf('{\$x :f}', bidiIsolation: BidiIsolation.none, functions: {
        'f': (context, options, operand) {
          called = true;
          return _StringValue('', 'en', null);
        },
      });
      expect(_format(mf),
          _yields(r'{$x}', ['unresolved-variable', 'bad-operand']));
      expect(called, isFalse);
    });

    test('are called at most once per declaration', () {
      var calls = 0;
      final mf = _mf(
        '.local \$x = {1 :count} .match \$x 1 {{{\$x}{\$x}}} * {{}}',
        bidiIsolation: BidiIsolation.none,
        functions: {
          'count': (context, options, operand) {
            calls++;
            return _NumberValue(1);
          },
        },
      );
      expect(_format(mf), _yields('11', <String>[]));
      expect(calls, 1);
    });

    test('are not called for unused declarations', () {
      var calls = 0;
      final mf = _mf('.local \$x = {1 :count} {{}}', functions: {
        'count': (context, options, operand) {
          calls++;
          return _NumberValue(1);
        },
      });
      expect(_format(mf), _yields('', <String>[]));
      expect(calls, 0);
    });
  });

  group('selection', () {
    test('compares string keys after NFC normalization', () {
      final mf = _mf(
        '.input {\$x :string} .match \$x |\u1e0c\u0307| {{dot}} * {{other}}',
      );
      expect(_format(mf, {'x': '\u1e0c\u0307'}).$1, 'dot');
    });

    test('matches only * for a selector whose betterThan fails', () {
      final mf = _mf(
        '.local \$x = {1 :flaky} .match \$x 1 {{exact}} one {{one}} * {{other}}',
        functions: {'flaky': (context, options, operand) => _FlakyValue()},
      );
      expect(_format(mf), _yields('other', ['bad-selector']));
    });
  });

  group('bidi isolation', () {
    test('isolates placeholders by their direction', () {
      final mf = _mf(
        '{a} {1 :n} {b :string u:dir=ltr} {c :string u:dir=rtl} '
        '{d :string u:dir=auto} {e :string u:dir=inherit}',
        functions: {
          ..._functions,
          'n': (context, options, operand) => _NumberValue(1),
        },
      );
      expect(
        _format(mf).$1,
        '\u2068a\u2069 1 \u2066b\u2069 \u2067c\u2069 \u2068d\u2069 '
        '\u2068e\u2069',
      );
    });

    test('isolates left-to-right values in a right-to-left message', () {
      final functions = {
        'n': (MessageFunctionContext c, Map<String, Object?> o, Object? x) =>
            _NumberValue(1),
      };
      expect(_mf('{1 :n}', locales: 'ar', functions: functions).format(),
          '\u20661\u2069');
      expect(_mf('{1 :n}', locales: 'az-Arab', functions: functions).format(),
          '\u20661\u2069');
      expect(_mf('{1 :n}', locales: 'rhg', functions: functions).format(),
          '\u20661\u2069');
      expect(
          _mf('{1 :n}', dir: MessageDirection.auto, functions: functions)
              .format(),
          '\u20661\u2069');
      expect(
          _mf('{1 :n}',
                  locales: 'he',
                  dir: MessageDirection.ltr,
                  functions: functions)
              .format(),
          '1');
    });

    test('isolates fallback values', () {
      expect(_mf('{\$x}').format(), '\u2068{\$x}\u2069');
    });

    test('adds isolation parts, but none with BidiIsolation.none', () {
      final source = 'a {b :string u:dir=rtl u:id=x} {#m u:id=y/}';
      expect(_parts(_mf(source)).$1, [
        const MessageTextPart('a '),
        const MessageBidiIsolationPart('\u2067'),
        const MessageExpressionPart(
          'string',
          source: '|b|',
          value: 'b',
          dir: MessageDirection.rtl,
          locale: 'en-US',
          id: 'x',
        ),
        const MessageBidiIsolationPart('\u2069'),
        const MessageTextPart(' '),
        const MessageMarkupPart(MarkupKind.standalone, 'm', id: 'y'),
      ]);
      expect(
        _parts(_mf(source, bidiIsolation: BidiIsolation.none))
            .$1
            .whereType<MessageBidiIsolationPart>(),
        isEmpty,
      );
    });
  });

  group('u: options', () {
    test('keep u:dir and u:id with a declared value', () {
      final mf = _mf(
          '.local \$w = {world :string u:dir=ltr u:id=foo} {{hello {\$w}}}');
      expect(mf.format(), 'hello \u2066world\u2069');
      expect(
        _parts(mf).$1[2],
        isA<MessageExpressionPart>()
            .having((p) => p.dir, 'dir', MessageDirection.ltr)
            .having((p) => p.id, 'id', 'foo')
            .having((p) => p.source, 'source', r'$w'),
      );
    });

    test('reject an invalid u:dir or u:id and ignore it', () {
      final mf = _mf('{a :string u:dir=up} {b :string u:id=\$n}',
          bidiIsolation: BidiIsolation.none);
      final (parts, errors) = _parts(mf, {'n': _ThrowingToString()});
      expect(errors, ['bad-option', 'bad-option']);
      expect(parts.whereType<MessageExpressionPart>().map((p) => p.id),
          [null, null]);
    });

    test('accept a u:id that resolves to a string', () {
      final mf = _mf(
        '.local \$v = {1 :n} {{{a :string u:id=\$n} {b :string u:id=\$v}}}',
        functions: {
          ..._functions,
          'n': (context, options, operand) => _NumberValue(7),
        },
      );
      final (parts, errors) = _parts(mf, {'n': 42});
      expect(errors, isEmpty);
      expect(parts.whereType<MessageExpressionPart>().map((p) => p.id),
          ['42', '7']);
    });

    test('report a u:dir whose value cannot be read, and ignore it', () {
      final mf = _mf('.local \$d = {d :unreadable} {{{a :string u:dir=\$d}}}',
          functions: {
            ..._functions,
            'unreadable': (context, options, operand) => _UnreadableValue(),
          });
      expect(_format(mf), _yields('\u2068a\u2069', ['bad-option']));
    });

    test('accept u:dir and u:id from variables', () {
      final mf = _mf('{a :string u:dir=\$d u:id=\$i}');
      expect(_format(mf, {'d': 'rtl', 'i': 'x'}),
          _yields('\u2067a\u2069', <String>[]));
    });

    test('reject u:dir on markup', () {
      final (parts, errors) = _parts(_mf('{#b u:dir=rtl}x{/b}'));
      expect(errors, ['bad-option']);
      expect(parts.first, const MessageMarkupPart(MarkupKind.open, 'b'));
    });
  });

  group('markup', () {
    test('formats to nothing in a string and to parts with options', () {
      final mf = _mf('{#a x=1 y=\$y @attr}t{/a}{#br/}');
      expect(mf.format({'y': 2}), 't');
      expect(mf.formatToParts({'y': 2}), [
        const MessageMarkupPart(MarkupKind.open, 'a',
            options: {'x': '1', 'y': 2}),
        const MessageTextPart('t'),
        const MessageMarkupPart(MarkupKind.close, 'a'),
        const MessageMarkupPart(MarkupKind.standalone, 'br'),
      ]);
    });

    test('leaves out an option whose value cannot be read', () {
      final mf =
          _mf('.local \$v = {v :unreadable} {{{#a x=\$v y=1/}}}', functions: {
        'unreadable': (context, options, operand) => _UnreadableValue(),
      });
      expect(
        _parts(mf),
        _yields([
          const MessageMarkupPart(MarkupKind.standalone, 'a',
              options: {'y': '1'}),
        ], [
          'function-error'
        ]),
      );
    });
  });
}

/// A value whose [value] getter throws.
final class _UnreadableValue extends MessageValue {
  @override
  String get type => 'unreadable';

  @override
  Object? get value => throw StateError('unreadable');

  @override
  String formatToString() => 'unreadable';
}

final class _ThrowingValue extends MessageValue {
  @override
  String get type => 'throwing';

  @override
  Object? get value => null;

  @override
  String formatToString() => throw StateError('cannot format');

  @override
  List<MessageValuePart> formatToParts() => throw StateError('cannot format');
}

/// Matches `1` and `one`, but fails to rank them.
final class _FlakyValue extends SelectableMessageValue {
  @override
  String get type => 'flaky';

  @override
  Object? get value => 1;

  @override
  String formatToString() => '1';

  @override
  bool match(String key) => key == '1' || key == 'one';

  @override
  bool betterThan(String key1, String key2) => throw StateError('flaky');
}

/// An input value that cannot be converted to a string.
final class _ThrowingToString {
  @override
  String toString() => throw StateError('no string');
}
