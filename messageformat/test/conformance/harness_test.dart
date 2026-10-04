/// Tests of the conformance harness itself, which run while the suite's own
/// cases are still skipped.
library;

import 'dart:io';

import 'package:test/test.dart';

import 'expectations.dart';
import 'manifest.dart';
import 'subject.dart';
import 'suite.dart';
import 'test_functions.dart';
import 'unpaired_surrogates.dart';

void main() {
  group('manifest', () {
    final knownFiles = {...expectedCaseCounts.keys, unpairedSurrogatesFile};

    test('records the vendored tag and commit', () {
      final source = File('$suiteDirectory/SOURCE').readAsStringSync();
      expect(source, contains('Tag: $suiteTag\n'));
      expect(source, contains('Commit: $suiteCommit\n'));
    });

    test('ships the Unicode License v3 with the vendored files', () {
      final license = File('$suiteDirectory/LICENSE').readAsStringSync();
      expect(license, startsWith('UNICODE LICENSE V3'));
      expect(license, contains('SPDX-License-Identifier: Unicode-3.0'));
    });

    test('does not vendor the specification text', () {
      expect(Directory('$suiteDirectory/spec').existsSync(), isFalse);
    });

    test('counts add up to the total', () {
      expect(
        expectedCaseCounts.values.fold<int>(0, (sum, count) => sum + count),
        expectedTotalCaseCount,
      );
    });

    test('skip lists name only known files', () {
      expect(knownFiles, containsAll(notYetImplemented.keys));
      expect(knownFiles, containsAll(draftDeferred.keys));
    });

    test('only Draft function files may be deferred', () {
      expect(draftFunctionFiles, containsAll(draftDeferred.keys));
    });

    test('a file is never on both skip lists', () {
      expect(
        notYetImplemented.keys.toSet().intersection(draftDeferred.keys.toSet()),
        isEmpty,
      );
    });

    test('every tag the suite uses is mapped', () {
      final used = {
        for (final file in loadSuite())
          for (final testCase in file.cases) ...testCase.tags,
      };
      expect(testTags.keys, containsAll(used));
    });

    test('every mapped tag is declared in dart_test.yaml', () {
      final config = File('dart_test.yaml').readAsStringSync();
      for (final tag in testTags.values) {
        expect(config, contains('\n  $tag:'));
      }
    });
  });

  group('loader', () {
    test('applies defaults and lets a test replace them', () {
      final testCase = ConformanceCase.fromJson(
        'example.json',
        3,
        {
          'locale': 'en-US',
          'bidiIsolation': 'none',
          'expErrors': <Object?>[],
        },
        {
          'src': '{\$x}',
          'locale': 'fr',
          'params': <Object?>[
            {'name': 'x', 'value': 1.5},
            {'name': 'dt', 'type': 'datetime', 'value': '2006-01-02T15:04:06'},
          ],
          'expErrors': <Object?>[
            {'type': 'bad-operand'},
          ],
        },
      );
      expect(testCase.locale, 'fr');
      expect(testCase.bidiIsolation, 'none');
      expect(testCase.params, {
        'x': 1.5,
        'dt': DateTime(2006, 1, 2, 15, 4, 6),
      });
      expect(testCase.expErrors, ['bad-operand']);
      expect(testCase.name, r'#3 {$x} [fr]');
    });

    test('leaves bidiIsolation unset when the file does not set it', () {
      final file = loadSuite().singleWhere(
        (file) => file.path == 'pattern-selection.json',
      );
      expect(file.cases.map((c) => c.bidiIsolation), everyElement(isNull));
      expect(file.cases.map((c) => c.locale), everyElement('und'));
    });

    test('reads files in subdirectories', () {
      expect(
        loadSuite().map((file) => file.path),
        contains('functions/number.json'),
      );
    });

    test('escapes invisible characters in names', () {
      expect(
        escapeForName('a\u2068b\u200fc\n\ud800\ud83d\ude00'),
        r'a\u2068b\u200fc\u000a\ud800' '\u{1f600}',
      );
    });
  });

  group('unpaired surrogate cases', () {
    test('each invalid case contains an unpaired surrogate', () {
      final invalid = unpairedSurrogateCases.where(
        (c) => c.expErrors?.contains('syntax-error') ?? false,
      );
      expect(invalid, isNotEmpty);
      for (final testCase in invalid) {
        expect(escapeForName(testCase.src), matches(r'\\ud[89a-f]'));
      }
    });
  });

  group('checkCase', () {
    final cases = [
      for (final file in loadSuite()) ...file.cases,
      ...unpairedSurrogateCases,
    ];

    test('accepts output that meets every assertion of every case', () {
      for (final testCase in cases) {
        checkCase(_FakeSubject(testCase), testCase);
      }
    });

    test('rejects a wrong string', () {
      final testCase = cases.firstWhere((c) => c.exp != null);
      expect(
        () => checkCase(
            _FakeSubject(testCase, value: '${testCase.exp}!'), testCase),
        throwsA(isA<TestFailure>()),
      );
    });

    test('rejects a missing string', () {
      final testCase = cases.firstWhere((c) => c.exp != null);
      expect(
        () => checkCase(_FakeSubject(testCase, value: null), testCase),
        throwsA(isA<TestFailure>()),
      );
    });

    test('rejects an unexpected error', () {
      final testCase = cases.firstWhere((c) => c.expErrors?.isEmpty ?? true);
      expect(
        () =>
            checkCase(_FakeSubject(testCase, errors: ['bad-option']), testCase),
        throwsA(isA<TestFailure>()),
      );
    });

    test('rejects a missing error', () {
      final testCase =
          cases.firstWhere((c) => c.expErrors?.isNotEmpty ?? false);
      expect(
        () => checkCase(_FakeSubject(testCase, errors: []), testCase),
        throwsA(isA<TestFailure>()),
      );
    });

    test('rejects wrong parts', () {
      final testCase = cases.firstWhere((c) => c.expParts != null);
      expect(
        () => checkCase(_FakeSubject(testCase, parts: []), testCase),
        throwsA(isA<TestFailure>()),
      );
    });

    test('checks errors from formatToParts too', () {
      final testCase = cases.firstWhere(
        (c) => c.expParts != null && (c.expErrors?.isNotEmpty ?? false),
      );
      expect(
        () => checkCase(_FakeSubject(testCase, partsErrors: []), testCase),
        throwsA(isA<TestFailure>()),
      );
    });
  });

  group('containsSubset', () {
    test('allows extra keys in maps', () {
      expect(
        {'type': 'string', 'value': 'a', 'locale': 'en-US'},
        containsSubset({'type': 'string', 'value': 'a'}),
      );
    });

    test('requires every expected key', () {
      expect(
        {'type': 'string'},
        isNot(containsSubset({'type': 'string', 'value': 'a'})),
      );
    });

    test('requires lists of the same length', () {
      expect([1, 2], isNot(containsSubset([1])));
      expect([1], isNot(containsSubset([1, 2])));
    });

    test('compares nested parts', () {
      final actual = [
        {
          'type': 'number',
          'parts': [
            {'type': 'integer', 'value': '42'},
          ],
        },
      ];
      expect(
        actual,
        containsSubset([
          {
            'type': 'number',
            'parts': [
              {'type': 'integer', 'value': '42'},
            ],
          },
        ]),
      );
      expect(
        actual,
        isNot(containsSubset([
          {
            'type': 'number',
            'parts': [
              {'type': 'integer', 'value': '43'},
            ],
          },
        ])),
      );
    });

    test('rejects null output', () {
      expect(null, isNot(containsSubset(<Object?>[])));
    });
  });

  group('hasErrorTypes', () {
    test('ignores order', () {
      expect(['bad-operand', 'unresolved-variable'],
          hasErrorTypes(['unresolved-variable', 'bad-operand']));
    });

    test('counts repeated errors', () {
      expect(
          ['bad-option'], isNot(hasErrorTypes(['bad-option', 'bad-option'])));
    });

    test('treats a missing list as no errors', () {
      expect(<String>[], hasErrorTypes(null));
      expect(['bad-option'], isNot(hasErrorTypes(null)));
    });
  });

  group('test functions', () {
    final errors = <TestFunctionError>[];
    setUp(errors.clear);

    TestFunctionValue resolve(
      Object? operand, [
      Map<String, Object?> options = const {},
      TestFunction function = TestFunction.function,
    ]) =>
        TestFunctionValue.resolve(
          function,
          operand,
          options,
          onError: errors.add,
        );

    Matcher throwsTestFunctionError(String type) => throwsA(
          isA<TestFunctionError>().having((e) => e.type, 'type', type),
        );

    test('accept numbers and number-literal strings', () {
      expect(resolve(42).input, 42);
      expect(resolve(-1.5).input, -1.5);
      expect(resolve('1').input, 1);
      expect(resolve('-0.5e1').input, -5);
      expect(errors, isEmpty);
    });

    test('reject other operands with bad-operand', () {
      for (final operand in [
        null,
        'C:\\',
        '1.',
        '01',
        '+1',
        ' 1',
        'NaN',
        double.infinity,
        true,
      ]) {
        expect(
          () => resolve(operand),
          throwsTestFunctionError('bad-operand'),
          reason: '$operand',
        );
      }
    });

    test('format integers and one decimal place', () {
      expect(resolve(42).format(), '42');
      expect(resolve(-1.25).format(), '-1');
      expect(resolve(-1.25, {'decimalPlaces': 1}).format(), '-1.2');
      expect(resolve('1.97', {'decimalPlaces': '1'}).format(), '1.9');
      expect(resolve(-0.5).formatToParts(), [
        (type: 'neg', value: '-'),
        (type: 'int', value: '0'),
      ]);
    });

    test('reject a decimalPlaces other than 0 or 1 with bad-option', () {
      for (final value in [2, '9', -1, 0.5, 'one']) {
        expect(
          () => resolve(1, {'decimalPlaces': value}),
          throwsTestFunctionError('bad-option'),
          reason: '$value',
        );
      }
    });

    test('report an invalid fails option and keep resolving', () {
      final value = resolve(1, {'fails': 'sometimes'});
      expect(errors.map((e) => e.type), ['bad-option']);
      expect(value.format(), '1');
      expect(value.match('1'), isTrue);
    });

    test('fail selection or formatting on request', () {
      final failsFormat = resolve(1, {'fails': 'format'});
      expect(failsFormat.format, throwsTestFunctionError('bad-option'));
      expect(failsFormat.match('1'), isTrue);

      final failsSelect = resolve(1, {'fails': 'select'});
      expect(
          () => failsSelect.match('1'), throwsTestFunctionError('bad-option'));
      expect(failsSelect.format(), '1');

      final failsAlways = resolve(1, {'fails': 'always'});
      expect(failsAlways.format, throwsTestFunctionError('bad-option'));
      expect(
          () => failsAlways.match('1'), throwsTestFunctionError('bad-option'));

      expect(resolve(1, {'fails': 'never'}).format(), '1');
      expect(errors, isEmpty);
    });

    test('match 1 and, with one decimal place, 1.0', () {
      final integer = resolve(1, {}, TestFunction.select);
      expect(integer.match('1'), isTrue);
      expect(integer.match('1.0'), isFalse);
      expect(integer.match('2'), isFalse);

      final decimal = resolve(1, {'decimalPlaces': 1}, TestFunction.select);
      expect(decimal.match('1'), isTrue);
      expect(decimal.match('1.0'), isTrue);

      expect(resolve(0, {}, TestFunction.select).match('0'), isFalse);
    });

    test('prefer 1.0 over other keys', () {
      final value = resolve(1, {'decimalPlaces': 1}, TestFunction.select);
      expect(value.betterThan('1.0', '1'), isTrue);
      expect(value.betterThan('1', '1.0'), isFalse);
    });

    test('inherit settings from a test-function operand', () {
      final inner = resolve(1, {'decimalPlaces': 1, 'fails': 'format'});
      final outer = resolve(inner, {}, TestFunction.select);
      expect(outer.input, 1);
      expect(outer.decimalPlaces, 1);
      expect(outer.failsFormat, isTrue);
      expect(outer.match('1.0'), isTrue);

      final overridden = resolve(inner, {'decimalPlaces': 0});
      expect(overridden.decimalPlaces, 0);
    });

    test('use the input of a test value given as an option value', () {
      final option = resolve(1);
      expect(resolve(5, {'decimalPlaces': option}).decimalPlaces, 1);
    });

    test('enforce what each function can do', () {
      expect(TestFunction.function.canFormat, isTrue);
      expect(TestFunction.function.canSelect, isTrue);
      expect(TestFunction.select.canFormat, isFalse);
      expect(TestFunction.format.canSelect, isFalse);
      expect(resolve(1, {}, TestFunction.select).format, throwsStateError);
      expect(
        () => resolve(1, {}, TestFunction.format).match('1'),
        throwsStateError,
      );
    });
  });
}

