import SwiftDraft
import SwiftDraftAccessFixture
import Testing

@Suite("Draft cross-module access")
struct DraftAccessTests {
  @Test("keeps each property's access level")
  func propertyAccess() throws {
    let model = AccessControlledModel(title: "Before", revision: 7)
    var draft = AccessControlledModel.Draft(from: model)

    draft.title = "After"
    draft.priority = 9

    #expect(draft.isComplete)
    #expect(try draft.makeOrThrow().state == "After:7:9:kept")
  }

  @Test("exposes an empty public draft without exposing hidden fields")
  func emptyDraft() {
    let draft = AccessControlledModel.Draft()

    requireInt(draft.priority)
    #expect(draft.priority == 1)
    #expect(!draft.isComplete)
    #expect(draft.make() == nil)
  }

  @Test("copies the model's declared protocol conformances")
  func conformances() {
    let draft = AccessControlledModel.Draft(
      from: AccessControlledModel(title: "Model")
    )

    requireCommonConformances(draft)
  }
}

private func requireCommonConformances<Value>(_: Value)
where Value: Equatable & Hashable & Codable & Sendable {}

private func requireInt(_: Int) {}
