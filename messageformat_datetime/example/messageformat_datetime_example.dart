// The examples from the package README, runnable with
// `dart run example/messageformat_datetime_example.dart`.
//
// `test/readme_test.dart` checks the same messages, so update both when a
// README example changes.
import 'package:messageformat/messageformat.dart';
import 'package:messageformat_datetime/messageformat_datetime.dart';

void main() {
  // Register the date/time functions. A date in the left-to-right message
  // of an English locale is not isolated.
  final updated = MessageFormat(
    'en',
    r'Updated {$when :datetime}',
    options: MessageFormatOptions(functions: dateTimeFunctions),
  );
  print(updated.format({'when': DateTime(2006, 1, 2, 15, 4)}));
  // 'Updated Jan 2, 2006, 3:04 PM'

  // Choose the fields and their length with options.
  const options = MessageFormatOptions(
    bidiIsolation: BidiIsolation.none,
    functions: dateTimeFunctions,
  );
  final when = DateTime(2006, 1, 2, 15, 4);
  print(MessageFormat('en', r'{$when :date length=long}', options: options)
      .format({'when': when})); // 'January 2, 2006'
  print(MessageFormat('de', r'{$when :date fields=weekday length=long}',
          options: options)
      .format({'when': when})); // 'Montag'
  print(MessageFormat('en', r'{$when :time timeZone=UTC}', options: options)
      .format({'when': DateTime.utc(2006, 1, 2, 15, 4)})); // '3:04 PM'
}
