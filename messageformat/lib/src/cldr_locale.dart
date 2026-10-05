import 'locale_direction.dart';
import 'message_value.dart';
import 'number_locale.dart';
import 'version.dart';

/// The Unicode CLDR locale that a list of BCP 47 language tags resolves to,
/// as the default functions resolve it.
///
/// It lets a package of further functions, such as
/// `package:messageformat_datetime`, choose its locale data as `:number`
/// does: data keyed by the CLDR [cldrVersion] locales finds its locale and
/// the ancestors it inherits from in [chain], and formats digits in the
/// same numbering system.
final class CldrLocale {
  CldrLocale._(this._numbers);

  /// The locale of the first of [tags] that CLDR has data for, or the root
  /// locale `und` if none has.
  ///
  /// Each tag is a BCP 47 language tag. Its `nu` Unicode extension keyword,
  /// as in `ar-u-nu-latn`, chooses a numeric numbering system, and its `hc`
  /// keyword is kept as [hourCycle].
  factory CldrLocale(List<String> tags) => CldrLocale._(NumberLocale(tags));

  final NumberLocale _numbers;

  /// The requested tag whose locale this is, or the first one (`und` if
  /// there is none) when no tag has data: the locale of a formatted value.
  String get tag => _numbers.tag;

  /// The CLDR locale with data and its ancestors, ending with `und`, such
  /// as `[en-GB, en-001, en, und]`.
  ///
  /// Every CLDR [cldrVersion] locale with full data can appear, so data
  /// generated for those locales, with each locale keeping only what
  /// differs from its parent in this chain, is complete when its fields
  /// are looked up along the chain.
  List<String> get chain => _numbers.chain;

  /// The numbering system, such as `latn` or `arab`.
  String get numberingSystem => _numbers.numberingSystem;

  /// The digits zero to nine of [numberingSystem].
  List<String> get digits => _numbers.digits;

  /// The region subtag of the requested tag, if it has one, in upper case.
  String? get region => _numbers.region;

  /// The value of the `hc` Unicode extension keyword of the requested tag,
  /// such as `h23`, if it has one.
  String? get hourCycle => _numbers.hourCycle;

  /// The character direction of [tag], which the default functions give
  /// the values they format.
  MessageDirection get dir => localeDirection(tag);
}
