import SwiftDraftMacros
import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import Testing

@Suite("Draft macro")
struct DraftMacroTests {
  @Test("generates the complete draft API")
  func expansion() {
    assertMacroExpansion(
      """
      @Draft
      public struct SomeModel: Equatable, Hashable, Codable, Sendable {
        public var id: Int
        var title: String
        @DraftIgnored var cache: String = "cached"
        let schemaVersion: Int = 1
        static var count = 0
        var displayTitle: String { title.uppercased() }
      }
      """,
      expandedSource: """
        public struct SomeModel: Equatable, Hashable, Codable, Sendable {
          public var id: Int
          var title: String
          var cache: String = "cached"
          let schemaVersion: Int = 1
          static var count = 0
          var displayTitle: String { title.uppercased() }
        }

        extension SomeModel {
          public struct Draft: Equatable, Hashable, Codable, Sendable {
            public var id: Int? = nil
            var title: String? = nil
            enum Field: Hashable, Sendable {
              case id
              case title
            }
            enum ValidationError: Error, Equatable, Sendable {
              case missingFields(Set<Field>)
              case rejectedByModel
            }
            public init() {
            }
            public init(from model: SomeModel) {
              self.id = model.id
              self.title = model.title
            }
            var missingFields: Set<Field> {
              var fields: Set<Field> = []
              if id == nil {
                fields.insert(.id)
              }
              if title == nil {
                fields.insert(.title)
              }
              return fields
            }
            public var isComplete: Bool {
              missingFields.isEmpty
            }
            public mutating func unset<DraftValue>(_ keyPath: WritableKeyPath<Self, DraftValue?>) {
              self[keyPath: keyPath] = nil
            }
            public func make() -> SomeModel? {
              try? makeOrThrow()
            }
            public func makeOrThrow() throws -> SomeModel {
              let missingFields = missingFields
              guard missingFields.isEmpty else {
                throw ValidationError.missingFields(missingFields)
              }
              guard let model = SomeModel(draft: self) else {
                throw ValidationError.rejectedByModel
              }
              return model
            }
          }
          public init?(draft: Draft) {
            guard let id = draft.id else {
              return nil
            }
            guard let title = draft.title else {
              return nil
            }
            self.id = id
            self.title = title
          }
        }
        """,
      macros: [
        "Draft": DraftMacro.self,
        "DraftIgnored": DraftIgnoredMacro.self,
      ],
      indentationWidth: .spaces(2)
    )
  }

  @Test("supports optional and explicitly required optional fields")
  func optionalFieldExpansion() {
    assertMacroExpansion(
      """
      @Draft
      struct Profile: Equatable, Codable {
        var nickname: String?
        @DraftRequired var avatarURL: String?
      }
      """,
      expandedSource: """
        struct Profile: Equatable, Codable {
          var nickname: String?
          var avatarURL: String?
        }

        extension Profile {
          struct Draft: Equatable, Codable {
            var nickname: String? = nil
            var avatarURL: String? = nil {
              didSet {
                self.__swiftDraft_avatarURLIsSet = true
              }
            }
            fileprivate var __swiftDraft_avatarURLIsSet: Bool = false
            enum Field: Hashable, Sendable {
              case nickname
              case avatarURL
            }
            enum ValidationError: Error, Equatable, Sendable {
              case missingFields(Set<Field>)
              case rejectedByModel
            }
            init() {
            }
            init(from model: Profile) {
              self.nickname = model.nickname
              self.avatarURL = model.avatarURL
              self.__swiftDraft_avatarURLIsSet = true
            }
            var missingFields: Set<Field> {
              var fields: Set<Field> = []
              if !__swiftDraft_avatarURLIsSet {
                fields.insert(.avatarURL)
              }
              return fields
            }
            var isComplete: Bool {
              missingFields.isEmpty
            }
            mutating func unset<DraftValue>(_ keyPath: WritableKeyPath<Self, DraftValue?>) {
              self[keyPath: keyPath] = nil
              if (keyPath as AnyKeyPath) == \\Self.avatarURL {
                self.__swiftDraft_avatarURLIsSet = false
              }
            }
            func make() -> Profile? {
              try? makeOrThrow()
            }
            func makeOrThrow() throws -> Profile {
              let missingFields = missingFields
              guard missingFields.isEmpty else {
                throw ValidationError.missingFields(missingFields)
              }
              guard let model = Profile(draft: self) else {
                throw ValidationError.rejectedByModel
              }
              return model
            }
          }
          init?(draft: Draft) {
            guard draft.__swiftDraft_avatarURLIsSet else {
              return nil
            }
            self.nickname = draft.nickname
            self.avatarURL = draft.avatarURL
          }
        }
        """,
      macros: [
        "Draft": DraftMacro.self,
        "DraftRequired": DraftRequiredMacro.self,
      ],
      indentationWidth: .spaces(2)
    )
  }

