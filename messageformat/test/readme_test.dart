/// The examples in README.md and example/, with the results the README
/// states. Update the README when one of these changes.
library;

import 'dart:async';

import 'package:messageformat/messageformat.dart';
import 'package:messageformat_datetime/messageformat_datetime.dart';
import 'package:test/test.dart';

import '../example/messageformat_example.dart' as example;

const _none = MessageFormatOptions(bidiIsolation: BidiIsolation.none);

void main() {
  test('formatting a message', () {
    final mf = MessageFormat('en', r'Hello, {$name}!');
    expect(mf.format({'name': 'World'}), 'Hello, \u2068World\u2069!');
  });

  test('bidi isolation', () {
    final mf = MessageFormat('en', r'Hello, {$name}!', options: _none);
    expect(mf.format({'name': 'World'}), 'Hello, World!');
  });

  test('plurals and selection', () {
    final mf = MessageFormat(
        'en',
        r'''
.input {$count :number}
.match $count
0   {{No episodes}}
one {{{$count} episode}}
*   {{{$count} episodes}}
''',
        options: _none);
    expect(mf.format({'count': 0}), 'No episodes');
    expect(mf.format({'count': 1}), '1 episode');
    expect(mf.format({'count': 1000}), '1,000 episodes');
  });

  test('numbers', () {
    expect(
      MessageFormat('de', r'{$price :currency currency=EUR}', options: _none)
          .format({'price': 1234.5}),
      '1.234,50\u00a0€',
    );
    expect(
      MessageFormat('en', r'{$ratio :percent}', options: _none)
          .format({'ratio': 0.5}),
      '50%',
    );
  });

  test('dates and times', () {
    final mf = MessageFormat(
      'en',
      r'Updated {$when :date}',
      options: const MessageFormatOptions(
        bidiIsolation: BidiIsolation.none,
        functions: dateTimeFunctions,
      ),
    );
    final when = DateTime(2006, 1, 2, 15, 4);
    expect(mf.format({'when': when}), 'Updated Jan 2, 2006');

    final implicit = MessageFormat('en', r'{$when}',
        options: const MessageFormatOptions(
          bidiIsolation: BidiIsolation.none,
          functions: dateTimeFunctions,
        ));
    expect(implicit.format({'when': when}), 'Jan 2, 2006, 3:04\u202fPM');

    final errors = <MessageError>[];
    final unregistered =
        MessageFormat('en', r'Updated {$when :date}', options: _none);
    expect(unregistered.format({'when': when}, errors.add), r'Updated {$when}');
    expect(errors.single.type, 'unknown-function');
    expect(errors.single.message, contains('messageformat_datetime'));
    expect(
        MessageFormat('en', r'{$when}', options: _none).format({'when': when}),
        when.toString());
  });

  test('formatting to parts', () {
    final mf = MessageFormat(
      'en',
      r'You have {$count :integer} {#b}new{/b} messages',
      options: _none,
    );
    expect(mf.formatToParts({'count': 1234}), [
      const MessageTextPart('You have '),
      const MessageExpressionPart(
        'number',
        source: r'$count',
        value: '1,234',
        dir: MessageDirection.ltr,
        locale: 'en',
        parts: [
          MessageValuePart('integer', '1'),
          MessageValuePart('group', ','),
          MessageValuePart('integer', '234'),
        ],
      ),
      const MessageTextPart(' '),
      const MessageMarkupPart(MarkupKind.open, 'b'),
      const MessageTextPart('new'),
      const MessageMarkupPart(MarkupKind.close, 'b'),
      const MessageTextPart(' messages'),
    ]);
  });

  test('errors', () {
    final mf = MessageFormat('en', r'Hi {$name}', options: _none);
    final errors = <MessageError>[];
    expect(mf.format({}, errors.add), r'Hi {$name}');
    expect(errors.single.type, 'unresolved-variable');
  });

  test('custom functions', () {
    final mf = MessageFormat(
      'en',
      r'{$word :shout}!',
      options: const MessageFormatOptions(
        bidiIsolation: BidiIsolation.none,
        functions: {'shout': example.shoutFunction},
      ),
    );
    expect(mf.format({'word': 'hello'}), 'HELLO!');

    final errors = <MessageError>[];
    expect(mf.format({'word': 42}, errors.add), r'{$word}!');
    expect(errors.single.type, 'bad-operand');
  });

  test('the example prints what its comments say', () {
    final lines = <String>[];
    runZoned(
      example.main,
      zoneSpecification: ZoneSpecification(
        print: (self, parent, zone, line) => lines.add(line),
      ),
    );
    expect(lines, [
      'Hello, \u2068World\u2069!',
      'Hello, World!',
      'No episodes',
      '1 episode',
      '1,000 episodes',
      'MessageTextPart(You have )',
      startsWith('MessageExpressionPart(number, 1,234,'),
      'MessageTextPart( )',
      'MessageMarkupPart(open, b, {})',
      'MessageTextPart(new)',
      'MessageMarkupPart(close, b, {})',
      'MessageTextPart( messages)',
      r'Hi {$name}',
      'unresolved-variable',
      'HELLO!',
    ]);
  });
}
