import 'locale_direction_data.dart';
import 'message_value.dart';

/// The character direction of [locale], a BCP 47 language tag.
///
/// It is the direction of the tag's script subtag when there is one, and
/// otherwise that of the likely script of its language and region, from
/// the Unicode CLDR data of the pinned LDML version. Tags this does not
/// recognise are left-to-right.
MessageDirection localeDirection(String locale) {
  final subtags = locale.toLowerCase().split(RegExp('[-_]'));
  final language = subtags.first;
  String? region;
  for (final subtag in subtags.skip(1)) {
    if (subtag.isEmpty) break;
    final startsWithDigit = _isDigit(subtag.codeUnitAt(0));
    if (subtag.length == 4 && !startsWithDigit) {
      return _direction(rtlScripts.contains(subtag));
    }
    if (subtag.length == 2 || (subtag.length == 3 && startsWithDigit)) {
      region = subtag;
      break;
    }
    // Only extended language subtags, of three letters, may come between
    // the language and the script or region.
    if (subtag.length != 3) break;
  }
  final override =
      region == null ? null : regionDirectionOverrides['$language-$region'];
  return _direction(override ?? rtlLanguages.contains(language));
}

MessageDirection _direction(bool rtl) =>
    rtl ? MessageDirection.rtl : MessageDirection.ltr;

bool _isDigit(int unit) => unit >= 0x30 && unit <= 0x39;
