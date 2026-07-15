# Building Models from Drafts

Create drafts from scratch or seed them from an existing model.

## Overview

### Track completeness

An empty draft reports its missing fields without relying on string keys:

```swift
var draft = Article.Draft()
draft.id = 42

if !draft.isComplete {
  print(draft.missingFields)
}
```

Use `make()` when failure is expected and an optional result is convenient. Use
`makeOrThrow()` when the caller needs to distinguish missing data from model
validation failure.

### Choose optional-field validation

An optional model property is ready by default. Its initial `nil` value does not
appear in `missingFields` and does not prevent model creation:

```swift
@Draft
struct ArticleMetadata {
  var subtitle: String?
}

let draft = ArticleMetadata.Draft()
draft.isComplete // true
draft.make()     // ArticleMetadata(subtitle: nil)
```

The generated property remains a plain optional, so SwiftUI can project a
`Binding<Value?>` through an `@State` draft, for example `$draft.subtitle`.

Apply ``DraftRequired()`` when an optional property must be explicitly set.
Assigning `nil` then counts as filling the field, while `unset(_:)` marks it as
missing again.

### Provide default values

An initialized mutable model property keeps its declared type in the draft and
uses the same initial value. A non-optional model property therefore no longer
needs an additional optional layer:

```swift
@Draft
struct Settings {
  var retryCount: Int = 3
  var owner: String
}

let draft = Settings.Draft()
draft.retryCount // Int with the value 3.
draft.owner      // String? with the value nil.
```

Use ``DraftDefault(_:)`` when the model has no initializer or when its editing
default should be different:

```swift
@DraftDefault(20)
var pageSize: Int = 50

@DraftDefault(1)
let revision: Int
```

The explicit draft default takes precedence over the model initializer. It
cannot be combined with ``DraftRequired()`` or ``DraftIgnored()``. An initialized
constant remains outside the draft because `init(draft:)` cannot assign it
again; remove its initializer and use ``DraftDefault(_:)`` when the generated
initializer should supply the constant.

### Add domain validation

Declare `init(draft:)` on the model to replace the default field-copying
initializer. It may be failable or throwing. The generated `make()` and
`makeOrThrow()` methods automatically use it.
