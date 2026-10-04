/// Compares implementation output with the suite's assertions.
library;

import 'package:test/test.dart';

import 'manifest.dart';
import 'subject.dart';
import 'suite.dart';

/// Matches a value that contains [expected].
///
/// Maps match when every key of [expected] is present and its value matches
/// recursively; other keys are allowed, since the suite lists only the part
/// properties it asserts (an expression part may carry `locale`, `dir`, and
/// so on). Lists match element by element and must have the same length.
/// Other values must be equal.
///
/// This follows the reference harness of the JS `messageformat` package,
/// which compares `expParts` with `toMatchObject`.
Matcher containsSubset(Object? expected) => _SubsetMatcher(expected);

/// Matches a list of error types that equals [expected] in any order.
///
/// The spec does not define the order in which errors are reported, so the
/// harness compares them as multisets. `null` expects no errors.
Matcher hasErrorTypes(List<String>? expected) =>
    unorderedEquals(expected ?? const <String>[]);

/// Checks [subject] against every assertion of [testCase].
///
/// `exp` is compared with the string from `format`, and `expParts`, when
/// present, with the parts from `formatToParts`. The errors of each call
/// must match `expErrors`; when that is absent or empty, there must be none.
void checkCase(ConformanceSubject subject, ConformanceCase testCase) {
  final formatted = subject.format(
    locale: testCase.locale,
    src: testCase.src,
    bidiIsolation: testCase.bidiIsolation,
    params: testCase.params,
  );
  if (testCase.exp case final exp?) {
    expect(formatted.value, exp, reason: 'format()');
  }
  expect(
    formatted.errors,
    hasErrorTypes(testCase.expErrors),
    reason: 'errors from format()',
  );

  if (testCase.expParts case final expParts?) {
    final parts = subject.formatToParts(
      locale: testCase.locale,
      src: testCase.src,
      bidiIsolation: testCase.bidiIsolation,
      params: testCase.params,
    );
    expect(parts.parts, containsSubset(expParts), reason: 'formatToParts()');
    expect(
      parts.errors,
      hasErrorTypes(testCase.expErrors),
      reason: 'errors from formatToParts()',
    );
  }
}

/// Checks that parsing [testCase] with [subject] reports exactly the Syntax
/// Errors and Data Model Errors that its `expErrors` lists.
///
/// The other expected errors, and the expected output, need formatting and
/// are not checked. See `parseOnly` in `manifest.dart`.
void checkParse(ConformanceSubject subject, ConformanceCase testCase) {
  expect(
    subject.parse(testCase.src),
    hasErrorTypes([
      for (final type in testCase.expErrors ?? const <String>[])
        if (staticErrorTypes.contains(type)) type,
    ]),
    reason: 'errors from parse()',
  );
}

final class _SubsetMatcher extends Matcher {
  const _SubsetMatcher(this._expected);

  final Object? _expected;

  @override
  bool matches(Object? item, Map<Object?, Object?> matchState) {
    final mismatch = _mismatch(item, _expected, r'$');
    if (mismatch != null) matchState['mismatch'] = mismatch;
    return mismatch == null;
  }

  @override
  Description describe(Description description) =>
      description.add('contains ').addDescriptionOf(_expected);

  @override
  Description describeMismatch(
    Object? item,
    Description mismatchDescription,
    Map<Object?, Object?> matchState,
    bool verbose,
  ) =>
      mismatchDescription.add(matchState['mismatch'] as String);

  static String? _mismatch(Object? actual, Object? expected, String path) {
    if (expected is Map<Object?, Object?>) {
      if (actual is! Map<Object?, Object?>) {
        return 'at $path expected a map but was ${_show(actual)}';
      }
      for (final MapEntry(:key, :value) in expected.entries) {
        if (!actual.containsKey(key)) return 'at $path is missing key "$key"';
        final mismatch = _mismatch(actual[key], value, '$path.$key');
        if (mismatch != null) return mismatch;
      }
      return null;
    }
    if (expected is List<Object?>) {
      if (actual is! List<Object?>) {
        return 'at $path expected a list but was ${_show(actual)}';
      }
      if (actual.length != expected.length) {
        return 'at $path expected ${expected.length} elements '
            'but had ${actual.length}';
      }
      for (var i = 0; i < expected.length; i++) {
        final mismatch = _mismatch(actual[i], expected[i], '$path[$i]');
        if (mismatch != null) return mismatch;
      }
      return null;
    }
    if (actual != expected) {
      return 'at $path expected ${_show(expected)} but was ${_show(actual)}';
    }
    return null;
  }

  static String _show(Object? value) => value is String ? '"$value"' : '$value';
}
