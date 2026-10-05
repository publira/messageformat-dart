import 'number_data.dart';

/// The CLDR number data of a locale: its numbering system, symbols,
/// patterns, and currency symbols, and the locales whose plural rules
/// apply to it.
final class NumberLocale {
  NumberLocale._(
    this.tag,
    this._chain,
    this.numberingSystem,
    this.pluralLocales,
  ) : digits = numberingSystemDigits[numberingSystem]!;

  /// The data of the first of [tags] that CLDR has data for, or of the root
  /// locale if none has.
  ///
  /// Each tag is a BCP 47 language tag. Its `nu` Unicode extension keyword,
  /// as in `ar-u-nu-latn`, chooses a numeric numbering system.
  factory NumberLocale(List<String> tags) {
    final key = tags.join(' ');
    final cached = _cache[key];
    if (cached != null) return cached;
    if (_cache.length >= 64) _cache.clear();
    return _cache[key] = _resolve(tags);
  }

  static final _cache = <String, NumberLocale>{};

  /// The requested tag whose data this is, or the first one (`und` if there
  /// is none) when no tag has data: the locale of a formatted number.
  final String tag;

  /// The locale with data and its ancestors, ending with `und`.
  final List<String> _chain;

  /// The numbering system, such as `latn` or `arab`.
  final String numberingSystem;

  /// The digits zero to nine of [numberingSystem].
  final List<String> digits;

  /// The CLDR locales whose plural rules apply, most specific first.
  final List<String> pluralLocales;

  /// The value of [field] in this locale or the nearest ancestor that has
  /// it.
  String? _field(String field) {
    for (final locale in _chain) {
      if (numberLocales[locale]![field] case final value?) return value;
    }
    return null;
  }

  /// The symbol or pattern [name] of the numbering system, such as
  /// `decimal` or `percentFormat`, falling back to that of `latn`.
  String? symbol(String name) =>
      _field('$numberingSystem.$name') ?? _field('latn.$name');

  /// The symbol [name] of the numbering system, without falling back to
  /// that of `latn`.
  String? ownSymbol(String name) => _field('$numberingSystem.$name');

  /// The minimum number of digits in the most significant group before
  /// grouping separators are used.
  int get minimumGroupingDigits =>
      int.parse(_field('minimumGroupingDigits') ?? '1');

  /// The symbol of [currency], an uppercase ISO 4217 code, or the code
  /// itself.
  String currencySymbol(String currency) => _field(currency) ?? currency;

  /// The narrow symbol of [currency], or its symbol.
  String narrowCurrencySymbol(String currency) =>
      _field('$currency.narrow') ?? currencySymbol(currency);

  /// The pattern, `decimal`, or `group` that [currency] has instead of the
  /// locale's, if any.
  String? currencyOverride(String currency, String name) =>
      _field('$currency.$name');

  static NumberLocale _resolve(List<String> tags) {
    for (final tag in tags) {
      final parsed = _Tag.parse(tag);
      if (parsed == null) continue;
      final locale = parsed.dataLocale();
      if (locale != null) return _create(tag, locale, parsed);
    }
    final first = tags.isEmpty ? 'und' : tags.first;
    return _create(first, 'und', _Tag.parse(first));
  }

  static NumberLocale _create(String requested, String locale, _Tag? tag) {
    final chain = <String>[];
    for (String? current = locale; current != null;) {
      chain.add(current);
      current = _parent(current);
    }
    final numberingSystem = switch (tag?.numberingSystem) {
      final system? when numberingSystemDigits.containsKey(system) => system,
      _ => _fieldOf(chain, 'numberingSystem') ?? 'latn',
    };
    return NumberLocale._(
      requested,
      List.unmodifiable(chain),
      numberingSystem,
      List.unmodifiable([
        ...chain.take(chain.length - 1),
        if (tag != null) tag.language,
        'und',
      ]),
    );
  }

  static String? _fieldOf(List<String> chain, String field) {
    for (final locale in chain) {
      if (numberLocales[locale]![field] case final value?) return value;
    }
    return null;
  }

