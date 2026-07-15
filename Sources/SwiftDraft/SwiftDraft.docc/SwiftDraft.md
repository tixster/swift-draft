# ``SwiftDraft``

Generate editable, validated draft values for Swift structures.

## Overview

Attach ``Draft()`` to a structure to generate a nested `Draft` type. Each stored
property becomes a plain optional value. Model properties that are already
optional keep their type and do not block model creation. Use
``DraftRequired()`` when a particular optional property must be explicitly set.
Initialized mutable properties keep their type and initial value in the draft;
use ``DraftDefault(_:)`` to provide or override that value explicitly.

```swift
@Draft
struct Article: Equatable, Codable {
  var id: Int
  var title: String
}

var draft = Article.Draft()
draft.id = 42
draft.title = "Macros"

let article = try draft.makeOrThrow()
```

The generated draft repeats the protocol conformances explicitly declared by
the model. Use ``DraftIgnored()`` for stored implementation details that should
not participate in editing.

## Topics

### Macros

- ``Draft()``
- ``DraftDefault(_:)``
- ``DraftIgnored()``
- ``DraftRequired()``

### Guides

- <doc:BuildingModelsFromDrafts>
