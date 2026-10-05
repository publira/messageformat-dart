// The examples from the package README, runnable with
// `dart run example/messageformat_example.dart`.
//
// `test/readme_test.dart` checks the same messages, so update both when a
// README example changes.
import 'package:messageformat/messageformat.dart';

void main() {
  // Format a message. Placeholders are isolated with U+2068 and U+2069 by
  // default; `BidiIsolation.none` turns that off.
  final hello = MessageFormat('en', r'Hello, {$name}!');
  print(hello.format({'name': 'World'})); // 'Hello, \u2068World\u2069!'

  const noIsolation = MessageFormatOptions(bidiIsolation: BidiIsolation.none);
  final plain = MessageFormat('en', r'Hello, {$name}!', options: noIsolation);
  print(plain.format({'name': 'World'})); // 'Hello, World!'

  // Select a variant with plural rules.
  final episodes = MessageFormat(
    'en',
    r'''
.input {$count :number}
.match $count
0   {{No episodes}}
one {{{$count} episode}}
*   {{{$count} episodes}}
''',
    options: noIsolation,
  );
  for (final count in [0, 1, 1000]) {
    print(episodes.format({'count': count}));
    // 'No episodes', '1 episode', '1,000 episodes'
  }

  // Format to parts, for example to style markup or a number's digits.
  final inbox = MessageFormat(
    'en',
    r'You have {$count :integer} {#b}new{/b} messages',
    options: noIsolation,
  );
  for (final part in inbox.formatToParts({'count': 1234})) {
    print(part);
  }

  // Report errors. Formatting never throws for a bad input: a placeholder
  // that fails formats as its fallback value.
  final greeting = MessageFormat('en', r'Hi {$name}', options: noIsolation);
  final errors = <MessageError>[];
  print(greeting.format({}, errors.add)); // 'Hi {$name}'
  print(errors.single.type); // 'unresolved-variable'

  // Add a custom function.
  final shout = MessageFormat(
    'en',
    r'{$word :shout}!',
    options: MessageFormatOptions(
      bidiIsolation: BidiIsolation.none,
      functions: {'shout': shoutFunction},
    ),
  );
  print(shout.format({'word': 'hello'})); // 'HELLO!'
}

/// The handler of `:shout`, which formats its operand in upper case.
MessageValue shoutFunction(
  MessageFunctionContext context,
  Map<String, Object?> options,
  Object? operand,
) {
  if (operand is! String) {
    throw MessageFunctionError.badOperand(
      'The operand of :shout must be a string',
      source: context.source,
    );
  }
  return ShoutValue(operand.toUpperCase(), context.locales.first);
}

/// The resolved value of a `:shout` expression.
final class ShoutValue extends MessageValue {
  const ShoutValue(this.value, this.locale);

  @override
  final String value;

  @override
  final String locale;

  @override
  String get type => 'shout';

  @override
  String formatToString() => value;
}
