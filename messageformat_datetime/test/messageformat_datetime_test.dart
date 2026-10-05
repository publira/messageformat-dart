import 'dart:io';

import 'package:messageformat_datetime/messageformat_datetime.dart';
import 'package:test/test.dart';

void main() {
  // A release sets all three together; see "Releases" in AGENTS.md.
  group('the release version', () {
    test('of pubspec.yaml is dateTimePackageVersion', () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      final version = RegExp(r'^version:\s*(\S+)\s*$', multiLine: true)
          .firstMatch(pubspec)
          ?.group(1);
      expect(version, dateTimePackageVersion);
    });

    test('heads CHANGELOG.md', () {
      final changelog = File('CHANGELOG.md').readAsLinesSync();
      final heading = changelog.firstWhere(
        (line) => line.startsWith('## '),
        orElse: () => '',
      );
      expect(heading, '## $dateTimePackageVersion');
    });
  });
}
