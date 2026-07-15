import Foundation
import SwiftDraft
import Testing

#if canImport(SwiftUI)
  import SwiftUI
#endif

@Draft
private struct SomeModel: Equatable, Hashable, Codable, Sendable {
  var id: Int
  var title: String
}

@Draft
private struct OptionalModel: Equatable, Codable {
  var value: String?
}

@Draft
private struct RequiredOptionalModel: Equatable, Codable {
  @DraftRequired var value: String? = "model-default"
}

@Draft
private struct DefaultedModel: Equatable {
  static let defaultRetryCount = 3
  static let defaultTitle = "Untitled"

  var retryCount: Int = Self.defaultRetryCount

  @DraftDefault(Self.defaultTitle)
  var title: String

  @DraftDefault(5)
  var pageSize: Int = 20

  @DraftDefault(7)
  let id: Int

  var required: String
}

@Draft
private struct CustomInitializedModel: Equatable {
  var id: Int

  init(seed: Int) {
    self.id = seed
  }
}

@Draft
private struct DraftNamedPropertyModel: Equatable {
  var draft: Int
  var draftValue: Int
}

@Draft
private struct GenericModel<DraftValue: Equatable>: Equatable {
  var value: DraftValue
}

private protocol DraftDefaultValue: Equatable {
  static var draftDefault: Self { get }
}

extension Int: DraftDefaultValue {
  fileprivate static var draftDefault: Self { 42 }
}

@Draft
private struct GenericDefaultModel<Value: DraftDefaultValue>: Equatable {
  var value: Value = .draftDefault
}

@Draft
private struct IgnoredPropertyModel: Equatable {
  var id: Int
  @DraftIgnored var cache: String = "default-cache"
  let schemaVersion: Int = 1
}

@Draft
private struct ValidatedModel: Equatable {
  var id: Int

  init(id: Int) {
    self.id = id
  }

  init?(draft: Draft) {
    guard let id = draft.id, id > 0 else {
      return nil
    }
    self.id = id
  }
}

@Draft
private struct IdentifiableModel: Equatable, Identifiable {
  var id: Int
}

private enum ModelValidationError: Error, Equatable {
  case invalidID
}

@Draft
private struct ThrowingValidatedModel: Equatable {
  var id: Int

  init(draft: Draft) throws {
    guard let id = draft.id, id > 0 else {
      throw ModelValidationError.invalidID
    }
    self.id = id
  }
}

@Draft
private struct NestedAuthor: Equatable, Hashable, Codable, Sendable {
  var name: String
  var nickname: String?
}

@Draft
private struct NestedBook: Equatable, Hashable, Codable, Sendable {
  var title: String
  @DraftNested let author: NestedAuthor
}

@Draft
private struct OptionalNestedBook: Equatable {
  @DraftNested var author: NestedAuthor?
}

@Draft
private struct RequiredOptionalNestedBook: Equatable, Codable {
  @DraftRequired
  @DraftNested
  var author: NestedAuthor? = NestedAuthor(
    name: "Model default",
    nickname: nil
  )
}

@Draft
private struct NestedDefaultsModel: Equatable {
  static let modelAuthor = NestedAuthor(
    name: "Model default",
    nickname: nil
  )
  static let draftEditor = NestedAuthor(
    name: "Draft default",
    nickname: "Editor"
  )
  static let optionalReviewer: NestedAuthor? = NestedAuthor(
    name: "Optional default",
    nickname: nil
  )

  @DraftNested
  var author: NestedAuthor = Self.modelAuthor

  @DraftNested
  @DraftDefault(Self.draftEditor)
  var editor: NestedAuthor

  @DraftNested
  var reviewer: NestedAuthor? = Self.optionalReviewer
}

@Draft
private struct ValidatedNestedAuthor: Equatable {
  var name: String

  init?(draft: Draft) {
    guard let name = draft.name, !name.isEmpty else {
      return nil
    }
    self.name = name
  }
}

@Draft
private struct ValidatedNestedBook: Equatable {
  @DraftNested var author: ValidatedNestedAuthor
}

