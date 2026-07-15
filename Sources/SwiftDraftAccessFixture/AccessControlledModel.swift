import SwiftDraft

@Draft
public struct AccessControlledModel: Equatable, Hashable, Codable, Sendable {
  public var title: String
  public var priority: Int = 1
  var revision: Int
  private var secret: String

  public init(title: String, revision: Int = 1) {
    self.title = title
    self.revision = revision
    self.secret = "kept"
  }

  public var state: String {
    "\(title):\(revision):\(priority):\(secret)"
  }
}
