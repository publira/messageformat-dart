/// Feeds generated sources to the parser to check that every failure is a
/// typed MessageFormat error, and that every message it accepts survives a
/// round trip through [stringifyMessage].
library;

import 'dart:math';

import 'package:messageformat/messageformat.dart';
import 'package:test/test.dart';

import 'conformance/suite.dart';

/// Fragments that exercise the grammar: sigils, keywords, whitespace, bidi
/// marks, characters the grammar excludes, and unusual code points.
const _fragments = [
  '{', '}', '{{', '}}', '|', r'\', '\$', ':', '#', '/', '@', '=', '*', '.', //
  '.input', '.local', '.match', ' ', '\t', '\n', '\r', '\u3000', '\u00a0',
  '\u061c', '\u200e', '\u200f', '\u2066', '\u2069', 'a', 'x', 'ns', '1',
  '-', '_', '+', '\u0000', '\ud800', '\udc00', '\u{1f600}', '\u{10fffe}',
  '\ufffe', '\u00e9', 'D\u0323\u0307', '\u1e0c\u0307', ':string', '\$x',
  '|a b|', '{\$x :f}', '{#b}', '{/b}', '{#b/}', ' * ', '{{}}',
];

void main() {
  final random = Random(20261004);

  void check(String source) {
    final Message message;
    try {
      message = parseMessage(source, onError: (error) {
        expect(error.start, inInclusiveRange(0, source.length));
        expect(error.end, inInclusiveRange(error.start!, source.length));
      });
    } on MessageSyntaxError catch (error) {
      expect(error.start, inInclusiveRange(0, source.length));
      expect(error.end, inInclusiveRange(error.start!, source.length));
      return;
    }
    final written = stringifyMessage(message);
    expect(
      parseMessage(written, onError: (_) {}),
      message,
      reason: 'round trip of ${escapeForName(source)} '
          'through ${escapeForName(written)}',
    );
  }

  test('random sequences of grammar fragments', () {
    for (var i = 0; i < 20000; i++) {
      final buffer = StringBuffer();
      for (var n = random.nextInt(24); n > 0; n--) {
        buffer.write(_fragments[random.nextInt(_fragments.length)]);
      }
      check(buffer.toString());
    }
  });

  test('random code units', () {
    for (var i = 0; i < 20000; i++) {
      check(String.fromCharCodes([
        for (var n = random.nextInt(16); n > 0; n--)
          random.nextBool() ? random.nextInt(0x80) : random.nextInt(0x10000),
      ]));
    }
  });

  test('mutations of the suite sources', () {
    final sources = [
      for (final file in loadSuite())
        for (final testCase in file.cases) testCase.src,
    ];
    for (var i = 0; i < 20000; i++) {
      final units = sources[random.nextInt(sources.length)].codeUnits.toList();
      for (var n = 1 + random.nextInt(3); n > 0; n--) {
        final at = random.nextInt(units.length + 1);
        switch (random.nextInt(3)) {
          case 0 when at < units.length:
            units.removeAt(at);
          case 1 when at < units.length:
            units[at] =
                _fragments[random.nextInt(_fragments.length)].codeUnitAt(0);
          default:
            units.insertAll(
              at,
              _fragments[random.nextInt(_fragments.length)].codeUnits,
            );
        }
      }
      check(String.fromCharCodes(units));
    }
  });
}
