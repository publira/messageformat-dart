/// Runs every case of the MessageFormat WG conformance suite at the pinned
/// tag, one `dart test` case per entry.
///
/// See `manifest.dart` for the pin and for the lists that skip files or
/// only parse them.
library;

import 'package:test/test.dart';

import 'expectations.dart';
import 'manifest.dart';
import 'subject.dart';
import 'suite.dart';
import 'unpaired_surrogates.dart';

void main() {
  final files = loadSuite();

  test('the suite has the expected files and case counts', () {
    expect(
      {for (final file in files) file.path: file.cases.length},
      equals(expectedCaseCounts),
    );
    expect(
      files.fold<int>(0, (sum, file) => sum + file.cases.length),
      expectedTotalCaseCount,
    );
  });

  for (final file in files) {
    _defineGroup(file.path, file.scenario, file.cases);
  }
  _defineGroup(
    unpairedSurrogatesFile,
    'Unpaired surrogates',
    unpairedSurrogateCases,
  );
}

void _defineGroup(String path, String scenario, List<ConformanceCase> cases) {
  final skip = switch ((draftDeferred[path], notYetImplemented[path])) {
    (final reason?, _) => 'Deferred Draft function: $reason',
    (_, final issues?) => 'Not yet implemented; see $issues',
    _ => null,
  };
  group('$path ($scenario)', skip: skip, () {
    for (final testCase in cases) {
      final pending = pendingFunctionsUsedBy(testCase);
      final issues = {for (final name in pending) pendingFunctions[name]};
      test(
        pending.isEmpty
            ? testCase.name
            : '${testCase.name} (parse only until ${issues.join(', ')})',
        tags: [for (final tag in testCase.tags) testTags[tag]!],
        () => pending.isEmpty
            ? checkCase(subject, testCase)
            : checkParse(subject, testCase),
      );
    }
  });
}
