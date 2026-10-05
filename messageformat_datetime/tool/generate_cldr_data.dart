// Generates lib/src/date_data.dart from Unicode CLDR data.
//
// Usage: dart run tool/generate_cldr_data.dart
//
// The data comes from the JSON form of the CLDR release that matches the
// pinned LDML version ([cldrJsonVersion]), as published to npm by the CLDR
// project as `cldr-core`, `cldr-dates-full`, and `cldr-bcp47`. It is keyed
// by the same locales as the number data of package:messageformat, whose
// generator (../messageformat/tool/generate_cldr_data.dart) finds their
// parents in the same way, so that `CldrLocale.chain` finds it.
// Moving the pin (#10) updates the version and reruns this script.

import 'dart:convert';
import 'dart:io';

/// The version of the CLDR JSON packages: the JSON form of CLDR
/// `release-48-2`, the release of the pinned LDML version.
const cldrJsonVersion = '48.2.0';

const _registry = 'https://registry.npmjs.org';

Future<void> main() async {
  final core = await _package('cldr-core');
  final dates = await _package('cldr-dates-full');
  final bcp47 = await _package('cldr-bcp47');
  Object? json(Map<String, String> files, String path) =>
      jsonDecode(files['package/$path'] ?? (throw StateError('No $path')));

  final license = core['package/LICENSE']!;
  final available = [
    for (final locale in _path(
            json(core, 'availableLocales.json'), ['availableLocales', 'full'])
        as List<Object?>)
      locale as String,
  ]..sort();
  final supplemental = {
    for (final name in [
      'dayPeriods',
      'likelySubtags',
      'parentLocales',
      'timeData',
    ])
      name: _path(json(core, 'supplemental/$name.json'), ['supplemental'])
          as Map<String, Object?>,
  };

  final likely =
      _strings(_path(supplemental['likelySubtags'], ['likelySubtags']));
  String likelyScript(String tag) => likely[tag]!.split('-')[1];

  // Parent locales: the explicit ones, then the rule that a locale with a
  // script other than its language's likely script inherits from root.
  final explicitParents = _strings(
      _path(supplemental['parentLocales'], ['parentLocales', 'parentLocale']));
  String parentOf(String locale) {
    if (explicitParents[locale] case final parent?) return parent;
    final subtags = locale.split('-');
    if (subtags.length == 1) return 'und';
    if (subtags.length == 2 &&
        subtags[1].length == 4 &&
        likely.containsKey(subtags[0]) &&
        likelyScript(subtags[0]) != subtags[1]) {
      return 'und';
    }
    return subtags.sublist(0, subtags.length - 1).join('-');
  }

  // The nearest ancestor with data of each locale other than `und`: default
  // content locales, such as `ca-ES`, have none of their own.
  final withData = available.toSet();
  final dataParents = <String, String>{};
  for (final locale in available) {
    if (locale == 'und') continue;
    var parent = parentOf(locale);
    while (!withData.contains(parent)) {
      parent = parentOf(parent);
    }
    dataParents[locale] = parent;
  }

  final notice = _notice(license);
  // The date data of each locale, kept where it differs from that of its
  // parent.
  final dateFields = {
    for (final locale in available)
      locale: _dateFields(
        _path(json(dates, 'main/$locale/ca-gregorian.json'), [
          'main',
          locale,
          'dates',
          'calendars',
          'gregorian'
        ]) as Map<String, Object?>,
        _path(json(dates, 'main/$locale/timeZoneNames.json'),
            ['main', locale, 'dates', 'timeZoneNames']) as Map<String, Object?>,
      ),
  };
  final dateDeltas = <String, Map<String, String>>{};
  for (final locale in available) {
    final own = dateFields[locale]!;
    final parent = dataParents[locale];
    if (parent == null) {
      dateDeltas[locale] = own;
      continue;
    }
    final inherited = dateFields[parent]!;
    for (final key in inherited.keys) {
      if (!own.containsKey(key)) {
        stderr.writeln('warning: $locale lacks $key of $parent');
      }
    }
    dateDeltas[locale] = {
      for (final MapEntry(:key, :value) in own.entries)
        if (inherited[key] != value) key: value,
    };
  }

  // The likely region of each locale without one, which selects its
  // preferred hour cycles. The root locale uses those of the world.
  final localeRegions = <String, String>{
    for (final locale in available)
      if (locale == 'und')
        locale: '001'
      else if (!locale
          .split('-')
          .skip(1)
          .any((subtag) => RegExp(r'^([A-Z]{2}|[0-9]{3})$').hasMatch(subtag)))
        locale: _likelyRegion(locale, likely),
  };

  final hourCycles = <String, String>{
    for (final MapEntry(:key, :value)
        in (_path(supplemental['timeData'], ['timeData'])
                as Map<String, Object?>)
            .entries)
      key: (value! as Map<String, Object?>)['_allowed']! as String,
  };

  final dayPeriodRules = <String, Map<String, (int, int)>>{};
  for (final MapEntry(key: language, value: rules)
      in (_path(supplemental['dayPeriods'], ['dayPeriodRuleSet'])
              as Map<String, Object?>)
          .entries) {
    int minutes(Object? time) {
      final [hours, rest] = (time! as String).split(':');
      return int.parse(hours) * 60 + int.parse(rest);
    }

    dayPeriodRules[language == 'root' ? 'und' : language] = {
      for (final MapEntry(key: period, value: rule)
          in (rules! as Map<String, Object?>).entries)
        period: switch (rule) {
          {'_at': final at} => (minutes(at), minutes(at)),
          {'_from': final from, '_before': final before} => (
              minutes(from),
              minutes(before),
            ),
          _ => throw StateError('Unexpected day period rule: $rule'),
        },
    };
  }

  final timeZoneIds = <String>{};
  final utcTimeZoneIds = <String>{};
  for (final MapEntry(:key, :value)
      in (_path(json(bcp47, 'bcp47/timezone.json'), ['keyword', 'u', 'tz'])
              as Map<String, Object?>)
          .entries) {
    if (key.startsWith('_') || key == 'unk') continue;
    final aliases = (value! as Map<String, Object?>)['_alias'] as String?;
    if (aliases == null) continue;
    final ids = aliases.split(' ');
    timeZoneIds.addAll(ids);
    if (key == 'utc' || key == 'gmt') utcTimeZoneIds.addAll(ids);
  }

  _write('lib/src/date_data.dart', [
    notice,
    '/// The locales with date data, the CLDR locales that `CldrLocale.chain`\n'
        '/// of package:messageformat finds, mapped to the fields in which each\n'
        '/// differs from its parent in that chain. The data is that of the\n'
        '/// Gregorian calendar.\n'
        '///\n'
        '/// A field is one of:\n'
        '///\n'
        '/// - `months.<context>.<width>`, `days.<context>.<width>`, and\n'
        '///   `eras.<width>`: the names of the months from January, the days\n'
        '///   from Sunday, and the eras from BCE, separated by U+001F. A\n'
        '///   `stand-alone` field is empty when it is the same as the\n'
        '///   `format` one. The widths are those that patterns use.\n'
        '/// - `dayPeriods.<period>`: the abbreviated name of a day period,\n'
        '///   such as `am` or `morning1`, in the format context.\n'
        '/// - `dateFormat.<length>`, `timeFormat.<length>`, and their\n'
        '///   skeletons `dateSkeleton.<length>` and `timeSkeleton.<length>`.\n'
        '/// - `dateTimeFormat.<length>` and `dateTimeFormat.atTime.<length>`:\n'
        '///   the patterns that combine a date `{1}` and a time `{0}`.\n'
        '/// - `availableFormats.<skeleton>`: a pattern for a skeleton, for\n'
        '///   the skeletons that use only the fields the runtime formats.\n'
        '/// - `appendItem.<field>`: the pattern that appends a missing field.\n'
        '/// - `gmtFormat` and `hourFormat`: the localized GMT format of time\n'
        '///   zone offsets.\n'
        '///\n'
        '/// `und` is the root locale and has every field that a locale can\n'
        '/// inherit.\n'
        'const dateLocales = <String, Map<String, String>>{\n',
    for (final locale in available)
      '  ${_string(locale)}: {${[
        for (final key in dateDeltas[locale]!.keys.toList()..sort())
          '${_string(key)}: ${_string(dateDeltas[locale]![key]!)}',
      ].join(', ')}},\n',
    '};\n\n',
    '/// The likely region of each locale in [dateLocales] that has no\n'
        '/// region subtag, as a key of [hourCycles].\n'
        'const localeRegions = <String, String>{\n',
    for (final key in localeRegions.keys.toList()..sort())
      '  ${_string(key)}: ${_string(localeRegions[key]!)},\n',
    '};\n\n',
    '/// The hour formats allowed in each region, or for a language in a\n'
        '/// region such as `hi-IN`, most preferred first, such as `h hb H hB`:\n'
        '/// an hour symbol, optionally followed by the day period symbol to\n'
        '/// use with it. `001` is the default.\n'
        'const hourCycles = <String, String>{\n',
    for (final key in hourCycles.keys.toList()..sort())
      '  ${_string(key)}: ${_string(hourCycles[key]!)},\n',
    '};\n\n',
    '/// The day period rules of each language: the minutes after midnight\n'
        '/// from which each period starts and before which it ends, which are\n'
        '/// equal for the periods `midnight` and `noon`.\n'
        'const dayPeriodRules = <String, Map<String, (int, int)>>{\n',
    for (final language in dayPeriodRules.keys.toList()..sort())
      '  ${_string(language)}: {${[
        for (final MapEntry(key: period, value: (from, before))
            in dayPeriodRules[language]!.entries)
          '${_string(period)}: ($from, $before)',
      ].join(', ')}},\n',
    '};\n\n',
    '/// The time zone identifiers that CLDR knows: the IANA identifiers and\n'
        '/// their aliases, from the BCP 47 `tz` keyword, without those of the\n'
        '/// unknown time zone.\n'
        'const timeZoneIds = <String>{\n',
    for (final id in timeZoneIds.toList()..sort()) '  ${_string(id)},\n',
    '};\n\n',
    '/// The identifiers in [timeZoneIds] of UTC and GMT, whose offset is\n'
        '/// always zero.\n'
        'const utcTimeZoneIds = <String>{\n',
    for (final id in utcTimeZoneIds.toList()..sort()) '  ${_string(id)},\n',
    '};\n',
  ]);
}

