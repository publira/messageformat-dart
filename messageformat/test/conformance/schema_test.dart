/// Validates the vendored test files against the suite's own JSON schema, so
/// that a bad re-vendor fails loudly.
library;

import 'dart:convert';
import 'dart:io';

import 'package:json_schema/json_schema.dart';
import 'package:test/test.dart';

import 'manifest.dart';

void main() {
  final schema = JsonSchema.create(
    File('$suiteDirectory/schemas/v0/tests.schema.json').readAsStringSync(),
  );

  final files = Directory('$suiteDirectory/tests')
      .listSync(recursive: true)
      .whereType<File>()
      .where((file) => file.path.endsWith('.json'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  test('there are test files to validate', () {
    expect(files, hasLength(expectedCaseCounts.length));
  });

  for (final file in files) {
    final path = file.path.substring('$suiteDirectory/tests/'.length);
    test('$path matches the suite schema', () {
      final results = schema.validate(
        jsonDecode(file.readAsStringSync()),
        validateFormats: true,
      );
      expect(results.errors, isEmpty);
      expect(results.isValid, isTrue);
    });
  }

  group('the validator', () {
    Map<String, Object?> fileWith(Map<String, Object?> test) => {
          'defaultTestProperties': <String, Object?>{'locale': 'en-US'},
          'tests': <Object?>[test],
        };

    test('accepts a minimal file', () {
      final file = fileWith({'src': 'hello', 'exp': 'hello'});
      expect(schema.validate(file).isValid, isTrue);
    });

    test('rejects an unknown test property', () {
      final file = fileWith({'src': 'hello', 'expected': 'hello'});
      expect(schema.validate(file).isValid, isFalse);
    });

    test('rejects an unknown error type', () {
      final file = fileWith({
        'src': 'hello',
        'expErrors': <Object?>[
          <String, Object?>{'type': 'not-an-error'},
        ],
      });
      expect(schema.validate(file).isValid, isFalse);
    });

    test('rejects a test without an assertion', () {
      final file = fileWith({'src': 'hello'});
      expect(schema.validate(file).isValid, isFalse);
    });

    test('rejects a source that is not a string', () {
      final file = fileWith({'src': 42, 'exp': '42'});
      expect(schema.validate(file).isValid, isFalse);
    });
  });
}
