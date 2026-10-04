import 'package:unorm_dart/unorm_dart.dart' as unorm;

/// Returns [text] in Unicode Normalization Form C.
///
/// The specification compares names and variant keys as if NFC had been
/// applied to both sides. Text below U+0300 is always in NFC, so the common
/// case returns [text] without normalizing it.
String toNfc(String text) {
  for (final unit in text.codeUnits) {
    if (unit >= 0x300) return unorm.nfc(text);
  }
  return text;
}