/// The fields of a locale's Gregorian calendar and time zone data. See
/// `dateLocales` in lib/src/date_data.dart.
Map<String, String> _dateFields(
  Map<String, Object?> calendar,
  Map<String, Object?> zones,
) {
  final fields = <String, String>{};
  // A pattern can carry a `numbers` override, which the runtime ignores.
  String text(Object? value) => switch (value) {
        String() => value,
        {'_value': final String pattern} => pattern,
        _ => throw StateError('Unexpected pattern: $value'),
      };
  Map<String, Object?> map(Object? value) => value! as Map<String, Object?>;

  // The widths that patterns use, or that the runtime asks for. Stand-alone
  // names that are the same as those in the format context are left empty.
  for (final (section, widths, keys) in [
    (
      'months',
      ['abbreviated', 'wide', 'narrow'],
      [for (var month = 1; month <= 12; month++) '$month'],
    ),
    (
      'days',
      ['abbreviated', 'wide', 'narrow'],
      ['sun', 'mon', 'tue', 'wed', 'thu', 'fri', 'sat'],
    ),
  ]) {
    for (final width in widths) {
      String names(String context) {
        final names = map(map(map(calendar[section])[context])[width]);
        return [for (final key in keys) names[key]! as String].join(_separator);
      }

      final format = names('format');
      final standAlone = names('stand-alone');
      fields['$section.format.$width'] = format;
      fields['$section.stand-alone.$width'] =
          standAlone == format ? '' : standAlone;
    }
  }
  for (final width in ['eraAbbr', 'eraNames', 'eraNarrow']) {
    final names = map(map(calendar['eras'])[width]);
    fields['eras.$width'] = [
      for (final key in ['0', '1']) names[key]! as String
    ].join(_separator);
  }
  for (final MapEntry(:key, :value)
      in map(map(map(calendar['dayPeriods'])['format'])['abbreviated'])
          .entries) {
    if (!key.contains('-alt-')) fields['dayPeriods.$key'] = value! as String;
  }
  final dateTimeFormats = map(calendar['dateTimeFormats']);
  final atTime = map(map(calendar['dateTimeFormats-atTime'])['standard']);
  for (final length in ['full', 'long', 'medium', 'short']) {
    fields['dateFormat.$length'] = text(map(calendar['dateFormats'])[length]);
    fields['dateSkeleton.$length'] =
        text(map(calendar['dateSkeletons'])[length]);
    fields['timeFormat.$length'] = text(map(calendar['timeFormats'])[length]);
    fields['timeSkeleton.$length'] =
        text(map(calendar['timeSkeletons'])[length]);
    fields['dateTimeFormat.$length'] = text(dateTimeFormats[length]);
    fields['dateTimeFormat.atTime.$length'] = text(atTime[length]);
  }
  for (final MapEntry(:key, :value)
      in map(dateTimeFormats['availableFormats']).entries) {
    if (_formattedSkeleton.hasMatch(key)) {
      fields['availableFormats.$key'] = value! as String;
    }
  }
  final appendItems = map(dateTimeFormats['appendItems']);
  for (final field in _appendedFields) {
    fields['appendItem.$field'] = appendItems[field]! as String;
  }
  for (final name in ['gmtFormat', 'hourFormat']) {
    fields[name] = zones[name]! as String;
  }
  return fields;
}

