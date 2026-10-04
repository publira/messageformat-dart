/// Character classes of the MessageFormat 2.0 ABNF.
library;

const $tab = 0x09;
const $lf = 0x0a;
const $cr = 0x0d;
const $space = 0x20;
const $hash = 0x23;
const $dollar = 0x24;
const $asterisk = 0x2a;
const $hyphen = 0x2d;
const $period = 0x2e;
const $slash = 0x2f;
const $colon = 0x3a;
const $equals = 0x3d;
const $at = 0x40;
const $backslash = 0x5c;
const $lbrace = 0x7b;
const $pipe = 0x7c;
const $rbrace = 0x7d;
const $ideographicSpace = 0x3000;

/// The production `ws`.
bool isWhitespace(int unit) =>
    unit == $space ||
    unit == $tab ||
    unit == $cr ||
    unit == $lf ||
    unit == $ideographicSpace;

/// The production `bidi`: ALM, LRM, RLM, and the isolates LRI, RLI, FSI,
/// and PDI.
bool isBidi(int unit) =>
    unit == 0x061c ||
    unit == 0x200e ||
    unit == 0x200f ||
    (unit >= 0x2066 && unit <= 0x2069);

/// The production `name-start`, for a code point.
bool isNameStart(int c) {
  if (c < 0x80) {
    return (c >= 0x41 && c <= 0x5a) ||
        (c >= 0x61 && c <= 0x7a) ||
        c == 0x2b ||
        c == 0x5f;
  }
  if (c <= 0xffff) {
    return (c >= 0xa1 && c <= 0x61b) ||
        (c >= 0x61d && c <= 0x167f) ||
        (c >= 0x1681 && c <= 0x1fff) ||
        (c >= 0x200b && c <= 0x200d) ||
        (c >= 0x2010 && c <= 0x2027) ||
        (c >= 0x2030 && c <= 0x205e) ||
        (c >= 0x2060 && c <= 0x2065) ||
        (c >= 0x206a && c <= 0x2fff) ||
        (c >= 0x3001 && c <= 0xd7ff) ||
        (c >= 0xe000 && c <= 0xfdcf) ||
        (c >= 0xfdf0 && c <= 0xfffd);
  }
  // Every supplementary plane, except its last two code points.
  return c <= 0x10ffff && (c & 0xffff) <= 0xfffd;
}

/// The production `name-char`, for a code point.
bool isNameChar(int c) =>
    isNameStart(c) || (c >= 0x30 && c <= 0x39) || c == $hyphen || c == $period;

bool isHighSurrogate(int unit) => unit >= 0xd800 && unit <= 0xdbff;

bool isLowSurrogate(int unit) => unit >= 0xdc00 && unit <= 0xdfff;

int combineSurrogates(int high, int low) =>
    0x10000 + ((high - 0xd800) << 10) + (low - 0xdc00);
