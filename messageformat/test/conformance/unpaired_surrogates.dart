/// Cases the suite's README asks UTF-16 implementations to add.
///
/// JSON cannot carry unpaired surrogate code points, so the vendored suite
/// has no tests for them. Dart strings are UTF-16 and can hold them.
///
/// The ABNF admits surrogate code points in some places and not in others.
/// `name-start` and `name-char` omit them, so an unpaired surrogate in a
/// name or an unquoted literal is a Syntax Error, as in the README's example.
/// `text-char`, `simple-start-char`, and `quoted-char` include them, and the
/// syntax section notes that text and quoted literals allow unpaired
/// surrogates for compatibility with UTF-16, so those messages are valid.
library;

import 'manifest.dart';
import 'suite.dart';

/// Sources with an unpaired surrogate where the ABNF admits none.
const _invalidSources = [
  // The example given in the README: an unquoted literal.
  '{\ud800}',
  // Unquoted literals, after a name character and before a function.
  '{a\ud800}',
  '{\udc00 :string}',
  // A variable name.
  '{\$x\ud800}',
  // Function, option, attribute, and markup identifiers.
  '{:f\ud800}',
  '{:string \udbff=a}',
  '{a @\udc00}',
  '{#b\ud800}',
  // A low surrogate followed by a high one is two unpaired surrogates.
  '{a\udc00\ud800}',
  // An unquoted literal as an option value and as a variant key.
  '{|a| :string opt=\udc00}',
  '.input {\$x :string} .match \$x \ud800 {{a}} * {{b}}',
];

/// Sources with an unpaired surrogate where the ABNF admits one, with the
/// parameters and the output that formatting them must produce.
final _validCases = <(String, Map<String, Object?>?, String)>[
  // Simple-message text, including its first character.
  ('\ud800', null, '\ud800'),
  ('a\udc00b', null, 'a\udc00b'),
  ('a\udbff', null, 'a\udbff'),
  ('\udc00\ud800', null, '\udc00\ud800'),
  // Quoted-pattern text.
  ('{{\udfff}}', null, '\udfff'),
  // Quoted literals as an operand, an option value, and a variant key.
  ('{|\ud800|}', null, '\ud800'),
  ('{|a| :string opt=|\udc00|}', null, 'a'),
  (
    '.input {\$x :string} .match \$x |\ud800| {{a}} * {{b}}',
    {'x': '\ud800'},
    'a',
  ),
  // A well-formed surrogate pair is a single code point everywhere.
  ('emoji {😀} {|😀|} {\$😀}', {'😀': '\u{1f600}'}, 'emoji 😀 😀 😀'),
];

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
  for (final (index, (src, params, exp)) in _validCases.indexed)
    ConformanceCase(
      file: unpairedSurrogatesFile,
      index: _invalidSources.length + index,
      locale: 'en-US',
      src: src,
      bidiIsolation: 'none',
      params: params,
      exp: exp,
    ),
];
