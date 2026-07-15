# SwiftDraft

[![CI](https://github.com/tixster/swift-draft/actions/workflows/ci.yml/badge.svg)](https://github.com/tixster/swift-draft/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/tixster/swift-draft)](https://github.com/tixster/swift-draft/releases/latest)
[![Swift 6.3](https://img.shields.io/badge/Swift-6.3-F05138?logo=swift&logoColor=white)](https://www.swift.org)
[![SwiftPM](https://img.shields.io/badge/SwiftPM-compatible-brightgreen?logo=swift&logoColor=white)](https://www.swift.org/package-manager)
[![Platforms](https://img.shields.io/badge/Platforms-Apple%20%7C%20Linux-lightgrey?logo=swift)](https://github.com/tixster/swift-draft)
[![License](https://img.shields.io/github/license/tixster/swift-draft)](https://github.com/tixster/swift-draft/blob/main/LICENSE)

`SwiftDraft` generates an editable, validated draft type for a Swift struct.

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

## Quick start

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

Create and validate an empty draft:

```swift
var draft = Article.Draft()

draft.missingFields == [.id, .title] // true
draft.isComplete                     // false

draft.id = 42
draft.title = "Swift macros"

let article = try draft.makeOrThrow()
```

Edit an existing model:

```swift
let article = Article(
  id: 42,
  title: "Drafts",
  subtitle: nil
)

var draft = Article.Draft(from: article)
draft.title = "SwiftDraft"

let updated = draft.make()
```

## Macros

| Macro | Purpose |
| --- | --- |
| `@Draft` | Generates the nested `Draft` type and model conversion API. |
| `@DraftDefault(value)` | Gives a draft field a default value and keeps its model type. |
| `@DraftRequired` | Requires explicit input for an optional model property. |
| `@DraftIgnored` | Excludes an instance stored property from the draft. |

## Generated API

For a model named `Article`, `@Draft` generates:

| API | Purpose |
| --- | --- |
| `Article.Draft()` | Creates an empty draft. |
| `Article.Draft(from: article)` | Creates a complete draft from a model. |
| `Draft.Field` | A typed enum containing every included field. |
| `draft.missingFields` | Returns `Set<Draft.Field>`. |
| `draft.isComplete` | Reports whether all required input is present. |
| `draft.unset(\.field)` | Returns an optional draft field to its missing state. |
| `draft.make()` | Returns the model or `nil`. |
| `draft.makeOrThrow()` | Returns the model or throws a validation error. |
| `Article(draft: draft)` | Generated failable model initializer. |

Defining your own `init(draft:)` replaces the generated model initializer.

## Field mapping

| Model property | Draft property | Behavior |
| --- | --- | --- |
| `var title: String` | `var title: String? = nil` | Required. |
| `let id: Int` | `var id: Int? = nil` | Required and editable in the draft. |
| `var subtitle: String?` | `var subtitle: String? = nil` | Optional; `nil` is valid. |
| `@DraftRequired var choice: Bool?` | `var choice: Bool? = nil` | An explicit assignment is required. |
| `var retries: Int = 3` | `var retries: Int = 3` | Uses the model default. |
| `var nickname: String? = "Guest"` | `var nickname: String? = "Guest"` | Optional with a model default. |
| `@DraftDefault(20) var pageSize: Int` | `var pageSize: Int = 20` | Uses the explicit draft default. |
| `@DraftDefault(1) let revision: Int` | `var revision: Int = 1` | Editable in the draft, assigned once to the model. |
| `@DraftIgnored var cache: String = ""` | Omitted | Restored from the model default. |
| `let schemaVersion: Int = 1` | Omitted | Initialized constants are excluded. |
| `static` or computed property | Omitted | Not part of model construction. |

## Required fields

A non-optional property without a default becomes optional in the draft and blocks model creation until filled.

```swift
@Draft
struct Credentials {
  let userID: Int
  var password: String
}

var draft = Credentials.Draft()
draft.missingFields == [.userID, .password] // true

draft.userID = 42
draft.password = "secret"

let credentials = draft.make()

draft.unset(\.password)
draft.isComplete // false
```

An uninitialized model `let` is a mutable `var` inside `Draft`. The generated model initializer assigns it once.

## Optional fields

An optional model property does not block model creation. The draft uses the same optional type, not a double optional.

```swift
@Draft
struct Profile {
  var nickname: String?
  var bio: Optional<String>
}

var draft = Profile.Draft()

draft.isComplete // true
draft.make()     // Profile(nickname: nil, bio: nil)

draft.nickname = "Taylor"
draft.unset(\.nickname)

draft.isComplete // still true
```

## Required optional fields

Use `@DraftRequired` when an optional value may be `nil`, but the user must explicitly make that choice.

```swift
@Draft
struct Consent {
  @DraftRequired
  var accepted: Bool? = false
}

var draft = Consent.Draft()

draft.accepted   // nil
draft.isComplete // false

draft.accepted = nil
draft.isComplete // true: explicit nil counts as input

draft.unset(\.accepted)
draft.isComplete // false again
```

The model initializer is intentionally ignored for a `@DraftRequired` optional field. A draft seeded from a model is complete, including when the model value is `nil`:

```swift
let model = Consent(accepted: nil)
let draft = Consent.Draft(from: model)

draft.isComplete // true
```

## Default values and constants

Mutable model properties keep their initializer. `@DraftDefault` adds or overrides the value used by `Draft()`.

```swift
@Draft
struct EditorSettings {
  static let suggestedTitle = "Untitled"

  var retryCount: Int = 3

  @DraftDefault(Self.suggestedTitle)
  var title: String

  @DraftDefault(20)
  var pageSize: Int = 50

  @DraftDefault("Draft note")
  var note: String?

  @DraftDefault(1)
  let revision: Int

  let schemaVersion: Int = 1
  var owner: String
}

let draft = EditorSettings.Draft()

draft.retryCount // Int, 3
draft.title      // String, "Untitled"
draft.pageSize   // Int, 20
draft.note       // String?, "Draft note"
draft.revision   // Int, 1
draft.owner      // String?, nil
```

`Draft(from:)` always replaces these defaults with the model's actual values:

```swift
let model = EditorSettings(
  retryCount: 9,
  title: "Saved",
  pageSize: 100,
  note: nil,
  revision: 7,
  owner: "Taylor"
)

let draft = EditorSettings.Draft(from: model)

draft.retryCount // 9
draft.pageSize   // 100
draft.note       // nil
draft.revision   // 7
```

Default rules:

- The expression is evaluated for every new `Draft()` in the model type's context, so `Self` and static factories work.
- `@DraftDefault` takes precedence over a model initializer.
- An optional property remains optional even when it has a default.
- An initialized `let` is excluded. Remove its initializer and use `@DraftDefault` to edit it through the draft.
- `@DraftDefault` cannot be combined with `@DraftRequired` or `@DraftIgnored`.
- `unset(_:)` accepts optional draft fields only; a non-optional defaulted field has no missing state.

## Ignored and automatically excluded properties

Use `@DraftIgnored` for stored implementation details. The property must have a default unless a custom `init(draft:)` initializes it.

```swift
import Foundation

@Draft
struct CacheEntry {
  var key: String

  @DraftIgnored
  var bytes: Data = Data()

  @DraftIgnored
  lazy var normalizedKey: String = key.lowercased()

  let schemaVersion: Int = 1
  static let formatVersion: Int = 1

  var displayName: String {
    key.uppercased()
  }
}
```

Ignored values are not copied from the source model:

```swift
let source = CacheEntry(
  key: "Home",
  bytes: Data([1, 2, 3])
)

let restored = try CacheEntry.Draft(from: source).makeOrThrow()

restored.key           // "Home"
restored.bytes.isEmpty // true: the model default was used
```

Initialized constants, type properties, and computed properties are excluded automatically. A `lazy` property must be marked `@DraftIgnored`.

## Model creation and errors

Use `make()` when all failures should become `nil`:

```swift
var draft = Article.Draft()
draft.id = 42
draft.title = "Ready"

let model: Article? = draft.make()
```

Use `makeOrThrow()` to distinguish missing input from model rejection:

```swift
let draft = Article.Draft()

do {
  let model = try draft.makeOrThrow()
  print(model)
} catch let error as Article.Draft.ValidationError {
  switch error {
  case .missingFields(let fields):
    print("Missing:", fields)

  case .rejectedByModel:
    print("The model rejected a complete draft")
  }
}
```

Without a custom initializer, these two calls perform the same field conversion:

```swift
var draft = Article.Draft()
draft.id = 42
draft.title = "Ready"

let first = draft.make()
let second = Article(draft: draft)
```

## Custom model validation

Declare `init(draft:)` inside the model to control construction. A failable initializer maps rejection to `Draft.ValidationError.rejectedByModel`.

```swift
@Draft
struct PositiveID {
  var id: Int

  init?(draft: Draft) {
    guard let id = draft.id, id > 0 else {
      return nil
    }
    self.id = id
  }
}

var draft = PositiveID.Draft()
draft.id = -1

draft.isComplete // true: the field is present
draft.make()     // nil: the model rejected its value
```

A throwing initializer propagates its own error from `makeOrThrow()`. It can also initialize an ignored property that has no default:

```swift
enum RegistrationError: Error {
  case invalidAge
}

@Draft
struct Registration {
  var age: Int

  @DraftIgnored
  var category: String

  init(draft: Draft) throws {
    guard let age = draft.age, age >= 0 else {
      throw RegistrationError.invalidAge
    }

    self.age = age
    self.category = age < 18 ? "minor" : "adult"
  }
}

var draft = Registration.Draft()
draft.age = -1

try draft.makeOrThrow() // throws RegistrationError.invalidAge
draft.make()            // nil
```

Supported custom initializer forms are:

```swift
// Choose one:
init(draft: Draft)
init?(draft: Draft)
init(draft: Draft) throws
init?(draft: Draft) throws
```

The parameter may also use `Self.Draft` or `ModelName.Draft`. The initializer must be declared in the model body so the macro can see it.

## Existing initializers

The generated conversion does not depend on a synthesized memberwise initializer, so existing model initializers remain supported.

```swift
@Draft
struct SeededModel {
  var id: Int

  init(seed: Int) {
    self.id = seed
  }
}

let model = SeededModel(seed: 42)
let restored = SeededModel.Draft(from: model).make()
```

## SwiftUI bindings

Draft fields are plain values, so `@State` projects normal bindings:

- A required `String` becomes `Binding<String?>` while it is being filled.
- An optional `String?` remains `Binding<String?>`.
- A defaulted `Int` remains `Binding<Int>`.

```swift
import SwiftUI

struct ArticleForm: View {
  @State private var draft = Article.Draft()

  let onSave: (Article) -> Void

  var body: some View {
    Form {
      OptionalTextField(
        title: "Title",
        text: $draft.title
      )

      Stepper(
        "Retries: \(draft.retryCount)",
        value: $draft.retryCount,
        in: 0...10
      )

      Button("Save") {
        if let article = draft.make() {
          onSave(article)
        }
      }
      .disabled(!draft.isComplete)
    }
  }
}

struct OptionalTextField: View {
  let title: String
  @Binding var text: String?

  var body: some View {
    TextField(
      title,
      text: Binding(
        get: { text ?? "" },
        set: { text = $0.isEmpty ? nil : $0 }
      )
    )
  }
}
```

## Protocol conformances and Codable

`Draft` copies conformances written directly in the model's inheritance clause.

```swift
import Foundation

@Draft
struct Note: Equatable, Hashable, Codable, Sendable, Identifiable {
  var id: UUID
  var text: String
}

let draft = Note.Draft(
  from: Note(id: UUID(), text: "Draft")
)

let data = try JSONEncoder().encode(draft)
let decoded = try JSONDecoder().decode(Note.Draft.self, from: data)

decoded == draft // true
```

`Codable` also preserves whether a `@DraftRequired` optional field was explicitly assigned:

```swift
@Draft
struct Submission: Codable {
  @DraftRequired var comment: String?
}

var draft = Submission.Draft()
draft.comment = nil

let data = try JSONEncoder().encode(draft)
let decoded = try JSONDecoder().decode(
  Submission.Draft.self,
  from: data
)

decoded.isComplete // true
```

Conformances added later in an extension are not visible to the macro. Custom protocols compile only when the generated draft satisfies their requirements.

## Generic models

Constrained generic models are supported.

```swift
@Draft
struct Box<Value: Equatable>: Equatable {
  var value: Value
}

var draft = Box<Int>.Draft()
draft.value = 42

draft.make() == Box(value: 42) // true
```

Defaults may use generic static requirements:

```swift
protocol DraftValue: Equatable {
  static var draftDefault: Self { get }
}

extension Int: DraftValue {
  static var draftDefault: Int { 42 }
}

@Draft
struct DefaultBox<Value: DraftValue>: Equatable {
  var value: Value = .draftDefault
}

let draft = DefaultBox<Int>.Draft()
draft.value // 42
```

## Access control

The generated `Draft` follows the model's access level. Each field follows its source property's access level; `private` becomes `fileprivate` so generated same-file conversion code can read it.

```swift
@Draft
public struct Document {
  public var title: String
  public var priority: Int = 1
  private var secret: String

  public init(title: String) {
    self.title = title
    self.secret = "kept"
  }
}
```

From another module, seed the draft to preserve inaccessible included fields:

```swift
let model = Document(title: "Before")
var draft = Document.Draft(from: model)

draft.title = "After"
draft.priority = 5

let updated = try draft.makeOrThrow()
```

An empty public draft cannot be completed externally if it contains a required non-public field. Give that field a default, mark it `@DraftIgnored`, provide a custom initializer, or seed the draft from a model.

## Limitations

- `@Draft` supports structs only.
- Every included instance stored property requires an explicit type annotation.
- Stored properties must use simple identifier patterns.
- `lazy` properties and stored opaque `some` types must use `@DraftIgnored`.
- Optional types are recognized syntactically as `T?`, `T!`, `Optional<T>`, or `Swift.Optional<T>`. An optional hidden behind a type alias is not recognized.
- `@DraftDefault` accepts exactly one unlabeled expression and applies only to instance stored properties.
- `@DraftDefault` cannot be used on an initialized `let`.
- `@DraftIgnored` requires a model default or a custom `init(draft:)`.
- A model cannot already declare a nested type or type alias named `Draft`.
- `isComplete`, `missingFields`, `unset`, `make`, and `makeOrThrow` are reserved draft property names.

## Requirements

- Swift 6.3+
- iOS 13+, macOS 10.15+, tvOS 13+, watchOS 6+, visionOS 1+, or Linux

## Development

```shell
swift test
swift build -c release
```
