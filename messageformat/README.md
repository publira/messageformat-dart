# messageformat

A pure-Dart implementation of [Unicode MessageFormat 2.0](https://www.unicode.org/reports/tr35/tr35-78/tr35-messageFormat.html) (MF2), the localization message syntax standardized in UTS #35, Part 9. It parses messages with plurals, selectors, placeholders, and markup, and formats them to strings or to parts.

The package depends only on Dart, not on Flutter, so it works on the server, on the command line, and in Flutter apps alike.

## Specification version

The package implements **LDML 48.2**, revision [`tr35-78`](https://www.unicode.org/reports/tr35/tr35-78/tr35-messageFormat.html) of UTS #35, Part 9. Its locale data comes from **Unicode CLDR 48.2**, the CLDR release of the same version.

Correctness is judged by the [MessageFormat Working Group conformance suite](https://github.com/unicode-org/message-format-wg/tree/LDML48.2/test) at tag `LDML48.2`. A move to a later version of the specification is made in a release of its own.

## Conformance

At WG tag `LDML48.2`, **all 461 test cases in the 16 test files pass**, with none skipped and none deferred, when the date/time functions of [`messageformat_datetime`](https://pub.dev/packages/messageformat_datetime) are registered. The suite runs under `dart test` in CI on every change, together with the 20 unpaired-surrogate cases that the suite asks UTF-16 implementations to add themselves.

This package provides the default functions that the specification marks Stable, which it requires of every implementation. The Draft date/time functions, whose locale data is most of the size of the CLDR data, are in the separate `messageformat_datetime` package, so that an app that does not format dates does not ship that data.

| Function | Status in LDML 48.2 | Supported |
|---|---|---|
| `:string` | Stable | Yes |
| `:number` | Stable | Yes |
| `:integer` | Stable | Yes |
| `:offset` | Stable | Yes |
| `:currency` | Stable | Yes |
| `:percent` | Stable | Yes |
| `:datetime` | Draft | With `messageformat_datetime` |
| `:date` | Draft | With `messageformat_datetime` |
| `:time` | Draft | With `messageformat_datetime` |
| `:unit` | Draft | No; the suite has no tests for it |

The number functions cover every CLDR locale, and they format as ECMA-402 `Intl.NumberFormat` does, with two differences: `:currency` with `currencyDisplay=name` shows the currency code, such as `42.00 EUR`, because currency names are not included; and the locale `und` uses CLDR's root data.

## Installation

```sh
dart pub add messageformat
```

The package supports Dart 3.6 and later.

## Usage

```dart
import 'package:messageformat/messageformat.dart';
```

### Formatting a message

A `MessageFormat` takes a locale, or a list of locales in order of preference, and the message source. The message is parsed and checked once; `format` can then be called with different values.

```dart
final mf = MessageFormat('en', r'Hello, {$name}!');
mf.format({'name': 'World'}); // 'Hello, \u2068World\u2069!'
```

A message that is not well-formed throws a `MessageSyntaxError`, and one that is well-formed but not valid throws a `MessageDataModelError`, both with the offset of the problem in the source.

### Bidi isolation

As the specification requires, `format` isolates each placeholder with Unicode isolate controls, such as U+2068 and U+2069 above, unless the placeholder is known to share the message's left-to-right direction. This keeps right-to-left values from reordering the text around them. To format without isolation, for example for text that is never shown in a right-to-left context, set `bidiIsolation`:

```dart
final mf = MessageFormat(
  'en',
  r'Hello, {$name}!',
  options: const MessageFormatOptions(bidiIsolation: BidiIsolation.none),
);
mf.format({'name': 'World'}); // 'Hello, World!'
```

The message's base direction comes from its locale and can be set with `MessageFormatOptions.dir`.

The remaining examples use `BidiIsolation.none` to keep their output readable.

### Plurals and selection

`.match` selects a variant. With `:number` or `:integer`, keys match exact numbers first and then the locale's CLDR plural categories:

```dart
final mf = MessageFormat('en', r'''
.input {$count :number}
.match $count
0   {{No episodes}}
one {{{$count} episode}}
*   {{{$count} episodes}}
''', options: const MessageFormatOptions(bidiIsolation: BidiIsolation.none));

mf.format({'count': 0}); // 'No episodes'
mf.format({'count': 1}); // '1 episode'
mf.format({'count': 1000}); // '1,000 episodes'
```

`select=ordinal` selects with ordinal rules instead, and `:string` matches keys literally.

### Numbers

```dart
const none = MessageFormatOptions(bidiIsolation: BidiIsolation.none);

MessageFormat('de', r'{$price :currency currency=EUR}', options: none)
    .format({'price': 1234.5}); // '1.234,50\u00a0€'

MessageFormat('en', r'{$ratio :percent}', options: none)
    .format({'ratio': 0.5}); // '50%'
```

A number in a placeholder without a function is formatted with `:number`.

### Dates and times

The date/time functions `:datetime`, `:date`, and `:time` are in the [`messageformat_datetime`](https://pub.dev/packages/messageformat_datetime) package, which provides them as the map `dateTimeFunctions` to register:

```dart
import 'package:messageformat_datetime/messageformat_datetime.dart';

final mf = MessageFormat(
  'en',
  r'Updated {$when :date}',
  options: MessageFormatOptions(
    bidiIsolation: BidiIsolation.none,
    functions: dateTimeFunctions,
  ),
);
mf.format({'when': DateTime(2006, 1, 2, 15, 4)}); // 'Updated Jan 2, 2006'
```

Once they are registered, a `DateTime` in a placeholder without a function is formatted with `:datetime`. Without them, a message that calls one of them reports an `unknown-function` error that names the package, and a `DateTime` in a placeholder without a function is formatted with its `toString()`.

### Formatting to parts

`formatToParts` returns the formatted message as a list of `MessagePart`s, for output that is not a plain string, such as styled text:

```dart
final mf = MessageFormat(
  'en',
  r'You have {$count :integer} {#b}new{/b} messages',
  options: const MessageFormatOptions(bidiIsolation: BidiIsolation.none),
);
mf.formatToParts({'count': 1234});
// [
//   MessageTextPart('You have '),
//   MessageExpressionPart('number', value: '1,234', parts: [
//     MessageValuePart('integer', '1'),
//     MessageValuePart('group', ','),
//     MessageValuePart('integer', '234'),
//   ], ...),
//   MessageTextPart(' '),
//   MessageMarkupPart(MarkupKind.open, 'b'),
//   MessageTextPart('new'),
//   MessageMarkupPart(MarkupKind.close, 'b'),
//   MessageTextPart(' messages'),
// ]
```

The part classes form a sealed hierarchy, so a `switch` over them is checked for exhaustiveness. Markup formats to nothing in `format`.

### Errors

Formatting does not throw for a problem in the message or its values. Each *Resolution Error* and *Message Function Error* is passed to the optional error callback, and a placeholder that failed is replaced by its fallback value:

```dart
final mf = MessageFormat(
  'en',
  r'Hi {$name}',
  options: const MessageFormatOptions(bidiIsolation: BidiIsolation.none),
);
final errors = <MessageError>[];
mf.format({}, errors.add); // 'Hi {$name}'
errors.single.type; // 'unresolved-variable'
```

Every error is a `MessageError` whose `type` is the error's name in the specification and the conformance suite.

### Custom functions

A function handler resolves an expression such as `{$word :shout}` to a `MessageValue`. Register it in `MessageFormatOptions.functions` by name, without the `:`; it is added to the default functions and replaces one with the same name.

```dart
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

MessageValue shout(
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

final mf = MessageFormat(
  'en',
  r'{$word :shout}!',
  options: MessageFormatOptions(
    bidiIsolation: BidiIsolation.none,
    functions: {'shout': shout},
  ),
);
mf.format({'word': 'hello'}); // 'HELLO!'
```

A value that can be used in `.match` extends `SelectableMessageValue` and implements `match` and `betterThan`, the specification's key matching. A value can also override `formatToParts`, `dir`, and `options`.

A package of functions with Unicode CLDR data of its own, such as `messageformat_datetime`, can import `package:messageformat/locale.dart`. Its `CldrLocale` resolves a list of language tags to a CLDR locale and its ancestors in the same way as the default functions, with the locale's digits and direction.

### The data model

`parseMessage` parses a source into the specification's data model, `stringifyMessage` turns a data model back into source, and `validateMessage` checks one built in code. `MessageFormat.fromMessage` formats a data model directly.

## Coming from JavaScript

The API follows the JS [`messageformat`](https://www.npmjs.com/package/messageformat) package v4 and the TC39 [`Intl.MessageFormat`](https://github.com/tc39/proposal-intl-messageformat) proposal, adapted to Dart:

| JS `messageformat` v4 | Dart `messageformat` |
|---|---|
| `new MessageFormat(locales, source, options)` | `MessageFormat(locales, source, options: ...)` |
| `new MessageFormat(locales, message, options)` with a data model object | `MessageFormat.fromMessage(locales, message, options: ...)` |
| `mf.format(msgParams, onError)` | `mf.format(params, onError)` |
| `mf.formatToParts(msgParams, onError)` | `mf.formatToParts(params, onError)` |
| `bidiIsolation: 'default'` / `'none'` | `bidiIsolation: BidiIsolation.defaultStrategy` / `BidiIsolation.none` |
| `dir: 'ltr' \| 'rtl' \| 'auto'` | `dir: MessageDirection.ltr` / `.rtl` / `.auto` |
| `localeMatcher` | Not supported; the first locale is used |
| `functions: { ...DraftFunctions, ...custom }` | `functions: {...dateTimeFunctions, ...custom}`, with `dateTimeFunctions` from `messageformat_datetime` |
| `MessageFunction` `(context, options, input)` | `MessageFunction` `(context, options, operand)` |
| `MessageValue` with `toString()`, `toParts()`, `valueOf()` | `MessageValue` with `formatToString()`, `formatToParts()`, `value` |
| `MessageValue.selectKey(keys)` | `SelectableMessageValue.match(key)` and `betterThan(key1, key2)` |
| `MessageSyntaxError`, `MessageDataModelError`, `MessageResolutionError`, `MessageFunctionError` | The same names, all subtypes of `MessageError` |
| `parseMessage`, `stringifyMessage`, `validate` | `parseMessage`, `stringifyMessage`, `validateMessage` |

## Not included

- MessageFormat 1 / ICU MessageFormat syntax.
- The Draft `:unit` function.
- Flutter integration, such as a `LocalizationsDelegate`; that is planned as a separate package.

## License

The package is licensed under the [Apache License 2.0](LICENSE). Its locale data is derived from Unicode CLDR, under the [Unicode License v3](https://www.unicode.org/license.txt), whose notice each generated data file carries.
