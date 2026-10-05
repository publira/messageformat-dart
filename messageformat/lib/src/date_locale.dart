import 'date_data.dart';
import 'number_locale.dart';

/// The CLDR date data of a locale, for the Gregorian calendar: its names,
/// patterns, and preferred hour cycles.
///
/// It is the data of the same locale as the [NumberLocale] of the same
/// tags, whose digits it formats with.
final class DateLocale {
  DateLocale._(this.numbers);

  /// The data of the first of [tags] that CLDR has data for, or of the root
  /// locale if none has. See [NumberLocale.new].
  factory DateLocale(List<String> tags) {
    final key = tags.join(' ');
    final cached = _cache[key];
    if (cached != null) return cached;
    if (_cache.length >= 64) _cache.clear();
    return _cache[key] = DateLocale._(NumberLocale(tags));
  }

  static final _cache = <String, DateLocale>{};

  /// The number data of the locale, whose digits format the fields.
  final NumberLocale numbers;

  /// The requested tag whose data this is. See [NumberLocale.tag].
  String get tag => numbers.tag;

  /// The value of [name] in this locale or the nearest ancestor that has
  /// it.
  String? field(String name) {
    for (final locale in numbers.chain) {
      if (dateLocales[locale]![name] case final value?) return value;
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
    for (final locale in numbers.chain) {
      for (final MapEntry(:key, :value) in dateLocales[locale]!.entries) {
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
    var region = numbers.region;
    if (region == null) {
      for (final locale in numbers.chain) {
        if (localeRegions[locale] case final likely?) {
          region = likely;
          break;
        }
      }
    }
    final language = numbers.chain.first.split('-').first;
    return (hourCycles['$language-$region'] ??
            hourCycles[region] ??
            hourCycles['001']!)
        .split(' ');
  }();

  /// The day period rules of the locale's language, or of the root locale.
  late final Map<String, (int, int)> periodRules = () {
    for (final locale in numbers.chain) {
      if (dayPeriodRules[locale.split('-').first] case final rules?) {
        return rules;
      }
    }
    return const <String, (int, int)>{};
  }();
}
