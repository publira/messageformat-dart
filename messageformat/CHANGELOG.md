## 0.1.0

The first release: an implementation of Unicode MessageFormat 2.0 as specified by LDML 48.2, which passes all 461 cases of the MessageFormat Working Group conformance suite at tag `LDML48.2`.

- Parse messages into the specification's data model with `parseMessage`, check a data model with `validateMessage`, and turn one back into source with `stringifyMessage`.
- Format messages with `MessageFormat.format` and `MessageFormat.formatToParts`, with pattern selection, fallback values, an error callback, and the Default Bidi Strategy, which `BidiIsolation.none` turns off.
- The Stable default functions `:string`, `:number`, `:integer`, `:offset`, `:currency`, and `:percent`, with plural rules and number formats from Unicode CLDR 48.2.
- The Draft default functions `:datetime`, `:date`, and `:time`, with Gregorian date and time patterns from Unicode CLDR 48.2.
- Custom functions through `MessageFormatOptions.functions`.