  /// The parent of [locale] that has data, or `null` for the root.
  static String? _parent(String locale) {
    if (locale == 'und') return null;
    var parent = numberParents[locale] ?? _truncate(locale);
    while (!numberLocales.containsKey(parent)) {
      parent = _truncate(parent);
    }
    return parent;
  }

  static String _truncate(String locale) {
    final dash = locale.lastIndexOf('-');
    return dash < 0 ? 'und' : locale.substring(0, dash);
  }
}

/// The parts of a language tag that select locale data.
final class _Tag {
  _Tag(this.language, this.script, this.region, this.variants,
      this.numberingSystem);

  /// [tag] split into its parts, with their case normalized, or `null` if
  /// it does not start with a language subtag.
  static _Tag? parse(String tag) {
    final subtags = tag.split(RegExp('[-_]'));
    var language = subtags.first.toLowerCase();
    if (language == 'root') language = 'und';
    if (!RegExp(r'^([a-z]{2,3}|[a-z]{5,8})$').hasMatch(language)) {
      return null;
    }
    String? script;
    String? region;
    final variants = <String>[];
    String? numberingSystem;
    var index = 1;
    bool at(bool Function(String subtag) test) =>
        index < subtags.length && test(subtags[index]);
    // Extended language subtags, as in `zh-yue`, do not select data.
    while (at((subtag) => subtag.length == 3 && _isAlpha(subtag))) {
      index++;
    }
    if (at((subtag) => subtag.length == 4 && _isAlpha(subtag))) {
      final subtag = subtags[index++];
      script = subtag[0].toUpperCase() + subtag.substring(1).toLowerCase();
    }
    if (at((subtag) =>
        (subtag.length == 2 && _isAlpha(subtag)) ||
        (subtag.length == 3 && _isDigits(subtag)))) {
      region = subtags[index++].toUpperCase();
    }
    while (at((subtag) =>
        subtag.length >= 5 ||
        (subtag.length == 4 && _isDigits(subtag.substring(0, 1))))) {
      variants.add(subtags[index++].toLowerCase());
    }
    // The `nu` keyword of a `u` extension; a private use `x` ends the tag.
    while (index < subtags.length) {
      final singleton = subtags[index++].toLowerCase();
      if (singleton == 'x') break;
      if (singleton != 'u') continue;
      while (at((subtag) => subtag.length > 1)) {
        final key = subtags[index++].toLowerCase();
        if (key == 'nu' && at((subtag) => subtag.length > 2)) {
          numberingSystem = subtags[index++].toLowerCase();
        }
      }
    }

    if (languageAliases[language] case final alias?) {
      final [aliasLanguage, ...rest] = alias.split('-');
      language = aliasLanguage;
      for (final subtag in rest) {
        if (subtag.length == 4) {
          script ??= subtag;
        } else {
          region ??= subtag;
        }
      }
    }
    return _Tag(language, script, region, variants, numberingSystem);
  }

  final String language;
  final String? script;
  final String? region;
  final List<String> variants;
  final String? numberingSystem;

  /// The most specific locale with data that this tag falls back to, other
  /// than the root locale, or `null` if there is none.
  ///
  /// A tag without a script gets the likely script of its language and
  /// region, so that `zh-TW` uses `zh-Hant` and `pa-PK` uses `pa-Arab`.
  String? dataLocale() {
    if (language == 'und') return null;
    final defaultScript = likelyScripts[language];
    final script =
        this.script ?? likelyScripts['$language-$region'] ?? defaultScript;
    final bases = [
      if (script != null) ...[
        if (region != null) '$language-$script-$region',
        '$language-$script',
      ],
      if (script == null || script == defaultScript) ...[
        if (region != null) '$language-$region',
        language,
      ],
    ];
    for (final base in bases) {
      for (final candidate in [
        if (variants.isNotEmpty) '$base-${variants.join('-')}',
        base,
      ]) {
        if (numberLocales.containsKey(candidate)) return candidate;
      }
    }
    return null;
  }

  static bool _isAlpha(String subtag) => _alpha.hasMatch(subtag);

  static bool _isDigits(String subtag) => _digits.hasMatch(subtag);

  static final _alpha = RegExp(r'^[A-Za-z]+$');
  static final _digits = RegExp(r'^[0-9]+$');
}
