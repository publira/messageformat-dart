/// The two packages release together with the same version; see "Releases"
/// in AGENTS.md. These tests read `messageformat` from the workspace, so
/// they are not published (see .pubignore).
library;

import 'dart:io';

import 'package:messageformat_datetime/messageformat_datetime.dart';
import 'package:test/test.dart';

void main() {
  test('messageformat has the same version', () {
    final pubspec = File('../messageformat/pubspec.yaml').readAsStringSync();
    final version = RegExp(r'^version:\s*(\S+)\s*$', multiLine: true)
        .firstMatch(pubspec)
        ?.group(1);
    expect(version, dateTimePackageVersion);
  });

  test('the dependency on messageformat starts at the same version', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final constraint = RegExp(r'^  messageformat:\s*(\S+)\s*$', multiLine: true)
        .firstMatch(pubspec)
        ?.group(1);
    expect(constraint, '^$dateTimePackageVersion');
  });
}