/// A subject that answers one case with exactly what it expects, adding a
/// property to each part as an implementation may, unless told otherwise.
final class _FakeSubject implements ConformanceSubject {
  _FakeSubject(
    ConformanceCase testCase, {
    Object? value = _expected,
    List<String>? errors,
    List<Map<String, Object?>>? parts,
    List<String>? partsErrors,
  })  : _value = identical(value, _expected) ? testCase.exp : value as String?,
        _errors = errors ?? testCase.expErrors ?? const [],
        _parts = parts ??
            [
              for (final part
                  in testCase.expParts ?? const <Map<String, Object?>>[])
                {...part, 'extra': true},
            ],
        _partsErrors = partsErrors ?? errors ?? testCase.expErrors ?? const [];

  static const _expected = Object();

  final String? _value;
  final List<String> _errors;
  final List<Map<String, Object?>> _parts;
  final List<String> _partsErrors;

  @override
  FormatOutcome format({
    required String locale,
    required String src,
    required String? bidiIsolation,
    required Map<String, Object?>? params,
  }) =>
      (value: _value, errors: _errors);

  @override
  PartsOutcome formatToParts({
    required String locale,
    required String src,
    required String? bidiIsolation,
    required Map<String, Object?>? params,
  }) =>
      (parts: _parts, errors: _partsErrors);
}