  @Test("generates model and explicit draft defaults")
  func defaultFieldExpansion() {
    assertMacroExpansion(
      """
      @Draft
      struct Defaults: Equatable {
        static let standardTitle = "Standard"
        var retryCount: Int = 3
        @DraftDefault(Self.standardTitle) var title: String
        @DraftDefault(5) var pageSize: Int = 20
        @DraftDefault(7) let id: Int
        var required: String
      }
      """,
      expandedSource: """
        struct Defaults: Equatable {
          static let standardTitle = "Standard"
          var retryCount: Int = 3
          var title: String
          var pageSize: Int = 20
          let id: Int
          var required: String
        }

        extension Defaults {
          private static func __swiftDraftDefault_retryCount() -> Int {
            3
          }
          private static func __swiftDraftDefault_title() -> String {
            Self.standardTitle
          }
          private static func __swiftDraftDefault_pageSize() -> Int {
            5
          }
          private static func __swiftDraftDefault_id() -> Int {
            7
          }
          struct Draft: Equatable {
            var retryCount: Int = Defaults.__swiftDraftDefault_retryCount()
            var title: String = Defaults.__swiftDraftDefault_title()
            var pageSize: Int = Defaults.__swiftDraftDefault_pageSize()
            var id: Int = Defaults.__swiftDraftDefault_id()
            var required: String? = nil
            enum Field: Hashable, Sendable {
              case retryCount
              case title
              case pageSize
              case id
              case required
            }
            enum ValidationError: Error, Equatable, Sendable {
              case missingFields(Set<Field>)
              case rejectedByModel
            }
            init() {
            }
            init(from model: Defaults) {
              self.retryCount = model.retryCount
              self.title = model.title
              self.pageSize = model.pageSize
              self.id = model.id
              self.required = model.required
            }
            var missingFields: Set<Field> {
              var fields: Set<Field> = []
              if required == nil {
                fields.insert(.required)
              }
              return fields
            }
            var isComplete: Bool {
              missingFields.isEmpty
            }
            mutating func unset<DraftValue>(_ keyPath: WritableKeyPath<Self, DraftValue?>) {
              self[keyPath: keyPath] = nil
            }
            func make() -> Defaults? {
              try? makeOrThrow()
            }
            func makeOrThrow() throws -> Defaults {
              let missingFields = missingFields
              guard missingFields.isEmpty else {
                throw ValidationError.missingFields(missingFields)
              }
              guard let model = Defaults(draft: self) else {
                throw ValidationError.rejectedByModel
              }
              return model
            }
          }
          init?(draft: Draft) {
            guard let required = draft.required else {
              return nil
            }
            self.retryCount = draft.retryCount
            self.title = draft.title
            self.pageSize = draft.pageSize
            self.id = draft.id
            self.required = required
          }
        }
        """,
      macros: [
        "Draft": DraftMacro.self,
        "DraftDefault": DraftDefaultMacro.self,
      ],
      indentationWidth: .spaces(2)
    )
  }

  @Test("diagnoses conflicting default policies")
  func defaultPolicyConflict() {
    assertMacroExpansion(
      """
      @Draft
      struct Profile {
        @DraftRequired
        @DraftDefault("Anonymous")
        var nickname: String?
      }
      """,
      expandedSource: """
        struct Profile {
          var nickname: String?
        }
        """,
      diagnostics: [
        DiagnosticSpec(
          message: "@DraftDefault cannot be combined with @DraftRequired",
          line: 4,
          column: 3
        )
      ],
      macros: [
        "Draft": DraftMacro.self,
        "DraftDefault": DraftDefaultMacro.self,
        "DraftRequired": DraftRequiredMacro.self,
      ],
      indentationWidth: .spaces(2)
    )
  }

  @Test("diagnoses a default on an initialized constant")
  func initializedConstantDefault() {
    assertMacroExpansion(
      """
      @Draft
      struct Constants {
        @DraftDefault(2) let version: Int = 1
      }
      """,
      expandedSource: """
        struct Constants {
          let version: Int = 1
        }
        """,
      diagnostics: [
        DiagnosticSpec(
          message:
            "@DraftDefault requires an uninitialized 'let'; remove the model initializer",
          line: 3,
          column: 3
        )
      ],
      macros: [
        "Draft": DraftMacro.self,
        "DraftDefault": DraftDefaultMacro.self,
      ],
      indentationWidth: .spaces(2)
    )
  }

