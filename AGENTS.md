# Repository Guidelines

## Project Structure & Module Organization

This repository is a Swift 6.3 package. Public macro declarations live in
`Sources/SwiftDraft`, while their SwiftSyntax implementations and compiler
plugin registration live in `Sources/SwiftDraftMacros`. Keep those two targets
in sync when adding a macro. `Sources/SwiftDraft/SwiftDraft.docc` contains DocC
guides. `Sources/SwiftDraftAccessFixture` exists only to verify cross-module
access control.

Tests mirror these responsibilities:

- `Tests/SwiftDraftMacrosTests`: macro expansions and diagnostics.
- `Tests/SwiftDraftTests`: generated API and runtime behavior.
- `Tests/SwiftDraftAccessTests`: public and non-public access behavior.

## Build, Test, and Development Commands

- `swift test` builds the package and runs all test suites.
- `swift test --filter DraftMacroTests` runs macro expansion tests only.
- `swift test --filter DraftTests` runs generated API behavior tests.
- `swift build -c release` verifies the optimized library and macro plugin.
- `swift format lint --strict --recursive Sources Tests Package.swift` checks
  formatting without changing files.

CI runs tests and a release build with Swift 6.3 on macOS and Ubuntu. Run both
primary commands before opening a pull request.

## Coding Style & Naming Conventions

Use two-space indentation and follow `swift-format`. Prefer trailing commas in
multiline declarations and keep public documentation direct. Types and macros
use `UpperCamelCase`; functions, properties, and test methods use
`lowerCamelCase`. Name marker implementations consistently, for example
`DraftNested` and `DraftNestedMacro`.

Build generated declarations with SwiftSyntax/SwiftSyntaxBuilder. Keep
diagnostic messages actionable and diagnostic IDs stable. Update README and
DocC whenever public macro behavior changes.

## Testing Guidelines

Tests use Swift Testing (`@Suite`, `@Test`, and `#expect`). Macro tests use
`assertMacroExpansion` from `SwiftSyntaxMacrosTestSupport`. Every macro behavior
change should include an expansion or diagnostic test plus a runtime test when
generated code can execute. Add cross-module coverage when changing access
levels. No numeric coverage threshold is configured; cover each new branch and
edge case explicitly.

## Commit & Pull Request Guidelines

History uses short, imperative summaries such as `fix CI` and `update readme`.
Keep each commit focused and describe the observable change. Pull requests
should explain behavior, list verification commands, and link relevant issues.
For macro changes, include a concise source-to-expansion example. Screenshots
are not required for this non-UI package.
