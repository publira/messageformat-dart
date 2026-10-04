import 'package:messageformat/messageformat.dart';
import 'package:test/test.dart';

import 'conformance/suite.dart';

void main() {
  group('stringifyMessage', () {
    test('writes a simple message when it can', () {
      expect(stringifyMessage(parseMessage('')), '');
      expect(stringifyMessage(parseMessage(' a {\$x} ')), ' a {\$x} ');
      expect(stringifyMessage(parseMessage('{{a}}')), 'a');
    });

    test('quotes a pattern that would start with a period', () {
      expect(stringifyMessage(parseMessage('{{ .a}}')), '{{ .a}}');
      expect(
        stringifyMessage(const PatternMessage([TextElement('\u200e.')])),
        '{{\u200e.}}',
      );
    });

    test('looks past leading text elements that are only whitespace', () {
      expect(
        stringifyMessage(const PatternMessage([
          TextElement(' '),
          TextElement('\u200e'),
          TextElement('.'),
        ])),
        '{{ \u200e.}}',
      );
      expect(
        stringifyMessage(const PatternMessage([
          TextElement(' '),
          VariableExpression(VariableRef('x')),
          TextElement('.'),
        ])),
        ' {\$x}.',
      );
    });

    test('quotes literals with unpaired surrogates', () {
      for (final source in ['{|\ud800|}', '{|a\udc00|}', '{|\udc00\ud800|}']) {
        final message = parseMessage(source);
        expect(stringifyMessage(message), source);
        expect(parseMessage(stringifyMessage(message)), message);
      }
    });

    test('escapes text and quoted literals', () {
      expect(
        stringifyMessage(parseMessage(r'\{\}\\| {|a\|\\{}|}')),
        r'\{\}\\| {|a\|\\{}|}',
      );
    });

    test('writes literals unquoted when it can', () {
      expect(
        stringifyMessage(parseMessage('{|abc| :f a=|1.5| b=|x y| c=||}')),
        '{abc :f a=1.5 b=|x y| c=||}',
      );
    });

    test('writes declarations, markup, attributes, and variants', () {
      const source = '.input {\$n :number}\n'
          '.local \$x = {:f @a @b=|c d|}\n'
          '.match \$n\n'
          '1 {{{#b k=\$x}one{/b}}}\n'
          '* {{{#img/}}}';
      expect(stringifyMessage(parseMessage(source)), source);
    });

    test('round-trips every well-formed source in the suite', () {
      for (final file in loadSuite()) {
        for (final testCase in file.cases) {
          final Message message;
          try {
            message = parseMessage(testCase.src, onError: (_) {});
          } on MessageSyntaxError {
            continue;
          }
          final source = stringifyMessage(message);
          expect(
            parseMessage(source, onError: (_) {}),
            message,
            reason: '${testCase.src} was written as $source',
          );
        }
      }
    });
  });
}