  @Test("uses a model-defined draft initializer")
  func customInitializer() {
    assertMacroExpansion(
      """
      @Draft
      struct ValidatedModel: Equatable {
        var id: Int

        init?(draft: Draft) {
          guard let id = draft.id, id > 0 else { return nil }
          self.id = id
        }
      }
      """,
      expandedSource: """
        struct ValidatedModel: Equatable {
          var id: Int

          init?(draft: Draft) {
            guard let id = draft.id, id > 0 else { return nil }
            self.id = id
          }
        }

        extension ValidatedModel {
          struct Draft: Equatable {
            var id: Int? = nil
            enum Field: Hashable, Sendable {
              case id
            }
            enum ValidationError: Error, Equatable, Sendable {
              case missingFields(Set<Field>)
              case rejectedByModel
            }
            init() {
            }
            init(from model: ValidatedModel) {
              self.id = model.id
            }
            var missingFields: Set<Field> {
              var fields: Set<Field> = []
              if id == nil {
                fields.insert(.id)
              }
              return fields
            }
            var isComplete: Bool {
              missingFields.isEmpty
            }
            mutating func unset<DraftValue>(_ keyPath: WritableKeyPath<Self, DraftValue?>) {
              self[keyPath: keyPath] = nil
            }
            func make() -> ValidatedModel? {
              try? makeOrThrow()
            }
            func makeOrThrow() throws -> ValidatedModel {
              let missingFields = missingFields
              guard missingFields.isEmpty else {
                throw ValidationError.missingFields(missingFields)
              }
              guard let model = ValidatedModel(draft: self) else {
                throw ValidationError.rejectedByModel
              }
              return model
            }
          }
        }
        """,
      macros: ["Draft": DraftMacro.self],
      indentationWidth: .spaces(2)
    )
  }

  @Test("diagnoses declarations that are not structs")
  func requiresStruct() {
    assertMacroExpansion(
      """
      @Draft
      final class SomeModel {
        var id: Int = 0
      }
      """,
      expandedSource: """
        final class SomeModel {
          var id: Int = 0
        }
        """,
      diagnostics: [
        DiagnosticSpec(
          message: "@Draft can only be attached to a struct",
          line: 1,
          column: 1
        )
      ],
      macros: ["Draft": DraftMacro.self],
      indentationWidth: .spaces(2)
    )
  }

  @Test("diagnoses stored properties without explicit types")
  func requiresExplicitTypes() {
    assertMacroExpansion(
      """
      @Draft
      struct SomeModel {
        var id = 0
      }
      """,
      expandedSource: """
        struct SomeModel {
          var id = 0
        }
        """,
      diagnostics: [
        DiagnosticSpec(
          message: "@Draft requires an explicit type annotation for every stored property",
          line: 3,
          column: 7
        )
      ],
      macros: ["Draft": DraftMacro.self],
      indentationWidth: .spaces(2)
    )
  }

  @Test("requires an ignored property to remain initializable")
  func ignoredPropertyRequiresDefault() {
    assertMacroExpansion(
      """
      @Draft
      struct SomeModel {
        @DraftIgnored var cache: String
      }
      """,
      expandedSource: """
        struct SomeModel {
          var cache: String
        }
        """,
      diagnostics: [
        DiagnosticSpec(
          message: "@DraftIgnored requires a default value or a custom init(draft:) initializer",
          line: 3,
          column: 21
        )
      ],
      macros: [
        "Draft": DraftMacro.self,
        "DraftIgnored": DraftIgnoredMacro.self,
      ],
      indentationWidth: .spaces(2)
    )
  }

  @Test("diagnoses names reserved by the generated API")
  func reservedName() {
    assertMacroExpansion(
      """
      @Draft
      struct SomeModel {
        var isComplete: Bool
      }
      """,
      expandedSource: """
        struct SomeModel {
          var isComplete: Bool
        }
        """,
      diagnostics: [
        DiagnosticSpec(
          message:
            "@Draft cannot generate its API because 'isComplete' is a reserved draft member name",
          line: 3,
          column: 7
        )
      ],
      macros: ["Draft": DraftMacro.self],
      indentationWidth: .spaces(2)
    )
  }
}
