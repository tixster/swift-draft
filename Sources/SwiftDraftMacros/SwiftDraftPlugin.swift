import SwiftCompilerPlugin
import SwiftSyntaxMacros

@main
struct SwiftDraftPlugin: CompilerPlugin {
  let providingMacros: [Macro.Type] = [
    DraftMacro.self,
    DraftDefaultMacro.self,
    DraftIgnoredMacro.self,
    DraftRequiredMacro.self,
  ]
}
