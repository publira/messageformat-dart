## 0.1.0

- Initial release, implementing Unicode MessageFormat 2.0 as of LDML 48.2
  (UTS #35, Part 9, revision `tr35-78`).
- Parses messages into the specification's data model, reports Syntax
  Errors and Data Model Errors, and serializes a data model back to a
  message.
- Formats messages to strings or to parts, with the bidi isolation
  strategies of the specification.
- Provides the default functions that the specification marks Stable,
  `:string`, `:number`, `:integer`, `:offset`, `:currency`, and `:percent`,
  with plural rules and number data from Unicode CLDR 48.2 for every CLDR
  locale.
- Accepts custom functions through `MessageFormatOptions(functions: ...)`,
  which the date/time functions of `messageformat_datetime` use.
- Passes all 461 test cases of the MessageFormat Working Group conformance
  suite at tag `LDML48.2`.
