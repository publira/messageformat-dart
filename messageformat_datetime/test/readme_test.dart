/// The examples in README.md and example/, with the results the README
/// states. Update the README when one of these changes.
library;

import 'dart:async';

import 'package:messageformat/messageformat.dart';
import 'package:messageformat_datetime/messageformat_datetime.dart';
import 'package:test/test.dart';

import '../example/messageformat_datetime_example.dart' as example;

const _options = MessageFormatOptions(
  bidiIsolation: BidiIsolation.none,
  functions: dateTimeFunctions,
);

final _when = DateTime(2006, 1, 2, 15, 4);

void main() {
  test('registering the functions', () {
    final mf = MessageFormat(
      'en',
      r'Updated {$when :datetime}',
      options: const MessageFormatOptions(functions: dateTimeFunctions),
    );
    expect(mf.format({'when': _when}), 'Updated Jan 2, 2006, 3:04 PM');
  });

  test('options', () {
    expect(
      MessageFormat('en', r'{$when :date length=long}', options: _options)
          .format({'when': _when}),
      'January 2, 2006',
    );
    expect(
      MessageFormat('de', r'{$when :date fields=weekday length=long}',
              options: _options)
          .format({'when': _when}),
      'Montag',
    );
    expect(
      MessageFormat('en', r'{$when :time timeZone=UTC}', options: _options)
          .format({'when': DateTime.utc(2006, 1, 2, 15, 4)}),
      '3:04 PM',
    );
  });

  test('a DateTime without a function', () {
    expect(
      MessageFormat('en', r'{$when}', options: _options)
          .format({'when': _when}),
      'Jan 2, 2006, 3:04 PM',
    );

    const none = MessageFormatOptions(bidiIsolation: BidiIsolation.none);
    final errors = <MessageError>[];
    expect(
      MessageFormat('en', r'{$when :date}', options: none)
          .format({'when': _when}, errors.add),
      r'{$when}',
    );
    expect(errors.single.type, 'unknown-function');
    expect(
      MessageFormat('en', r'{$when}', options: none).format({'when': _when}),
      _when.toString(),
    );
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
      'Updated Jan 2, 2006, 3:04 PM',
      'January 2, 2006',
      'Montag',
      '3:04 PM',
    ]);
  });
}