/// The likely region of [locale], which has no region subtag: that of the
/// locale itself, or else of its language and script, or of its language.
String _likelyRegion(String locale, Map<String, String> likely) {
  final [language, ...rest] = locale.split('-');
  final script = rest.where((subtag) => subtag.length == 4).firstOrNull;
  for (final key in [
    locale,
    if (script != null) '$language-$script',
    language,
  ]) {
    if (likely[key] case final tag?) return tag.split('-').last;
  }
  throw StateError('No likely region for $locale');
}

/// The separator of the names in a date field.
const _separator = '\u001f';

/// A skeleton of only the fields that the runtime formats, without the
/// `-alt-` and `-count-` variants.
final _formattedSkeleton = RegExp(r'^[GyMLdEcabBhHKkmsvz]+$');

/// The fields whose `appendItem` the runtime uses, which append them with
/// no field name.
const _appendedFields = ['Era', 'Year', 'Day-Of-Week', 'Timezone'];

Object? _path(Object? json, List<String> keys) {
  for (final key in keys) {
    json = (json! as Map<String, Object?>)[key];
  }
  return json;
}

Map<String, String> _strings(Object? json) =>
    (json! as Map<String, Object?>).cast<String, String>();

/// A Dart string literal for [value], with every character outside
/// printable ASCII escaped.
String _string(String value) {
  final buffer = StringBuffer("'");
  for (final rune in value.runes) {
    if (rune == 0x27 || rune == 0x5c || rune == 0x24) {
      buffer.write('\\${String.fromCharCode(rune)}');
    } else if (rune >= 0x20 && rune < 0x7f) {
      buffer.writeCharCode(rune);
    } else if (rune <= 0xffff) {
      buffer.write('\\u${rune.toRadixString(16).padLeft(4, '0')}');
    } else {
      buffer.write('\\u{${rune.toRadixString(16)}}');
    }
  }
  return (buffer..write("'")).toString();
}

