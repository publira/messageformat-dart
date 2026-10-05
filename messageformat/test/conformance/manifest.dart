/// The pinned MessageFormat Working Group conformance suite and the lists
/// that decide which of its files run.
///
/// The suite is vendored under [suiteDirectory] by
/// `tool/vendor_conformance_suite.sh <tag>`. Moving the pin is its own Issue
/// (#10): re-vendor, then update [suiteTag], [suiteCommit], and
/// [expectedCaseCounts] together.
library;

/// The WG repository tag the vendored suite was copied from.
const suiteTag = 'LDML48.2';

/// The commit [suiteTag] points to.
const suiteCommit = '7f142fb4f1f5ea6ab1eb34ce2b87e918ca9fd331';

/// The vendored copy of the WG repository's `test/` directory, relative to
/// the package root, which is where `dart test` runs.
const suiteDirectory = 'test/conformance/message-format-wg';

/// The number of test cases in each file under `tests/`, keyed by its path
/// relative to that directory.
///
/// The harness asserts these counts, so a file that is dropped, added, or
/// truncated by a re-vendor fails the run instead of silently shrinking it.
const expectedCaseCounts = <String, int>{
  'bidi.json': 27,
  'data-model-errors.json': 23,
  'fallback.json': 8,
  'functions/currency.json': 12,
  'functions/date.json': 7,
  'functions/datetime.json': 7,
  'functions/integer.json': 13,
  'functions/number.json': 41,
  'functions/offset.json': 16,
  'functions/percent.json': 13,
  'functions/string.json': 9,
  'functions/time.json': 6,
  'pattern-selection.json': 22,
  'syntax-errors.json': 133,
  'syntax.json': 114,
  'u-options.json': 10,
};

/// The total number of test cases at [suiteTag].
const expectedTotalCaseCount = 461;

/// The name under which the harness's own unpaired-surrogate cases are
/// reported, alongside the vendored files.
///
/// JSON cannot carry unpaired surrogates, so the WG suite asks UTF-16
/// implementations to add these cases themselves.
const unpairedSurrogatesFile = 'unpaired-surrogates';

/// Files whose cases are skipped because the code that makes them pass has
/// not landed yet, mapped to the Issues that will land it.
///
/// This is a temporary list, separate from [draftDeferred]. Each
/// implementation Issue removes the files it makes pass, and the list must be
/// empty before #1 is closed. Never add a file to it to hide a regression.
const notYetImplemented = <String, String>{};

/// Default functions that are not implemented yet, by identifier, mapped to
/// the Issues that will add them.
///
/// A case that uses one of them is, for now, only parsed: it must report
/// exactly the Syntax Errors and Data Model Errors in its `expErrors`
/// ([staticErrorTypes]) and no others, and its expected output and
/// formatting errors are not checked. Every other case runs in full. A case
/// uses a function when its source calls it, or, for `number` and
/// `datetime`, when it formats a number or date parameter in a placeholder
/// without a function, which the runtime does with those functions (see
/// `pendingFunctionsUsedBy` in `expectations.dart`).
///
/// Like [notYetImplemented], this list is temporary: each Issue removes the
/// functions it adds, and the list must be empty before #1 is closed.
const pendingFunctions = <String, String>{};

/// The error types that parsing reports: the Syntax Error and the Data
/// Model Errors.
const staticErrorTypes = {
  'syntax-error',
  'variant-key-mismatch',
  'missing-fallback-variant',
  'missing-selector-annotation',
  'duplicate-declaration',
  'duplicate-option-name',
  'duplicate-variant',
};

/// Files deliberately not run because they test a function that the pinned
/// version of the spec marks **Draft**, mapped to the reason.
///
/// This is the only permanent exclusion the project allows, and it is
/// expected to stay empty: #7 implements the Draft date/time functions
/// instead of deferring them. Only [draftFunctionFiles] may be listed.
const draftDeferred = <String, String>{};

/// The test files for functions that LDML 48.2 marks Draft: `:datetime`,
/// `:date`, `:time`, and `:unit` (which has no file at this tag).
const draftFunctionFiles = {
  'functions/date.json',
  'functions/datetime.json',
  'functions/time.json',
  'functions/unit.json',
};

/// Maps the suite's test tags to `dart test` tag names, which cannot contain
/// a colon. Tagged cases still run; the tags let `dart test --tags` select
/// them. Every tag is declared in `dart_test.yaml`.
const testTags = <String, String>{
  ':currency': 'mf2-currency',
  ':percent': 'mf2-percent',
  'u:dir': 'mf2-u-dir',
  'u:id': 'mf2-u-id',
};