@Suite("Draft")
struct DraftTests {
  @Test("creates and restores a complete draft")
  func roundTrip() {
    let model = SomeModel(id: 42, title: "A title")
    let draft = SomeModel.Draft(from: model)

    #expect(draft.id == 42)
    #expect(draft.title == "A title")
    #expect(draft.isComplete)
    #expect(draft.missingFields.isEmpty)
    #expect(draft.make() == model)
    #expect(SomeModel(draft: draft) == model)
  }

  @Test("creates an empty draft and reports all missing fields")
  func emptyDraft() {
    var draft = SomeModel.Draft()

    #expect(!draft.isComplete)
    #expect(draft.missingFields == [.id, .title])
    #expect(
      throws: SomeModel.Draft.ValidationError.missingFields([.id, .title])
    ) {
      try draft.makeOrThrow()
    }

    draft.id = 42
    draft.title = "Ready"

    #expect(draft.isComplete)
    #expect(draft.make() == SomeModel(id: 42, title: "Ready"))
  }

  @Test("rejects an incomplete draft")
  func incompleteDraft() {
    let model = SomeModel(id: 42, title: "A title")
    var draft = SomeModel.Draft(from: model)
    draft.unset(\.title)

    #expect(draft.missingFields == [.title])
    #expect(draft.make() == nil)
    #expect(SomeModel(draft: draft) == nil)
  }

  @Test("accepts an unset optional property")
  func optionalProperty() throws {
    var draft = OptionalModel.Draft()
    let model = OptionalModel(value: nil)

    #expect(draft.value == nil)
    #expect(draft.isComplete)
    #expect(draft.missingFields.isEmpty)
    #expect(draft.make() == model)
    #expect(OptionalModel(draft: draft) == model)
    #expect(try draft.makeOrThrow() == model)

    draft.value = "value"
    #expect(draft.make() == OptionalModel(value: "value"))

    draft.unset(\.value)
    #expect(draft.isComplete)
    #expect(draft.make() == model)

    let data = try JSONEncoder().encode(draft)
    let decoded = try JSONDecoder().decode(
      OptionalModel.Draft.self,
      from: data
    )
    #expect(decoded == draft)
    #expect(decoded.make() == model)
  }

  @Test("can require an optional property explicitly")
  func requiredOptionalProperty() throws {
    let model = RequiredOptionalModel(value: nil)
    var draft = RequiredOptionalModel.Draft()

    #expect(draft.value == nil)
    #expect(!draft.isComplete)
    #expect(draft.missingFields == [.value])
    #expect(draft.make() == nil)

    draft.value = nil
    #expect(draft.isComplete)
    #expect(draft.make() == model)

    let data = try JSONEncoder().encode(draft)
    let decoded = try JSONDecoder().decode(
      RequiredOptionalModel.Draft.self,
      from: data
    )
    #expect(decoded == draft)
    #expect(decoded.isComplete)

    draft.unset(\.value)
    #expect(!draft.isComplete)
    #expect(draft.make() == nil)

    let seededDraft = RequiredOptionalModel.Draft(from: model)
    #expect(seededDraft.isComplete)
    #expect(seededDraft.make() == model)
  }

  @Test("uses model and explicit draft defaults")
  func defaultValues() throws {
    var draft = DefaultedModel.Draft()

    requireDefaultValueTypes(
      retryCount: draft.retryCount,
      title: draft.title,
      pageSize: draft.pageSize,
      id: draft.id
    )
    #expect(draft.retryCount == 3)
    #expect(draft.title == "Untitled")
    #expect(draft.pageSize == 5)
    #expect(draft.id == 7)
    #expect(draft.missingFields == [.required])

    draft.required = "Ready"
    #expect(
      draft.make()
        == DefaultedModel(
          retryCount: 3,
          title: "Untitled",
          pageSize: 5,
          id: 7,
          required: "Ready"
        )
    )

    draft.retryCount = 10
    draft.title = "Custom"
    draft.pageSize = 50
    draft.id = 42
    let model = try draft.makeOrThrow()

    #expect(model.retryCount == 10)
    #expect(model.title == "Custom")
    #expect(model.pageSize == 50)
    #expect(model.id == 42)

    let seededDraft = DefaultedModel.Draft(from: model)
    #expect(seededDraft.retryCount == 10)
    #expect(seededDraft.title == "Custom")
    #expect(seededDraft.pageSize == 50)
    #expect(seededDraft.id == 42)
    #expect(seededDraft.required == "Ready")
  }

  @Test("does not depend on a synthesized memberwise initializer")
  func customInitializer() {
    let model = CustomInitializedModel(seed: 42)

    #expect(CustomInitializedModel.Draft(from: model).make() == model)
  }

  @Test("avoids collisions with generated parameter names")
  func generatedNameCollision() {
    let model = DraftNamedPropertyModel(draft: 1, draftValue: 2)
    let draft = DraftNamedPropertyModel.Draft(from: model)

    #expect(draft.make() == model)
  }

  @Test("supports constrained generic models")
  func genericModel() {
    let model = GenericModel(value: 42)

    #expect(GenericModel.Draft(from: model).make() == model)
  }

  @Test("supports defaults in constrained generic models")
  func genericDefaultModel() {
    let draft = GenericDefaultModel<Int>.Draft()

    #expect(draft.value == 42)
    #expect(draft.isComplete)
    #expect(draft.make() == GenericDefaultModel(value: 42))
  }

  @Test("omits ignored properties and initialized constants")
  func ignoredProperties() throws {
    let model = IgnoredPropertyModel(id: 42, cache: "transient")
    let draft = IgnoredPropertyModel.Draft(from: model)
    let restored = try draft.makeOrThrow()

    #expect(restored.id == 42)
    #expect(restored.cache == "default-cache")
    #expect(restored.schemaVersion == 1)
  }

  @Test("uses a model-defined init(draft:) for validation")
  func modelValidation() {
    var draft = ValidatedModel.Draft()
    draft.id = -1

    #expect(draft.isComplete)
    #expect(draft.make() == nil)
    #expect(throws: ValidatedModel.Draft.ValidationError.rejectedByModel) {
      try draft.makeOrThrow()
    }

    draft.id = 42
    #expect(draft.make() == ValidatedModel(id: 42))
  }

  @Test("propagates errors from a throwing init(draft:)")
  func throwingModelValidation() throws {
    var draft = ThrowingValidatedModel.Draft()
    draft.id = -1

    #expect(throws: ModelValidationError.invalidID) {
      try draft.makeOrThrow()
    }
    #expect(draft.make() == nil)

    draft.id = 42
    #expect(try draft.makeOrThrow().id == 42)
  }

  @Test("copies declared conformances to the draft")
  func protocolConformances() throws {
    let draft = SomeModel.Draft(
      from: SomeModel(id: 42, title: "Protocols")
    )
    let identifiableDraft = IdentifiableModel.Draft(
      from: IdentifiableModel(id: 7)
    )

    requireCommonConformances(draft)
    requireIdentifiable(identifiableDraft)

    let data = try JSONEncoder().encode(draft)
    let decoded = try JSONDecoder().decode(SomeModel.Draft.self, from: data)
    #expect(decoded == draft)
  }

  @Test("creates and restores a nested draft")
  func nestedDraft() throws {
    var draft = NestedBook.Draft()

    #expect(!draft.isComplete)
    #expect(draft.missingFields == [.title, .author])

    draft.title = "Nested models"
    draft.author.name = "Taylor"

    #expect(draft.isComplete)
    let model = try draft.makeOrThrow()
    #expect(
      model
        == NestedBook(
          title: "Nested models",
          author: NestedAuthor(name: "Taylor", nickname: nil)
        )
    )

    draft.author.unset(\.name)
    #expect(draft.missingFields == [.author])
    #expect(draft.make() == nil)

    let seeded = NestedBook.Draft(from: model)
    #expect(seeded.author.name == "Taylor")
    #expect(seeded.isComplete)
    #expect(seeded.make() == model)

    requireCommonConformances(seeded)
    let data = try JSONEncoder().encode(seeded)
    let decoded = try JSONDecoder().decode(
      NestedBook.Draft.self,
      from: data
    )
    #expect(decoded == seeded)
  }

  @Test("supports an optional nested draft")
  func optionalNestedDraft() throws {
    var draft = OptionalNestedBook.Draft()

    #expect(draft.author == nil)
    #expect(draft.isComplete)
    #expect(try draft.makeOrThrow() == OptionalNestedBook(author: nil))
    #expect(OptionalNestedBook(draft: draft) == OptionalNestedBook(author: nil))

    draft.author = NestedAuthor.Draft()
    #expect(!draft.isComplete)
    #expect(draft.missingFields == [.author])
    #expect(OptionalNestedBook(draft: draft) == nil)

    draft.author?.name = "Taylor"
    #expect(draft.isComplete)
    #expect(
      draft.make()
        == OptionalNestedBook(
          author: NestedAuthor(name: "Taylor", nickname: nil)
        )
    )
    #expect(
      OptionalNestedBook(draft: draft)
        == OptionalNestedBook(
          author: NestedAuthor(name: "Taylor", nickname: nil)
        )
    )

    draft.unset(\.author)
    #expect(draft.isComplete)
    #expect(draft.make() == OptionalNestedBook(author: nil))
  }

  @Test("can require an optional nested draft explicitly")
  func requiredOptionalNestedDraft() throws {
    var draft = RequiredOptionalNestedBook.Draft()

    #expect(draft.author == nil)
    #expect(!draft.isComplete)
    #expect(draft.missingFields == [.author])

    draft.author = nil
    #expect(draft.isComplete)
    #expect(
      draft.make()
        == RequiredOptionalNestedBook(author: nil)
    )

    let data = try JSONEncoder().encode(draft)
    let decoded = try JSONDecoder().decode(
      RequiredOptionalNestedBook.Draft.self,
      from: data
    )
    #expect(decoded.isComplete)
    #expect(decoded.make() == RequiredOptionalNestedBook(author: nil))

    draft.author = NestedAuthor.Draft()
    #expect(!draft.isComplete)

    draft.author?.name = "Taylor"
    #expect(draft.isComplete)

    draft.unset(\.author)
    #expect(!draft.isComplete)

    let seeded = RequiredOptionalNestedBook.Draft(
      from: RequiredOptionalNestedBook(author: nil)
    )
    #expect(seeded.isComplete)
    #expect(seeded.make() == RequiredOptionalNestedBook(author: nil))
  }

  @Test("converts model and explicit defaults into nested drafts")
  func nestedDefaults() throws {
    let draft = NestedDefaultsModel.Draft()

    #expect(draft.author.name == "Model default")
    #expect(draft.editor.name == "Draft default")
    #expect(draft.editor.nickname == "Editor")
    #expect(draft.reviewer?.name == "Optional default")
    #expect(draft.isComplete)

    let model = try draft.makeOrThrow()
    #expect(model.author == NestedDefaultsModel.modelAuthor)
    #expect(model.editor == NestedDefaultsModel.draftEditor)
    #expect(model.reviewer == NestedDefaultsModel.optionalReviewer)

    let changed = NestedDefaultsModel(
      author: NestedAuthor(name: "Changed author", nickname: nil),
      editor: NestedAuthor(name: "Changed editor", nickname: nil)
    )
    let seeded = NestedDefaultsModel.Draft(from: changed)

    #expect(seeded.author.name == "Changed author")
    #expect(seeded.editor.name == "Changed editor")
  }

  @Test("maps nested model rejection to parent rejection")
  func rejectedNestedDraft() {
    var draft = ValidatedNestedBook.Draft()
    draft.author.name = ""

    #expect(draft.isComplete)
    #expect(draft.make() == nil)
    #expect(
      throws: ValidatedNestedBook.Draft.ValidationError.rejectedByModel
    ) {
      try draft.makeOrThrow()
    }
  }
}

private func requireCommonConformances<Value>(_: Value)
where Value: Equatable & Hashable & Codable & Sendable {}

private func requireIdentifiable<Value: Identifiable>(_: Value) {}

private func requireDefaultValueTypes(
  retryCount: Int,
  title: String,
  pageSize: Int,
  id: Int
) {}

#if canImport(SwiftUI)
  private struct DraftBindingProbe: View {
    @State private var draft = SomeModel.Draft()
    @State private var defaultedDraft = DefaultedModel.Draft()

    var body: some View {
      VStack {
        DraftOptionalBindingProbe(value: $draft.title)
        DraftIntBindingProbe(value: $defaultedDraft.retryCount)
      }
    }
  }

  private struct DraftOptionalBindingProbe: View {
    @Binding var value: String?

    var body: some View {
      EmptyView()
    }
  }

  private struct DraftIntBindingProbe: View {
    @Binding var value: Int

    var body: some View {
      EmptyView()
    }
  }
#endif