String _notice(String license) => [
      '// Generated by tool/generate_cldr_data.dart from the CLDR JSON\n',
      '// packages $cldrJsonVersion (Unicode CLDR release-48-2). Do not edit.\n',
      '//\n',
      '// The data below is derived from Unicode CLDR data files, which\n',
      '// are distributed under this notice:\n',
      '//\n',
      for (final line in LineSplitter.split(license.trim()))
        line.isEmpty ? '//\n' : '// $line\n',
      '\n',
    ].join();

void _write(String path, List<String> chunks) {
  final file = File.fromUri(Platform.script.resolve('../$path'));
  file.writeAsStringSync(chunks.join());
  final format = Process.runSync('dart', ['format', file.path]);
  stdout.write(format.stdout);
  stderr.write(format.stderr);
}

/// The files of an npm package at [cldrJsonVersion], by path.
Future<Map<String, String>> _package(String name) async => _untar(gzip
    .decode(await _download('$_registry/$name/-/$name-$cldrJsonVersion.tgz')));

Future<List<int>> _download(String url) async {
  final client = HttpClient();
  try {
    final response = await (await client.getUrl(Uri.parse(url))).close();
    if (response.statusCode != HttpStatus.ok) {
      throw HttpException('${response.statusCode} for $url');
    }
    return [for (final chunk in await response.toList()) ...chunk];
  } finally {
    client.close();
  }
}

/// The regular files of a tar archive, decoded as UTF-8, by path.
Map<String, String> _untar(List<int> bytes) {
  final files = <String, String>{};
  var offset = 0;
  while (offset + 512 <= bytes.length) {
    final header = bytes.sublist(offset, offset + 512);
    if (header.every((byte) => byte == 0)) break;
    String field(int start, int length) {
      final raw = header.sublist(start, start + length);
      final end = raw.indexOf(0);
      return utf8.decode(end < 0 ? raw : raw.sublist(0, end)).trim();
    }

    final name = field(0, 100);
    final prefix = field(345, 155);
    final size = int.parse(field(124, 12), radix: 8);
    final type = header[156];
    offset += 512;
    if (type == 0x30 || type == 0) {
      final path = prefix.isEmpty ? name : '$prefix/$name';
      files[path] = utf8.decode(bytes.sublist(offset, offset + size));
    }
    offset += (size + 511) ~/ 512 * 512;
  }
  return files;
}
