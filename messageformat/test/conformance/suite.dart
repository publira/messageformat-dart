/// Loads the vendored conformance suite into [ConformanceCase] values.
library;

import 'dart:convert';
import 'dart:io';

import 'manifest.dart';

/// One test file of the suite.
final class ConformanceFile {
  ConformanceFile(this.path, this.scenario, this.cases);

  /// The path relative to the suite's `tests/` directory, using `/`.
  final String path;

  /// The file's `scenario`, or [path] when it has none.
  final String scenario;

  final List<ConformanceCase> cases;
}

/// One test case, with the file's `defaultTestProperties` applied.
final class ConformanceCase {
  ConformanceCase({
    required this.file,
    required this.index,
    required this.locale,
    required this.src,
    this.description,
    this.bidiIsolation,
    this.params,
    this.tags = const [],
    this.exp,
    this.expParts,
    this.expErrors,
  });

  /// Builds a case from a JSON test object and its file's defaults.
  ///
  /// A property on the test replaces the default of the same name, as the
  /// schema describes; lists such as `expErrors` are not merged.
  factory ConformanceCase.fromJson(
    String file,
    int index,
    Map<String, Object?> defaults,
    Map<String, Object?> test,
  ) {
    final merged = {...defaults, ...test};
    final params = merged['params'] as List<Object?>?;
    final expErrors = merged['expErrors'] as List<Object?>?;
    return ConformanceCase(
      file: file,
      index: index,
      description: merged['description'] as String?,
      locale: merged['locale'] as String,
      src: merged['src'] as String,
      bidiIsolation: merged['bidiIsolation'] as String?,
      params: params == null
          ? null
          : {
              for (final param in params.cast<Map<String, Object?>>())
                param['name'] as String: _paramValue(param),
            },
      tags: (merged['tags'] as List<Object?>?)?.cast<String>() ?? const [],
      exp: merged['exp'] as String?,
      expParts:
          (merged['expParts'] as List<Object?>?)?.cast<Map<String, Object?>>(),
      expErrors: expErrors
          ?.cast<Map<String, Object?>>()
          .map((error) => error['type'] as String)
          .toList(),
    );
  }

  /// The file this case comes from, relative to the suite's `tests/`.
  final String file;

  /// The zero-based position of the case in its file.
  final int index;

  final String? description;

  /// The locale to format with.
  final String locale;

  /// The message source.
  final String src;

  /// `'default'` or `'none'`, or `null` to use the implementation's default,
  /// which the spec requires to be the Default Bidi Strategy.
  final String? bidiIsolation;

  /// The input mapping, or `null` when the case passes no parameters.
  ///
  /// A parameter with `"type": "datetime"` is converted to a [DateTime]
  /// with [DateTime.parse]. Other values are passed as JSON decodes them.
  final Map<String, Object?>? params;

  /// The suite's tags, such as `u:dir`. Tagged cases still run.
  final List<String> tags;

  /// The expected result of formatting to a string, if asserted.
  final String? exp;

  /// The expected result of formatting to parts, if asserted.
  final List<Map<String, Object?>>? expParts;

  /// The expected error types. `null` and an empty list both mean that the
  /// message must format without errors.
  final List<String>? expErrors;

  /// A readable test name: the description if there is one, otherwise the
  /// source, with invisible and bidi characters escaped.
  String get name {
    final label = escapeForName(description ?? src);
    return locale == 'en-US' ? '#$index $label' : '#$index $label [$locale]';
  }

  static Object? _paramValue(Map<String, Object?> param) {
    final value = param['value'];
    if (param['type'] == 'datetime') return DateTime.parse(value as String);
    return value;
  }
}

/// Escapes characters that would make a test name unreadable or reorder it
/// in a terminal: controls, bidi marks and isolates, and lone surrogates.
String escapeForName(String text) {
  final buffer = StringBuffer();
  final units = text.codeUnits;
  for (var i = 0; i < units.length; i++) {
    final unit = units[i];
    if (_isHighSurrogate(unit) &&
        i + 1 < units.length &&
        _isLowSurrogate(units[i + 1])) {
      buffer
        ..writeCharCode(unit)
        ..writeCharCode(units[++i]);
      continue;
    }
    final escape = unit < 0x20 ||
        unit == 0x7f ||
        unit == 0x061c ||
        (unit >= 0x200e && unit <= 0x200f) ||
        (unit >= 0x202a && unit <= 0x202e) ||
        (unit >= 0x2066 && unit <= 0x2069) ||
        _isHighSurrogate(unit) ||
        _isLowSurrogate(unit);
    if (escape) {
      buffer.write('\\u${unit.toRadixString(16).padLeft(4, '0')}');
    } else {
      buffer.writeCharCode(unit);
    }
  }
  return buffer.toString();
}

bool _isHighSurrogate(int unit) => unit >= 0xd800 && unit <= 0xdbff;

bool _isLowSurrogate(int unit) => unit >= 0xdc00 && unit <= 0xdfff;

/// Reads every `*.json` file under the suite's `tests/` directory.
List<ConformanceFile> loadSuite([String directory = suiteDirectory]) {
  final root = Directory('$directory/tests');
  final files = root
      .listSync(recursive: true)
      .whereType<File>()
      .where((file) => file.path.endsWith('.json'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  return [
    for (final file in files)
      _loadFile(
        file.path.substring(root.path.length + 1).replaceAll(r'\', '/'),
        jsonDecode(file.readAsStringSync()) as Map<String, Object?>,
      ),
  ];
}

ConformanceFile _loadFile(String path, Map<String, Object?> json) {
  final defaults =
      json['defaultTestProperties'] as Map<String, Object?>? ?? const {};
  final tests = (json['tests'] as List<Object?>).cast<Map<String, Object?>>();
  return ConformanceFile(path, json['scenario'] as String? ?? path, [
    for (var i = 0; i < tests.length; i++)
      ConformanceCase.fromJson(path, i, defaults, tests[i]),
  ]);
}
