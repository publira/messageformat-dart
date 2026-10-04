/// Cases the suite's README asks UTF-16 implementations to add.
///
/// JSON cannot carry unpaired surrogate code points, so the vendored suite
/// has no tests for them. Dart strings are UTF-16 and can hold them, and the
/// ABNF admits no surrogate code point in text, literals, or names, so each
/// of these must be a Syntax Error.
library;

import 'manifest.dart';
import 'suite.dart';

/// Sources containing an unpaired surrogate.
const _invalidSources = [
  // The example given in the README.
  '{\ud800}',
  // Simple-message text.
  '\ud800',
  'a\udc00b',
  'a\udbff',
  // A low surrogate followed by a high one is two unpaired surrogates.
  '\udc00\ud800',
  // Quoted-pattern text.
  '{{\udfff}}',
  // Quoted literals as an operand, an option value, and a variant key.
  '{|\ud800|}',
  '{|a| :string opt=|\udc00|}',
  '.input {\$x :string} .match \$x |\ud800| {{a}} * {{b}}',
  // Unquoted literals.
  '{a\ud800}',
  '{\udc00 :string}',
  // A variable name.
  '{\$x\ud800}',
];

/// A source with a well-formed surrogate pair, which must not be rejected.
const _validSource = 'emoji {😀} {|😀|}';

/// The harness's unpaired-surrogate cases, reported under
/// [unpairedSurrogatesFile].
final List<ConformanceCase> unpairedSurrogateCases = [
  for (final (index, src) in _invalidSources.indexed)
    ConformanceCase(
      file: unpairedSurrogatesFile,
      index: index,
      locale: 'en-US',
      src: src,
      expErrors: const ['syntax-error'],
    ),
  ConformanceCase(
    file: unpairedSurrogatesFile,
    index: _invalidSources.length,
    description: 'paired surrogates are accepted',
    locale: 'en-US',
    src: _validSource,
    bidiIsolation: 'none',
    exp: 'emoji \u{1f600} \u{1f600}',
  ),
];
