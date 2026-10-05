// Generates lib/src/number_data.dart, lib/src/date_data.dart,
// lib/src/plural_rules_data.dart, and test/plural_samples.dart from Unicode
// CLDR data.
//
// Usage: dart run tool/generate_cldr_data.dart
//
// The data comes from the JSON form of the CLDR release that matches the
// pinned LDML version ([cldrJsonVersion]), as published to npm by the CLDR
// project as `cldr-core`, `cldr-numbers-full`, `cldr-dates-full`, and
// `cldr-bcp47`.
// Moving the pin (#10) updates the version and reruns this script.

import 'dart:convert';
import 'dart:io';

/// The version of the CLDR JSON packages: the JSON form of CLDR
/// `release-48-2`, the release of the pinned LDML version.
const cldrJsonVersion = '48.2.0';

const _registry = 'https://registry.npmjs.org';

/// The CLDR release whose JSON form [cldrJsonVersion] is.
const _cldr = 'https://raw.githubusercontent.com/unicode-org/cldr/release-48-2';

Future<void> main() async {
  final core = await _package('cldr-core');
  final numbers = await _package('cldr-numbers-full');
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
      'aliases',
      'currencyData',
      'dayPeriods',
      'likelySubtags',
      'numberingSystems',
      'ordinals',
      'parentLocales',
      'plurals',
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

  // The fields of each locale. The JSON data is resolved, so each locale
  // has every field it inherits, and only those that differ from its
  // parent's are kept.
  final fields = {
    for (final locale in available)
      locale: _localeFields(
        _path(json(numbers, 'main/$locale/numbers.json'),
            ['main', locale, 'numbers']) as Map<String, Object?>,
        _path(json(numbers, 'main/$locale/currencies.json'),
            ['main', locale, 'numbers', 'currencies']) as Map<String, Object?>,
      ),
  };
  // The JSON form of root has only the symbols of `latn`, but root also
  // has those of other numbering systems, which a tag such as
  // `en-u-nu-arab` uses.
  final rootOnly = <String>{};
  for (final MapEntry(:key, :value) in _rootFields(
    await _fetch('$_cldr/common/main/root.xml'),
  ).entries) {
    if (!fields['und']!.containsKey(key)) {
      fields['und']![key] = value;
      rootOnly.add(key);
    }
  }
  final parents = <String, String>{};
  // The nearest ancestor with data of each locale other than `und`.
  final dataParents = <String, String>{};
  final deltas = <String, Map<String, String>>{};
  for (final locale in available) {
    if (locale == 'und') {
      deltas[locale] = {
        for (final MapEntry(:key, :value) in fields[locale]!.entries)
          if (value != _currencyCode(key)) key: value,
      };
      continue;
    }
    // The nearest ancestor with data: default content locales, such as
    // `ca-ES`, have none of their own.
    var parent = parentOf(locale);
    while (!fields.containsKey(parent)) {
      parent = parentOf(parent);
    }
    // The runtime walks up by truncation, skipping tags without data, unless
    // the parent is listed.
    var truncated = _truncate(locale);
    while (!fields.containsKey(truncated)) {
      truncated = _truncate(truncated);
    }
    if (parent != truncated) parents[locale] = parent;
    dataParents[locale] = parent;
    final inherited = fields[parent]!;
    final own = fields[locale]!;
    for (final key in inherited.keys) {
      if (!own.containsKey(key) && !rootOnly.contains(key)) {
        stderr.writeln('warning: $locale lacks $key of $parent');
      }
    }
    deltas[locale] = {
      for (final MapEntry(:key, :value) in own.entries)
        if ((inherited[key] ?? _currencyCode(key)) != value) key: value,
    };
  }

  // Languages that have locales for more than one script, whose likely
  // script decides which of those locales a tag without a script uses.
  final scripted = {
    for (final locale in available)
      if (locale.split('-') case [final language, final script, ...]
          when script.length == 4)
        language,
  };
  final likelyScripts = <String, String>{};
  for (final language in scripted) {
    final script = likelyScript(language);
    likelyScripts[language] = script;
    for (final MapEntry(:key, :value) in likely.entries) {
      if (key.split('-') case [final l, final region]
          when l == language && region.length != 4) {
        final regionScript = value.split('-')[1];
        if (regionScript != script) likelyScripts[key] = regionScript;
      }
    }
  }

  // Deprecated language codes whose replacement is a language, optionally
  // with a script or region, such as `iw` (`he`) or `sh` (`sr-Latn`).
  final languageAliases = <String, String>{};
  for (final MapEntry(:key, :value)
      in (_path(supplemental['aliases'], ['metadata', 'alias', 'languageAlias'])
              as Map<String, Object?>)
          .entries) {
    final replacement =
        ((value as Map<String, Object?>)['_replacement'] as String)
            .replaceAll('_', '-');
    if (RegExp(r'^[a-z]{2,3}$').hasMatch(key) &&
        RegExp(r'^[a-z]{2,3}(-[A-Z][a-z]{3})?(-[A-Z]{2}|-[0-9]{3})?$')
            .hasMatch(replacement) &&
        !fields.containsKey(key)) {
      languageAliases[key] = replacement;
    }
  }

  final currencyDigits = <String, int>{};
  for (final MapEntry(:key, :value)
      in (_path(supplemental['currencyData'], ['currencyData', 'fractions'])
              as Map<String, Object?>)
          .entries) {
    final digits =
        int.parse((value as Map<String, Object?>)['_digits']! as String);
    if (key != 'DEFAULT' && digits != 2) currencyDigits[key] = digits;
  }

  final numberingSystems = <String, List<String>>{
    for (final MapEntry(:key, :value)
        in (_path(supplemental['numberingSystems'], ['numberingSystems'])
                as Map<String, Object?>)
            .entries)
      if (value case {'_type': 'numeric', '_digits': final String digits})
        key: [for (final rune in digits.runes) String.fromCharCode(rune)],
  };

  final notice = _notice(license);
  _write('lib/src/number_data.dart', [
    notice,
    '/// The locales with number data, as BCP 47 tags, mapped to the fields\n'
        '/// in which each differs from its parent ([numberParents]).\n'
        '///\n'
        '/// A field is `<numbering system>.<name>` for symbols and patterns,\n'
        '/// such as `latn.decimal` or `arab.percentFormat`; a currency code\n'
        '/// for its symbol, or `<code>.<name>` for its `narrow` symbol and\n'
        '/// its own `pattern`, `decimal`, and `group`; or one of\n'
        '/// `numberingSystem` and `minimumGroupingDigits`. `und` is the\n'
        '/// root locale and has every field that a locale can inherit.\n'
        'const numberLocales = <String, Map<String, String>>{\n',
    for (final locale in available)
      '  ${_string(locale)}: {${[
        for (final key in deltas[locale]!.keys.toList()..sort())
          '${_string(key)}: ${_string(deltas[locale]![key]!)}',
      ].join(', ')}},\n',
    '};\n\n',
    '/// The parents of the locales in [numberLocales] whose parent is not\n'
        '/// the tag without its last subtag. A language\'s parent is `und`.\n'
        'const numberParents = <String, String>{\n',
    for (final key in parents.keys.toList()..sort())
      '  ${_string(key)}: ${_string(parents[key]!)},\n',
    '};\n\n',
    '/// The likely script of each language that has locales for more than\n'
        '/// one script, and of each of its `language-REGION` combinations\n'
        '/// whose likely script differs from the language\'s.\n'
        'const likelyScripts = <String, String>{\n',
    for (final key in likelyScripts.keys.toList()..sort())
      '  ${_string(key)}: ${_string(likelyScripts[key]!)},\n',
    '};\n\n',
    '/// Deprecated language codes mapped to their replacements.\n'
        'const languageAliases = <String, String>{\n',
    for (final key in languageAliases.keys.toList()..sort())
      '  ${_string(key)}: ${_string(languageAliases[key]!)},\n',
    '};\n\n',
    '/// The number of fraction digits of each currency that does not use\n'
        '/// two.\n'
        'const currencyDigits = <String, int>{\n',
    for (final key in currencyDigits.keys.toList()..sort())
      '  ${_string(key)}: ${currencyDigits[key]},\n',
    '};\n\n',
    '/// The digits zero to nine of each numeric numbering system.\n'
        'const numberingSystemDigits = <String, List<String>>{\n',
    for (final key in numberingSystems.keys.toList()..sort())
      '  ${_string(key)}: [${numberingSystems[key]!.map(_string).join(', ')}],\n',
    '};\n',
  ]);

  // The date data of each locale, kept where it differs from that of the
  // same parent as its number data.
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
    '/// The locales with date data, the same as those of `numberLocales`,\n'
        '/// mapped to the fields in which each differs from its parent (the\n'
        '/// same as for number data). The data is that of the Gregorian\n'
        '/// calendar.\n'
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

  final cardinal =
      _pluralRules(_path(supplemental['plurals'], ['plurals-type-cardinal']));
  final ordinal =
      _pluralRules(_path(supplemental['ordinals'], ['plurals-type-ordinal']));
  _write('lib/src/plural_rules_data.dart', [
    notice,
    "import 'plural_rules.dart';\n",
    ...cardinal.code('cardinal'),
    ...ordinal.code('ordinal'),
  ]);
  _write('test/plural_samples.dart', [
    notice,
    '/// Sample numbers of each plural category, by plural rule type and\n'
        '/// locale, from the `@integer` and `@decimal` samples of the CLDR\n'
        '/// plural rules. A range contributes its ends, and samples in\n'
        '/// compact exponent notation are left out.\n'
        'const pluralSamples = <String, Map<String, Map<String, List<String>>>>{\n',
    for (final (type, rules) in [('cardinal', cardinal), ('ordinal', ordinal)])
      '  ${_string(type)}: {\n${[
        for (final locale in rules.samples.keys.toList()..sort())
          '    ${_string(locale)}: {${[
            for (final MapEntry(:key, :value) in rules.samples[locale]!.entries)
              '${_string(key)}: [${value.map(_string).join(', ')}]',
          ].join(', ')}},\n',
      ].join()}  },\n',
    '};\n',
  ]);
}

