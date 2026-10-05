import 'dart:io';

import 'package:messageformat/messageformat.dart';
import 'package:test/test.dart';

void main() {
  test('exposes the version in pubspec.yaml', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final version = RegExp(r'^version: (\S+)$', multiLine: true)
        .firstMatch(pubspec)
        ?.group(1);
    expect(packageVersion, version);
  });

  test('has a changelog entry for the version', () {
    final changelog = File('CHANGELOG.md').readAsLinesSync();
    expect(changelog.first, '## $packageVersion');
  });
}
