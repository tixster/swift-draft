# SwiftDraft

[![CI](https://github.com/tixster/swift-draft/actions/workflows/ci.yml/badge.svg)](https://github.com/tixster/swift-draft/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/tixster/swift-draft)](https://github.com/tixster/swift-draft/releases/latest)
[![Swift 6.3](https://img.shields.io/badge/Swift-6.3-F05138?logo=swift&logoColor=white)](https://www.swift.org)
[![SwiftPM](https://img.shields.io/badge/SwiftPM-compatible-brightgreen?logo=swift&logoColor=white)](https://www.swift.org/package-manager)
[![Platforms](https://img.shields.io/badge/Platforms-Apple%20%7C%20Linux-lightgrey?logo=swift)](https://github.com/tixster/swift-draft)
[![License](https://img.shields.io/github/license/tixster/swift-draft)](https://github.com/tixster/swift-draft/blob/main/LICENSE)

`SwiftDraft` generates an editable draft type for a Swift model.

## Installation

```swift
dependencies: [
  .package(
    url: "https://github.com/tixster/swift-draft.git",
    from: "1.0.0"
  )
]
```

Add the product to your target:

```swift
.product(name: "SwiftDraft", package: "swift-draft")
```

## Usage

```swift
import SwiftDraft

@Draft
struct Article: Equatable, Codable, Sendable {
  var id: Int
  var title: String
  var subtitle: String?
  var retryCount: Int = 3
}
```

The macro generates `Article.Draft`, model conversion APIs, and completeness checks:

```swift
var draft = Article.Draft()

draft.id = 42
draft.title = "Swift macros"

draft.isComplete       // true
draft.missingFields    // []

let article = draft.make()
let validated = try draft.makeOrThrow()
```

Create a draft from an existing model:

```swift
let article = Article(id: 42, title: "Drafts", subtitle: nil)
var draft = Article.Draft(from: article)

draft.title = "SwiftDraft"
let updated = Article(draft: draft)
```

## Field behavior

| Model property | Generated draft property | Completeness |
| --- | --- | --- |
| `var title: String` | `var title: String? = nil` | Required |
| `var subtitle: String?` | `var subtitle: String? = nil` | Optional; `nil` is valid |
| `@DraftRequired var choice: Bool?` | `var choice: Bool? = nil` | Explicit assignment required; `nil` counts |
| `var retries: Int = 3` | `var retries: Int = 3` | Ready |
| `@DraftDefault(20) var pageSize: Int` | `var pageSize: Int = 20` | Ready |
| `@DraftIgnored var cache: String = ""` | Omitted | — |
| `let version: Int = 1` | Omitted | — |

Draft fields are plain values, so they work directly with SwiftUI bindings:

```swift
@State private var draft = Article.Draft()

// $draft.title: Binding<String?>
// $draft.retryCount: Binding<Int>
```

Use `unset(_:)` to return an optional draft field to its missing state:

```swift
draft.unset(\.title)
```

For `@DraftRequired` optional fields, assigning `nil` counts as explicit input. Calling `unset(_:)` makes the field missing again.

## Defaults

An initializer on a mutable model property becomes the draft default. Use `@DraftDefault` to provide or override it:

```swift
@Draft
struct Settings {
  var retryCount: Int = 3

  @DraftDefault(20)
  var pageSize: Int = 50

  @DraftDefault(1)
  let revision: Int

  var owner: String
}
```

- `Draft()` starts with `retryCount == 3`, `pageSize == 20`, and `revision == 1`.
- `Draft(from:)` replaces defaults with values from the model.
- Default expressions are evaluated for every new `Draft()` in the model's context.
- `@DraftDefault` cannot be combined with `@DraftRequired` or `@DraftIgnored`.
- An initialized `let` is omitted. An uninitialized `let` can be included with `@DraftDefault` and is mutable only inside `Draft`.

## Model validation

Define `init(draft:)` on the model to add validation. The macro uses it from `make()` and `makeOrThrow()`:

```swift
@Draft
struct PositiveID {
  var id: Int

  init?(draft: Draft) {
    guard let id = draft.id, id > 0 else { return nil }
    self.id = id
  }
}
```

The initializer may be failable, non-failable, or throwing. `makeOrThrow()` reports missing fields, model rejection, or propagates the model's error.

## Protocols and access

- `Draft` copies protocols declared directly on the model. Protocols added in extensions are not visible to the macro.
- Synthesized conformances work when every generated field supports them.
- Draft fields keep the source property's access level. `private` is emitted as `fileprivate` because generated model conversion code lives in an extension.

## Limitations

- `@Draft` supports structs only.
- Included stored properties require an explicit type annotation.
- `lazy` properties and opaque `some` types must use `@DraftIgnored`.
- Optional types are recognized syntactically as `T?`, `Optional<T>`, or `Swift.Optional<T>`, not through a type alias.
- `isComplete`, `missingFields`, `unset`, `make`, and `makeOrThrow` are reserved names.

## Requirements

- Swift 6.3+
- iOS 13+, macOS 10.15+, tvOS 13+, watchOS 6+, visionOS 1+, or Linux

## Development

```shell
swift test
swift build -c release
```