/// The fields of a locale's number and currency data.
Map<String, String> _localeFields(
  Map<String, Object?> numbers,
  Map<String, Object?> currencies,
) {
  final fields = <String, String>{
    'numberingSystem': numbers['defaultNumberingSystem']! as String,
    'minimumGroupingDigits': numbers['minimumGroupingDigits']! as String,
  };
  for (final MapEntry(:key, :value) in numbers.entries) {
    final system = key.startsWith('symbols-numberSystem-')
        ? key.substring('symbols-numberSystem-'.length)
        : null;
    if (system == null) continue;
    void add(String name, Object? value) {
      if (value is String) fields['$system.$name'] = value;
    }

    final symbols = value! as Map<String, Object?>;
    for (final name in _symbols) {
      add(name, symbols[name]);
    }
    final decimal = numbers['decimalFormats-numberSystem-$system'];
    final percent = numbers['percentFormats-numberSystem-$system'];
    final currency = numbers['currencyFormats-numberSystem-$system'];
    if (decimal is Map<String, Object?>) {
      add('decimalFormat', decimal['standard']);
    }
    if (percent is Map<String, Object?>) {
      add('percentFormat', percent['standard']);
    }
    if (currency is Map<String, Object?>) {
      // Like ICU, the runtime does not use the `alphaNextToNumber`
      // patterns: currency spacing separates an alphabetic symbol from the
      // digits instead.
      for (final (field, name) in [
        ('standard', 'currencyFormat'),
        ('standard-noCurrency', 'currencyFormatNoCurrency'),
        ('accounting', 'accountingFormat'),
        ('accounting-noCurrency', 'accountingFormatNoCurrency'),
      ]) {
        add(name, currency[field]);
      }
      for (final category in _pluralCategories) {
        add('unitPattern.$category', currency['unitPattern-count-$category']);
      }
      final spacing = currency['currencySpacing'];
      if (spacing
          case {
            'beforeCurrency': final Map<String, Object?> before,
            'afterCurrency': final Map<String, Object?> after,
          }) {
        // The other fields of currencySpacing are the same in every locale,
        // so the runtime applies them itself.
        for (final side in [before, after]) {
          if (side['currencyMatch'] != '[[:^S:]&[:^Z:]]' ||
              side['surroundingMatch'] != '[:digit:]') {
            throw StateError('Unexpected currency spacing: $side');
          }
        }
        add('currencySpacingBefore', before['insertBetween']);
        add('currencySpacingAfter', after['insertBetween']);
      }
    }
  }
  for (final MapEntry(:key, :value) in currencies.entries) {
    final currency = value! as Map<String, Object?>;
    if (currency['symbol'] case final String symbol) fields[key] = symbol;
    // A currency can have its own pattern and separators, such as the euro
    // in `en-DE`, `¤#,##0.00`. As in ICU's conversion of CLDR data, a
    // currency with its own pattern has the separators `.` and `,` unless
    // it gives others.
    final pattern = currency['pattern'];
    for (final (field, name, fallback) in [
      ('symbol-alt-narrow', 'narrow', null),
      ('pattern', 'pattern', null),
      ('decimal', 'decimal', pattern == null ? null : '.'),
      ('group', 'group', pattern == null ? null : ','),
    ]) {
      if (currency[field] ?? fallback case final String text) {
        fields['$key.$name'] = text;
      }
    }
  }
  return fields;
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

/// The symbols that the runtime uses.
const _symbols = [
  'decimal',
  'group',
  'percentSign',
  'plusSign',
  'minusSign',
  'infinity',
  'nan',
  'currencyDecimal',
  'currencyGroup',
];

/// The symbols and standard patterns of each numbering system in
/// `root.xml`, as fields, leaving out those that are an alias of `latn`.
Map<String, String> _rootFields(String xml) {
  final fields = <String, String>{};
  String? first(String pattern, String text) =>
      RegExp(pattern, dotAll: true).firstMatch(text)?[1]?.let(_unescapeXml);
  for (final match in RegExp(
    r'<(symbols|decimalFormats|percentFormats|currencyFormats) '
    r'numberSystem="(\w+)">(.*?)</\1>',
    dotAll: true,
  ).allMatches(xml)) {
    final system = match[2]!;
    final body = match[3]!;
    void add(String name, String? value) {
      if (value != null) fields['$system.$name'] = value;
    }

    switch (match[1]) {
      case 'symbols':
        for (final name in _symbols) {
          add(name, first('<$name>([^<]*)</$name>', body));
        }
      case 'decimalFormats':
        add('decimalFormat',
            first(r'<decimalFormatLength>.*?<pattern>([^<]*)<', body));
      case 'percentFormats':
        add('percentFormat',
            first(r'<percentFormatLength>.*?<pattern>([^<]*)<', body));
      case 'currencyFormats':
        final standard = first(
                r'<currencyFormat type="standard">(.*?)</currencyFormat>',
                body) ??
            '';
        final accounting = first(
                r'<currencyFormat type="accounting">(.*?)</currencyFormat>',
                body) ??
            '';
        final pattern = first(r'<pattern>([^<]*)<', standard);
        final noCurrency =
            first(r'<pattern alt="noCurrency">([^<]*)<', standard);
        add('currencyFormat', pattern);
        add('currencyFormatNoCurrency', noCurrency);
        // An accounting format that is an alias is the standard one.
        add('accountingFormat',
            first(r'<pattern>([^<]*)<', accounting) ?? pattern);
        add(
            'accountingFormatNoCurrency',
            first(r'<pattern alt="noCurrency">([^<]*)<', accounting) ??
                noCurrency);
    }
  }
  return fields;
}

String _unescapeXml(String text) => text
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&apos;', "'")
    .replaceAll('&amp;', '&');

extension<T extends Object> on T {
  R let<R>(R Function(T value) transform) => transform(this);
}

const _pluralCategories = ['zero', 'one', 'two', 'few', 'many', 'other'];

/// Plural rules of one type, compiled to Dart.
final class _PluralRules {
  /// The distinct rule sets, as Dart statements, in order.
  final ruleSets = <String>[];

  /// The index in [ruleSets] of each locale's rules.
  final locales = <String, int>{};

  /// The samples of each locale's categories.
  final samples = <String, Map<String, List<String>>>{};

  /// The rules as Dart functions `_<type><index>`, and the map
  /// `<type>Rules` from each locale to its function.
  Iterable<String> code(String type) sync* {
    for (final (index, body) in ruleSets.indexed) {
      yield 'String _$type$index(PluralOperands o) {\n$body'
          "  return 'other';\n}\n\n";
    }
    yield '/// The CLDR $type plural rules, by locale.\n'
        'const ${type}Rules = <String, PluralRule>{\n';
    for (final locale in locales.keys.toList()..sort()) {
      yield '  ${_string(locale)}: _$type${locales[locale]},\n';
    }
    yield '};\n\n';
  }
}

_PluralRules _pluralRules(Object? data) {
  final rules = _PluralRules();
  final indices = <String, int>{};
  for (final MapEntry(key: locale, value: categories)
      in (data! as Map<String, Object?>).entries) {
    final body = StringBuffer();
    final localeSamples = <String, List<String>>{};
    for (final category in _pluralCategories) {
      final rule = (categories!
          as Map<String, Object?>)['pluralRule-count-$category'] as String?;
      if (rule == null) continue;
      final at = rule.indexOf('@');
      final condition = (at < 0 ? rule : rule.substring(0, at)).trim();
      localeSamples[category] = _samples(at < 0 ? '' : rule.substring(at));
      if (category == 'other') {
        if (condition.isNotEmpty) {
          throw StateError('$locale has a condition for other');
        }
        continue;
      }
      final expression = _compileCondition(condition);
      if (expression == 'false') continue;
      body.writeln(expression == 'true'
          ? "  return '$category';"
          : "  if ($expression) {\n    return '$category';\n  }");
    }
    final code = body.toString();
    rules.locales[locale] = indices.putIfAbsent(code, () {
      rules.ruleSets.add(code);
      return rules.ruleSets.length - 1;
    });
    rules.samples[locale] = localeSamples;
  }
  return rules;
}

/// The samples of a rule, such as `@integer 0, 2~16, 1c3 @decimal 0.0~1.5`.
List<String> _samples(String text) {
  final samples = <String>[];
  for (final list in text.split('@').skip(1)) {
    final values = list.substring(list.indexOf(' ') + 1);
    for (var sample in values.split(',')) {
      sample = sample.trim();
      if (sample.isEmpty || sample == '…' || sample.contains('c')) continue;
      samples.addAll(sample.split('~'));
    }
  }
  return samples;
}

/// Compiles a plural rule condition (UTS #35, Part 3, Language Plural
/// Rules) to a Dart expression over a `PluralOperands o`.
///
/// The compact exponent operands `c` and `e` are always 0, since numbers
/// are never formatted in compact notation, so relations on them are
/// folded to constants.
String _compileCondition(String condition) {
  final ors = <String>[];
  for (final and in condition.split(' or ')) {
    final relations = <String>[];
    var isFalse = false;
    for (final relation in and.split(' and ')) {
      final compiled = _compileRelation(relation.trim());
      if (compiled == 'false') isFalse = true;
      if (compiled != 'true') relations.add(compiled);
    }
    if (isFalse) continue;
    if (relations.isEmpty) return 'true';
    ors.add(relations.join(' && '));
  }
  if (ors.isEmpty) return 'false';
  return ors.length == 1
      ? ors.single
      : ors.map((and) => and.contains(' && ') ? '($and)' : and).join(' || ');
}

final _relation =
    RegExp(r'^([nivwftce])(?:\s*%\s*(\d+))?\s*(!=|=)\s*([\d.,]+)$');

String _compileRelation(String relation) {
  final match = _relation.firstMatch(relation);
  if (match == null) throw FormatException('Unsupported relation', relation);
  final operand = match[1]!;
  final modulus = match[2];
  final negated = match[3] == '!=';
  final ranges = [
    for (final item in match[4]!.split(','))
      item.split('..').map(int.parse).toList(),
  ];
  for (final range in ranges) {
    for (final value in range) {
      if (value >= PluralLimits.maxValue) {
        throw StateError('Value $value is too large in $relation');
      }
    }
  }
  if (modulus != null && PluralLimits.modulusBase % int.parse(modulus) != 0) {
    throw StateError('Unsupported modulus in $relation');
  }

  if (operand == 'c' || operand == 'e') {
    final value = modulus == null ? 0 : 0 % int.parse(modulus);
    final inRange = ranges.any((range) => range.length == 1
        ? value == range[0]
        : value >= range[0] && value <= range[1]);
    return '${inRange != negated}';
  }

  // `n` is the absolute value, which is only equal to an integer, or in a
  // range of integers, when it has no fraction.
  final name = operand == 'n' ? 'i' : operand;
  final variable = modulus == null ? 'o.$name' : 'o.$name % $modulus';
  final tests = [
    for (final range in ranges)
      range.length == 1
          ? '$variable == ${range[0]}'
          : range[0] == 0
              ? '$variable <= ${range[1]}'
              : '$variable >= ${range[0]} && $variable <= ${range[1]}',
  ];
  var test = tests.length == 1
      ? tests.single
      : tests
          .map((test) => test.contains('&&') ? '($test)' : test)
          .join(' || ');
  if (operand == 'n') {
    test = tests.length == 1 && !test.contains('&&')
        ? 'o.t == 0 && $test'
        : 'o.t == 0 && ($test)';
  }
  if (!negated) return tests.length == 1 || operand == 'n' ? test : '($test)';
  return '!($test)';
}

/// The bounds that the runtime's plural operands are kept within. They
/// mirror `PluralOperands` in lib/src/plural_rules.dart.
abstract final class PluralLimits {
  /// Every modulus in a rule divides this.
  static const modulusBase = 1000000;

  /// Every value in a rule is below this.
  static const maxValue = 1000000000000000;
}

/// [key] if it is the field of a currency's symbol, which is the currency
/// code when no locale gives one.
String? _currencyCode(String key) =>
    RegExp(r'^[A-Z]{3}$').hasMatch(key) ? key : null;

/// [locale] without its last subtag, or `und` for a language.
String _truncate(String locale) {
  final dash = locale.lastIndexOf('-');
  return dash < 0 ? 'und' : locale.substring(0, dash);
}

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

/// The text at [url].
Future<String> _fetch(String url) async => utf8.decode(await _download(url));

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
