import 'message_value.dart';

/// The character direction of [locale], a BCP 47 language tag.
///
/// A script subtag decides when there is one; otherwise the language's
/// usual script does. Tags this does not recognise are left-to-right.
MessageDirection localeDirection(String locale) {
  final subtags = locale.toLowerCase().split(RegExp('[-_]'));
  for (final subtag in subtags.skip(1)) {
    if (subtag.length == 4 && !_isDigit(subtag.codeUnitAt(0))) {
      return _rtlScripts.contains(subtag)
          ? MessageDirection.rtl
          : MessageDirection.ltr;
    }
    // Only the language may come before the script, apart from extended
    // language subtags of three letters.
    if (subtag.length != 3) break;
  }
  return _rtlLanguages.contains(subtags.first)
      ? MessageDirection.rtl
      : MessageDirection.ltr;
}

bool _isDigit(int unit) => unit >= 0x30 && unit <= 0x39;

/// ISO 15924 codes of the right-to-left scripts in current use.
const _rtlScripts = {
  'adlm', 'arab', 'hebr', 'mand', 'mend', 'nkoo', 'rohg', 'samr', 'syrc', //
  'thaa', 'yezi',
};

/// Languages whose likely script, in CLDR's likely subtags, is
/// right-to-left.
const _rtlLanguages = {
  'ar', 'arc', 'azb', 'bal', 'bqi', 'ckb', 'dv', 'fa', 'glk', 'he', 'iw', //
  'khw', 'ks', 'lrc', 'mzn', 'nqo', 'pnb', 'ps', 'rhg', 'sd', 'sdh', 'syr',
  'ug',
  'ur', 'yi',
};
