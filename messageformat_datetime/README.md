# messageformat_datetime

The date/time functions of [Unicode MessageFormat 2.0](https://www.unicode.org/reports/tr35/tr35-78/tr35-messageFormat.html), `:datetime`, `:date`, and `:time`, for the pure-Dart [`messageformat`](https://pub.dev/packages/messageformat) package, with their Unicode CLDR data.

`messageformat` provides the default functions that the specification marks Stable. These functions are a package of their own because their locale data is large, about 900 KB of source for every CLDR locale, so that an app that does not format dates does not ship it. Like `messageformat`, the package depends only on Dart, not on Flutter.

## Specification version

The package implements the date/time functions of **LDML 48.2**, revision [`tr35-78`](https://www.unicode.org/reports/tr35/tr35-78/tr35-messageFormat.html) of UTS #35, Part 9, with the date data of **Unicode CLDR 48.2**. Together with `messageformat`, they pass every case of the [MessageFormat Working Group conformance suite](https://github.com/unicode-org/message-format-wg/tree/LDML48.2/test) at tag `LDML48.2`, including those in `functions/date.json`, `functions/datetime.json`, and `functions/time.json`.

> [!NOTE]
> The specification marks `:datetime`, `:date`, and `:time` as **Draft**. Their options and output can change in a minor release of this package when a later version of the specification changes them.

## Installation

```sh
dart pub add messageformat messageformat_datetime
```

The package supports Dart 3.6 and later.

## Usage

Register `dateTimeFunctions` in `MessageFormatOptions.functions`, together with any custom functions:

```dart
import 'package:messageformat/messageformat.dart';
import 'package:messageformat_datetime/messageformat_datetime.dart';

final mf = MessageFormat(
  'en',
  r'Updated {$when :datetime}',
  options: MessageFormatOptions(functions: dateTimeFunctions),
);
mf.format({'when': DateTime(2006, 1, 2, 15, 4)});
// 'Updated Jan 2, 2006, 3:04 PM'
```

The functions format a `DateTime` or an ISO 8601 date/time literal, such as `|2006-01-02T15:04:06|`, with the CLDR patterns of the *semantic skeleton* that their options map to:

```dart
const options = MessageFormatOptions(
  bidiIsolation: BidiIsolation.none,
  functions: dateTimeFunctions,
);
final when = DateTime(2006, 1, 2, 15, 4);

MessageFormat('en', r'{$when :date length=long}', options: options)
    .format({'when': when}); // 'January 2, 2006'

MessageFormat('de', r'{$when :date fields=weekday length=long}', options: options)
    .format({'when': when}); // 'Montag'

MessageFormat('en', r'{$when :time timeZone=UTC}', options: options)
    .format({'when': DateTime.utc(2006, 1, 2, 15, 4)}); // '3:04 PM'
```

Once the functions are registered, a `DateTime` in a placeholder without a function, such as `{$when}`, is formatted with `:datetime`. Without them, a message that calls one of them reports an `unknown-function` error, and a `DateTime` in a placeholder without a function is formatted with its `toString()`.

## Limits

- Dates use the Gregorian calendar in every locale, and the option `calendar` accepts only `gregory`.
- The default time zone is the platform's local time zone. The option `timeZone` accepts `input` and the time zone identifiers that CLDR knows, such as `UTC` or `America/New_York`. Since time zone data is not included, a value with an offset can be converted only to UTC; converting it to another zone reports a `bad-option` error.
- `timeZoneStyle` shows the offset from GMT, such as `GMT-8`, since time zone names are not included.

## Coming from JavaScript

The JS [`messageformat`](https://www.npmjs.com/package/messageformat) package v4 makes the Draft functions opt-in with `functions: { ...DraftFunctions }`. Here, `functions: {...dateTimeFunctions}` does the same for the date/time functions.

## License

The package is licensed under the [Apache License 2.0](LICENSE). Its locale data is derived from Unicode CLDR, under the [Unicode License v3](https://www.unicode.org/license.txt), whose notice the generated data file carries.
