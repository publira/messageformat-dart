import 'package:messageformat/messageformat.dart';
import 'package:test/test.dart';

void main() {
  group('parseMessage', () {
    test('parses an empty simple message', () {
      expect(parseMessage(''), const PatternMessage([]));
    });

    test('keeps whitespace around a simple message as text', () {
      expect(
        parseMessage(' \t hello {\$name} '),
        const PatternMessage([
          TextElement(' \t hello '),
          VariableExpression(VariableRef('name')),
          TextElement(' '),
        ]),
      );
    });

    test('processes escape sequences in text and quoted literals', () {
      expect(
        parseMessage(r'\{\}\\\| {|a\|b\\|}'),
        const PatternMessage([
          TextElement(r'{}\| '),
          LiteralExpression(Literal(r'a|b\')),
        ]),
      );
    });

    test('parses expressions with functions, options, and attributes', () {
      expect(
        parseMessage(
          '{42 :ns:fn a=1 b=|x y| c=\$v @attr @other=|z|} {:f} {\$x @a}',
        ),
        const PatternMessage([
          LiteralExpression(
            Literal('42'),
            function: FunctionRef('ns:fn', options: {
              'a': Literal('1'),
              'b': Literal('x y'),
              'c': VariableRef('v'),
            }),
            attributes: {'attr': null, 'other': Literal('z')},
          ),
          TextElement(' '),
          FunctionExpression(FunctionRef('f')),
          TextElement(' '),
          VariableExpression(VariableRef('x'), attributes: {'a': null}),
        ]),
      );
    });

    test('keeps the last of repeated attributes', () {
      final message = parseMessage('{x @a=1 @a=2}') as PatternMessage;
      expect(
        (message.pattern.single as Expression).attributes,
        {'a': const Literal('2')},
      );
    });

    test('treats attribute names that are equal under NFC as repeated', () {
      final message = parseMessage(
        '{x @\u1e0c\u0307=1 @b @D\u0323\u0307=2}',
      ) as PatternMessage;
      expect((message.pattern.single as Expression).attributes, {
        'b': null,
        'D\u0323\u0307': const Literal('2'),
      });
    });

    test('parses open, standalone, and close markup', () {
      expect(
        parseMessage('{#b k=v @a}{#img /}{/b}'),
        const PatternMessage([
          Markup(
            MarkupKind.open,
            'b',
            options: {'k': Literal('v')},
            attributes: {'a': null},
          ),
          Markup(MarkupKind.standalone, 'img'),
          Markup(MarkupKind.close, 'b'),
        ]),
      );
    });

    test('parses declarations and a quoted pattern', () {
      expect(
        parseMessage('''
          .input {\$count :number}
          .local \$x = {|a b| :string}
          {{{\$x} has {\$count}}}
        '''),
        const PatternMessage(
          [
            VariableExpression(VariableRef('x')),
            TextElement(' has '),
            VariableExpression(VariableRef('count')),
          ],
          declarations: [
            InputDeclaration(VariableExpression(
              VariableRef('count'),
              function: FunctionRef('number'),
            )),
            LocalDeclaration(
              'x',
              LiteralExpression(Literal('a b'),
                  function: FunctionRef('string')),
            ),
          ],
        ),
      );
    });

    test('parses a matcher', () {
      expect(
        parseMessage(
          '.input {\$n :number} .input {\$g :string}'
          '.match \$n \$g 1 |m| {{one}} one * {{few}}* *{{other}}',
        ),
        const SelectMessage(
          [VariableRef('n'), VariableRef('g')],
          [
            Variant([Literal('1'), Literal('m')], [TextElement('one')]),
            Variant([Literal('one'), CatchallKey()], [TextElement('few')]),
            Variant([CatchallKey(), CatchallKey()], [TextElement('other')]),
          ],
          declarations: [
            InputDeclaration(VariableExpression(
              VariableRef('n'),
              function: FunctionRef('number'),
            )),
            InputDeclaration(VariableExpression(
              VariableRef('g'),
              function: FunctionRef('string'),
            )),
          ],
        ),
      );
    });

    test('distinguishes the catch-all key from the literal *', () {
      final message = parseMessage(
        '.local \$x = {a :string} .match \$x |*| {{star}} * {{other}}',
      ) as SelectMessage;
      expect(message.variants.map((v) => v.keys.single), [
        const Literal('*'),
        const CatchallKey(),
      ]);
    });

    test('drops bidi marks around names', () {
      expect(
        parseMessage('{\$\u200ex\u200f :\u2066ns\u2069:\u200efn\u200f}'),
        const PatternMessage([
          VariableExpression(VariableRef('x'), function: FunctionRef('ns:fn')),
        ]),
      );
    });

    test('allows bidi marks in optional and required whitespace', () {
      expect(
        parseMessage(
          '\u200e.local\u200e \u200e\$x\u200e=\u200e{a}\u200e{{}}\u200e',
        ),
        const PatternMessage(
          [],
          declarations: [
            LocalDeclaration('x', LiteralExpression(Literal('a')))
          ],
        ),
      );
    });

    test('accepts names outside the BMP', () {
      expect(
        parseMessage('{\$\u{10000}\u{1f600} :\u{20000}}'),
        const PatternMessage([
          VariableExpression(
            VariableRef('\u{10000}\u{1f600}'),
            function: FunctionRef('\u{20000}'),
          ),
        ]),
      );
    });

    test('does not normalize text or names', () {
      expect(
        parseMessage('\u1e0a\u0323{\$D\u0323\u0307}'),
        const PatternMessage([
          TextElement('\u1e0a\u0323'),
          VariableExpression(VariableRef('D\u0323\u0307')),
        ]),
      );
    });

    test('returns unmodifiable collections', () {
      final message = parseMessage('{a :f k=v @x}') as PatternMessage;
      final expression = message.pattern.single as Expression;
      expect(
        () => message.pattern.add(const TextElement('b')),
        throwsUnsupportedError,
      );
      expect(
        () => expression.function!.options['j'] = const Literal('w'),
        throwsUnsupportedError,
      );
      expect(() => expression.attributes.clear(), throwsUnsupportedError);
    });
  });

  group('syntax errors', () {
    void expectSyntaxError(String source, int start, [int? end]) {
      expect(
        () => parseMessage(source),
        throwsA(isA<MessageSyntaxError>()
            .having((e) => e.type, 'type', 'syntax-error')
            .having((e) => e.start, 'start', start)
            .having((e) => e.end, 'end', end ?? start + 1)),
        reason: source,
      );
    }

    test('locate the offending character', () {
      expectSyntaxError('a}b', 1);
      expectSyntaxError(r'a\nb', 2);
      expectSyntaxError('{a b}', 3);
      expectSyntaxError('{{a}', 3);
      expectSyntaxError('.local \$x = {a}', 15, 15);
      expectSyntaxError('.input {a} {{}}', 7);
      expectSyntaxError('.local \$x = {#b} {{}}', 13);
      expectSyntaxError('.match {{}}', 7);
      expectSyntaxError('{\$x}{{}}', 5);
    });

    test('span a whole surrogate pair', () {
      expectSyntaxError('{a \u{1f600}}', 3, 5);
    });

    test('reject an unpaired surrogate in a name', () {
      expectSyntaxError('{\$x\ud800}', 3);
      expectSyntaxError('{\ud800}', 1);
    });

    test('reject NULL in text and quoted literals', () {
      expectSyntaxError('a\u0000', 1);
      expectSyntaxError('{|\u0000|}', 2);
    });

    test('take priority over Data Model Errors', () {
      expectSyntaxError('.input {\$x} .input {\$x} {{', 26, 26);
    });

    test('are reported even with an error callback', () {
      expect(
        () => parseMessage('{', onError: (_) {}),
        throwsA(isA<MessageSyntaxError>()),
      );
    });
  });

  group('data model errors', () {
    List<MessageDataModelError> errorsOf(String source) {
      final errors = <MessageDataModelError>[];
      parseMessage(source, onError: errors.add);
      return errors;
    }

    test('are thrown without an error callback', () {
      expect(
        () => parseMessage('.input {\$x} .input {\$x} {{}}'),
        throwsA(isA<MessageDataModelError>()
            .having((e) => e.type, 'type', 'duplicate-declaration')
            .having((e) => e.kind, 'kind',
                DataModelErrorKind.duplicateDeclaration)),
      );
    });

    test('are all reported, with their location, to the callback', () {
      const source = '.local \$a = {1} .local \$a = {2} '
          '.match \$a 1 2 {{x}} 1 {{y}} 1 {{z}}';
      final errors = errorsOf(source);
      expect(
        [
          for (final error in errors)
            (error.kind, source.substring(error.start!, error.end)),
        ],
        [
          (DataModelErrorKind.duplicateDeclaration, '.local \$a = {2}'),
          (DataModelErrorKind.missingSelectorAnnotation, '\$a'),
          (DataModelErrorKind.variantKeyMismatch, '1 2 {{x}}'),
          (DataModelErrorKind.duplicateVariant, '1 {{z}}'),
          (DataModelErrorKind.missingFallbackVariant, '.match'),
        ],
      );
    });

    test('locate duplicate option names', () {
      const source = '{:f a=1 b=2 a=3}';
      final error = errorsOf(source).single;
      expect(error.kind, DataModelErrorKind.duplicateOptionName);
      expect(source.substring(error.start!, error.end), 'a=3');
    });

    test('keep the first of duplicate options', () {
      final message =
          parseMessage('{#m a=1 a=2}', onError: (_) {}) as PatternMessage;
      expect((message.pattern.single as Markup).options, {
        'a': const Literal('1'),
      });
    });

    test('compare names and keys as if normalized to NFC', () {
      expect(
        errorsOf('{:f \u1e0c\u0307=1 D\u0323\u0307=2}').single.kind,
        DataModelErrorKind.duplicateOptionName,
      );
      expect(
        errorsOf('.input {\$\u1e0c\u0307} .local \$D\u0307\u0323 = {1} '
                '{{}}')
            .single
            .kind,
        DataModelErrorKind.duplicateDeclaration,
      );
      expect(
        errorsOf('.local \$x = {a :string} '
                '.match \$x \u1e0a\u0323 {{}} |\u1e0c\u0307| {{}} * {{}}')
            .single
            .kind,
        DataModelErrorKind.duplicateVariant,
      );
    });

    test('follow local variables to find a selector annotation', () {
      expect(
        errorsOf('.input {\$a :string} .local \$b = {\$a} .local \$c = {\$b} '
            '.match \$c x {{}} * {{}}'),
        isEmpty,
      );
      expect(
        errorsOf('.input {\$a} .local \$b = {\$a} .match \$b x {{}} * {{}}')
            .single
            .kind,
        DataModelErrorKind.missingSelectorAnnotation,
      );
    });
  });

  group('validateMessage', () {
    test('accepts a valid message', () {
      validateMessage(const SelectMessage(
        [VariableRef('x')],
        [
          Variant([CatchallKey()], []),
        ],
        declarations: [
          InputDeclaration(VariableExpression(
            VariableRef('x'),
            function: FunctionRef('string'),
          )),
        ],
      ));
    });

    test('reports errors without a location', () {
      final errors = <MessageDataModelError>[];
      validateMessage(
        const SelectMessage([
          VariableRef('x')
        ], [
          Variant([Literal('a')], []),
        ]),
        onError: errors.add,
      );
      expect(errors.map((e) => e.kind), [
        DataModelErrorKind.missingSelectorAnnotation,
        DataModelErrorKind.missingFallbackVariant,
      ]);
      expect(errors.map((e) => e.start), everyElement(isNull));
    });

    test('reports option names that are equal under NFC', () {
      final errors = <MessageDataModelError>[];
      validateMessage(
        const PatternMessage(
          [
            FunctionExpression(FunctionRef('f', options: {
              '\u1e0c\u0307': Literal('1'),
              'D\u0323\u0307': Literal('2'),
            })),
            Markup(MarkupKind.open, 'b', options: {
              'a': Literal('1'),
              'b': Literal('2'),
            }),
          ],
          declarations: [
            LocalDeclaration(
              'x',
              FunctionExpression(FunctionRef('g', options: {
                'k\u00e9': Literal('1'),
                'ke\u0301': Literal('2'),
              })),
            ),
          ],
        ),
        onError: errors.add,
      );
      expect(errors.map((e) => e.kind), [
        DataModelErrorKind.duplicateOptionName,
        DataModelErrorKind.duplicateOptionName,
      ]);
    });

    test('throws the first error without a callback', () {
      expect(
        () => validateMessage(const PatternMessage([], declarations: [
          LocalDeclaration('x', VariableExpression(VariableRef('x'))),
        ])),
        throwsA(isA<MessageDataModelError>()),
      );
    });
  });
}
