import 'package:messageformat/locale.dart';

import 'date_data.dart';

/// The CLDR date data of a locale, for the Gregorian calendar: its names,
/// patterns, and preferred hour cycles.
///
/// It is the data of the [CldrLocale] of the same tags, whose digits it
/// formats with.
final class DateLocale {
  DateLocale._(this.cldr);

  /// The data of the first of [tags] that CLDR has data for, or of the root
  /// locale if none has. See [CldrLocale.new].
  factory DateLocale(List<String> tags) {
    final key = tags.join(' ');
    final cached = _cache[key];
    if (cached != null) return cached;
    if (_cache.length >= 64) _cache.clear();
    return _cache[key] = DateLocale._(CldrLocale(tags));
  }

  static final _cache = <String, DateLocale>{};

  /// The locale that [tag] resolves to, whose digits format the fields.
  final CldrLocale cldr;

  /// The requested tag whose data this is. See [CldrLocale.tag].
  String get tag => cldr.tag;

  /// The value of [name] in this locale or the nearest ancestor that has
  /// it.
  ///
  /// A locale of [CldrLocale.chain] without date data, which a different
  /// CLDR version of `package:messageformat` can resolve to, inherits all
  /// of its fields.
  String? field(String name) {
    for (final locale in cldr.chain) {
      if (dateLocales[locale]?[name] case final value?) return value;
    }
    return null;
  }

  /// The names of the field [section] (`months` or `days`) in [context]
  /// (`format` or `stand-alone`) and [width], or `null` if the locale has
  /// none of that width.
  List<String>? names(String section, String context, String width) =>
      _names.putIfAbsent('$section.$context.$width', () {
        final names = field('$section.$context.$width');
        if (names == null) return null;
        if (names.isEmpty) return this.names(section, 'format', width);
        return names.split('\u001f');
      });

  final _names = <String, List<String>?>{};

  /// The patterns of the locale's `availableFormats`, by skeleton.
  late final Map<String, String> availableFormats = () {
    const prefix = 'availableFormats.';
    final formats = <String, String>{};
    for (final locale in cldr.chain) {
      final fields = dateLocales[locale];
      if (fields == null) continue;
      for (final MapEntry(:key, :value) in fields.entries) {
        if (key.startsWith(prefix)) {
          formats.putIfAbsent(key.substring(prefix.length), () => value);
        }
      }
    }
    return formats;
  }();

  /// The hour formats that the locale's language in its region, or else its
  /// region, allows, most preferred first, such as `h`, `hb`, or `H`.
  late final List<String> hourFormats = () {
    var region = cldr.region;
    if (region == null) {
      for (final locale in cldr.chain) {
        if (localeRegions[locale] case final likely?) {
          region = likely;
          break;
        }
      }
    }
    final language = cldr.chain.first.split('-').first;
    return (hourCycles['$language-$region'] ??
            hourCycles[region] ??
            hourCycles['001']!)
        .split(' ');
  }();

  /// The day period rules of the locale's language, or of the root locale.
  late final Map<String, (int, int)> periodRules = () {
    for (final locale in cldr.chain) {
      if (dayPeriodRules[locale.split('-').first] case final rules?) {
        return rules;
      }
    }
    return const <String, (int, int)>{};
  }();
}
