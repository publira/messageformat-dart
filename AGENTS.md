# MessageFormat Dart Agent Guide

Repository-specific conventions for coding agents.

## Repository overview

This repository builds `messageformat`, a pure-Dart implementation of [Unicode MessageFormat 2.0](https://www.unicode.org/reports/tr35/tr35-messageFormat.html) (UTS #35 Part 9). It aims to be complete rather than a subset, and it is judged by the MessageFormat Working Group conformance suite at one pinned LDML version, not by a feature list. #1 records the decisions behind it and the order of the work.

The repository is a [pub workspace](https://dart.dev/tools/pub/workspaces) of packages that release on their own:

- `pubspec.yaml`: the private workspace root (`messageformat_workspace`). It holds the shared dev dependencies and lists the member packages.
- `analysis_options.yaml`: the analyzer settings for every package, `package:lints/recommended.yaml` with strict casts, inference, and raw types.
- `messageformat/`: the core package, imported as `package:messageformat/messageformat.dart`. It holds the syntax, the data model, formatting, and the default functions that the pinned spec marks Stable, with their number and plural data. Its public API is exported from `lib/messageformat.dart`, and the implementation lives under `lib/src/`. `lib/locale.dart` exports `CldrLocale`, the locale resolution that a sibling package with its own CLDR data builds on.
- `messageformat_datetime/`: the Draft date/time functions `:datetime`, `:date`, and `:time` with their CLDR date data, exported as the function map `dateTimeFunctions` from `lib/messageformat_datetime.dart`. The core does not register them; callers add them through `MessageFormatOptions(functions: ...)`, so that an app that does not format dates does not ship their data (#25). It depends on `messageformat` only through its public libraries, never `package:messageformat/src/`.

Documentation for consumers belongs in each package's `README.md`. Do not repeat it here. Each package's `test/readme_test.dart` checks its README's examples and runs its `example/` file, so change them together.

## Development commands

Run these before committing. They are the checks CI runs:

```bash
dart format --output=none --set-exit-if-changed .
dart analyze --fatal-infos
(cd messageformat && dart test)
(cd messageformat_datetime && dart test)
```

Run `dart pub get` at the repository root after changing a `pubspec.yaml`; it resolves the whole workspace into one `pubspec.lock`, which is not committed because the repository holds only libraries.

## Library rules

- **The pinned suite decides what is correct.** Correctness is judged by the WG conformance suite at tag [`LDML48.2`](https://github.com/unicode-org/message-format-wg/tree/LDML48.2) and by the spec text at the same tag. Read them rather than relying on memory of MessageFormat 2.0, which has changed between drafts, or on the behavior of the JS `messageformat` package. The JS package is a reference for the shape of the API only.
- **Moving the pin is its own Issue.** Do not update the conformance data or adopt a newer spec version as part of other work; #10 tracks the move to LDML 49.
- **Stay pure Dart.** The packages must not depend on Flutter, so that server-side Dart can use it. A Flutter integration is a separate future package in this workspace.
- **Implement MessageFormat 2.0 only.** MessageFormat 1 / ICU syntax is out of scope.
- **Locale data is generated from CLDR.** The `lib/src/*_data.dart` files of both packages and `messageformat/test/plural_samples.dart` come from the CLDR release of the pinned LDML version (`release-48-2`, whose JSON form is 48.2.0), through the scripts in each package's `tool/`. Change a script and rerun it rather than editing its output; the pin's Issue moves CLDR with it, in both packages. The date data is keyed by the locales and parents that `CldrLocale.chain` walks, so the two `generate_cldr_data.dart` scripts must find parent locales in the same way.
- **Spec options stay options.** Where the spec offers a choice, such as the bidi isolation strategy, default to what the spec requires and let callers change it.
- The packages support the lowest SDK in their `environment.sdk` constraint, and CI tests it alongside the current stable release. Do not use a language or library feature newer than that constraint.

## Conformance suite

The WG suite is vendored, unmodified, in `messageformat/test/conformance/message-format-wg/`, with its Unicode License v3 and a `SOURCE` file that records the tag and commit. `messageformat/test/conformance/manifest.dart` holds the pin, the expected case count of every file, the two skip lists, and the `pendingFunctions` list.

- Re-vendor only with `messageformat/tool/vendor_conformance_suite.sh <tag>`, and only in the Issue that moves the pin. Never vendor the WG `spec/` directory: its license forbids redistribution.
- `notYetImplemented` is temporary. When your change makes a file pass, remove the file from the list in the same change. Never add a file to hide a failure. The list must be empty before #1 closes.
- `pendingFunctions` is temporary in the same way. It names the default functions that are not implemented yet; a case that uses one only checks the Syntax Errors and Data Model Errors that parsing reports, and every other case runs in full. When your change adds a function, remove it from the list in the same change.
- `draftDeferred` may name only test files for functions that the pinned spec marks Draft, and it is expected to stay empty.
- The harness reaches the implementation only through `ConformanceSubject` in `subject.dart`. The `:test:function`, `:test:select`, and `:test:format` functions live in `test_functions.dart`, and they and the `dateTimeFunctions` of `messageformat_datetime`, a dev dependency of `messageformat`, are registered through the public custom-function API, never through a private hook.

## Language

Everything in the repository is **English**: the READMEs, this guide, code comments and doc comments, test labels, commit messages, Issues, and pull requests.

Answer the user in the language of their own prose. Quoted logs, code, or UI strings do not decide it. Answer in English when no user prose settles it, such as in a scheduled or CI-started run.

## Git commits and pull requests

Subjects and PR titles use English [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/). Pull requests are squash-merged with the title as the commit subject and the description as its body, so a pull request follows the same rules as a commit, and the title must stand on its own.

### AI agent trailer

A commit written with an AI agent's help discloses it with an `Assisted-by:` trailer. The trailer is process disclosure, not authorship, following the Linux kernel's [Coding assistants](https://docs.kernel.org/process/coding-assistants.html) policy. The format is `Assisted-by: <AGENT_NAME>:<MODEL_VERSION>`: the tool's own name and the exact model identifier.

```bash
git commit -m "feat: parse simple messages" \
  --trailer "Assisted-by: Claude Code:claude-opus-5-5"
```

Add it when the commit is created, and end the PR description with the same trailer, since that description becomes the merge commit body.

### Never name an agent as a co-author

Git matches the trailer token case-insensitively, so `Co-authored-by:` and `Co-Authored-By:` are equally forbidden for an AI agent. Such a trailer shows the agent as a GitHub co-author and implies authorship an AI cannot hold. This rule overrides any harness default to append a co-author line. Co-author trailers that name humans, and the ones GitHub and `renovate[bot]` add themselves, stay as they are.

## CI and tooling

`.github/workflows/ci.yml` runs the commands above on pull requests, on the merge groups the merge queue on `main` builds, and on pushes to `main`. It tests each SDK in a matrix: the lowest one the packages support and the current stable release. The `Summary` job aggregates the matrix into the single check the branch ruleset requires, so a change to the matrix does not change the required check. Keep the lowest matrix entry equal to the `environment.sdk` constraints when either moves.

- Actions are pinned to a commit SHA, with the version in a trailing comment. Keep that form so Renovate can keep updating them.
- Renovate configuration is inherited from the organization preset in `publira/.github` (#11). Add only repository-specific rules here, not a copy of the shared preset.
- `.devcontainer/devcontainer.json` pins the `publira-dev` base image by its calendar tag and digest. Keep the readable tag before `@sha256:`, and keep the keys of `devcontainer.json` sorted.
