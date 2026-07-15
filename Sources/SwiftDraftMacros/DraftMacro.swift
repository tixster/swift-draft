import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

public struct DraftMacro: ExtensionMacro {
  public static func expansion(
    of node: AttributeSyntax,
    attachedTo declaration: some DeclGroupSyntax,
    providingExtensionsOf type: some TypeSyntaxProtocol,
    conformingTo protocols: [TypeSyntax],
    in context: some MacroExpansionContext
  ) throws -> [ExtensionDeclSyntax] {
    guard let structure = declaration.as(StructDeclSyntax.self) else {
      context.diagnose(
        Diagnostic(
          node: Syntax(declaration),
          message: DraftDiagnostic(
            id: "requires-struct",
            message: "@Draft can only be attached to a struct"
          )
        )
      )
      return []
    }

    guard !hasDraftDeclaration(in: structure) else {
      context.diagnose(
        Diagnostic(
          node: Syntax(structure.name),
          message: DraftDiagnostic(
            id: "duplicate-draft",
            message: "@Draft cannot generate 'Draft' because the type already declares that name"
          )
        )
      )
      return []
    }

    let customInitializer = customDraftInitializer(in: structure)
    var properties: [DraftProperty] = []
    var hasErrors = false

    if let customInitializer, customInitializer.isAsync {
      context.diagnose(
        Diagnostic(
          node: Syntax(customInitializer.declaration),
          message: DraftDiagnostic(
            id: "async-draft-initializer",
            message: "@Draft does not support an async init(draft:) initializer"
          )
        )
      )
      hasErrors = true
    }

    for member in structure.memberBlock.members {
      guard let variable = member.decl.as(VariableDeclSyntax.self) else {
        continue
      }

      let isIgnored = variable.hasDraftIgnoredAttribute
      let draftDefaultAttribute = variable.draftDefaultAttribute
      let explicitDraftDefault = variable.draftDefaultExpression
      let draftNestedAttribute = variable.draftNestedAttribute

      if let draftNestedAttribute {
        if isIgnored {
          context.diagnose(
            Diagnostic(
              node: Syntax(draftNestedAttribute),
              message: DraftDiagnostic(
                id: "nested-ignored-conflict",
                message: "@DraftNested cannot be combined with @DraftIgnored"
              )
            )
          )
          hasErrors = true
          continue
        }

        if variable.isTypeProperty
          || !variable.bindings.contains(where: \.isStoredProperty)
        {
          context.diagnose(
            Diagnostic(
              node: Syntax(draftNestedAttribute),
              message: DraftDiagnostic(
                id: "nested-requires-instance-property",
                message:
                  "@DraftNested can only be attached to an instance stored property"
              )
            )
          )
          hasErrors = true
          continue
        }
      }

      if let draftDefaultAttribute {
        if isIgnored {
          context.diagnose(
            Diagnostic(
              node: Syntax(draftDefaultAttribute),
              message: DraftDiagnostic(
                id: "default-ignored-conflict",
                message: "@DraftDefault cannot be combined with @DraftIgnored"
              )
            )
          )
          hasErrors = true
          continue
        }

        if variable.hasDraftRequiredAttribute {
          context.diagnose(
            Diagnostic(
              node: Syntax(draftDefaultAttribute),
              message: DraftDiagnostic(
                id: "default-required-conflict",
                message: "@DraftDefault cannot be combined with @DraftRequired"
              )
            )
          )
          hasErrors = true
          continue
        }

        if explicitDraftDefault == nil {
          context.diagnose(
            Diagnostic(
              node: Syntax(draftDefaultAttribute),
              message: DraftDiagnostic(
                id: "default-argument",
                message: "@DraftDefault requires exactly one unlabeled value"
              )
            )
          )
          hasErrors = true
          continue
        }

        if variable.isTypeProperty
          || !variable.bindings.contains(where: \.isStoredProperty)
        {
          context.diagnose(
            Diagnostic(
              node: Syntax(draftDefaultAttribute),
              message: DraftDiagnostic(
                id: "default-requires-instance-property",
                message:
                  "@DraftDefault can only be attached to an instance stored property"
              )
            )
          )
          hasErrors = true
          continue
        }
      }

      guard !variable.isTypeProperty else {
        continue
      }

      if variable.isLazy, !isIgnored {
        context.diagnose(
          Diagnostic(
            node: Syntax(variable),
            message: DraftDiagnostic(
              id: "lazy-property",
              message:
                "@Draft does not support lazy stored properties; add @DraftIgnored to exclude it"
            )
          )
        )
        hasErrors = true
        continue
      }

      for binding in variable.bindings where binding.isStoredProperty {
        if isIgnored {
          if binding.initializer == nil, customInitializer == nil {
            context.diagnose(
              Diagnostic(
                node: Syntax(binding.pattern),
                message: DraftDiagnostic(
                  id: "ignored-without-default",
                  message:
                    "@DraftIgnored requires a default value or a custom init(draft:) initializer"
                )
              )
            )
            hasErrors = true
          }
          continue
        }

        // An initialized constant cannot be assigned again from init(draft:), and
        // its declaration already provides the value needed by the model.
        if variable.bindingSpecifier.tokenKind == .keyword(.let),
          binding.initializer != nil
        {
          if let draftDefaultAttribute {
            context.diagnose(
              Diagnostic(
                node: Syntax(draftDefaultAttribute),
                message: DraftDiagnostic(
                  id: "default-initialized-let",
                  message:
                    "@DraftDefault requires an uninitialized 'let'; remove the model initializer"
                )
              )
            )
            hasErrors = true
          }
          continue
        }

        guard let identifier = binding.pattern.as(IdentifierPatternSyntax.self) else {
          context.diagnose(
            Diagnostic(
              node: Syntax(binding.pattern),
              message: DraftDiagnostic(
                id: "unsupported-pattern",
                message: "@Draft requires each stored property to use an identifier pattern"
              )
            )
          )
          hasErrors = true
          continue
        }

        guard let propertyType = binding.typeAnnotation?.type else {
          context.diagnose(
            Diagnostic(
              node: Syntax(binding.pattern),
              message: DraftDiagnostic(
                id: "missing-type",
                message: "@Draft requires an explicit type annotation for every stored property"
              )
            )
          )
          hasErrors = true
          continue
        }

        if propertyType.containsSomeSpecifier {
          context.diagnose(
            Diagnostic(
              node: Syntax(propertyType),
              message: DraftDiagnostic(
                id: "opaque-property",
                message:
                  "@Draft cannot store an opaque 'some' type; add @DraftIgnored to exclude it"
              )
            )
          )
          hasErrors = true
          continue
        }

        if DraftProperty.reservedNames.contains(identifier.identifier.text) {
          context.diagnose(
            Diagnostic(
              node: Syntax(identifier),
              message: DraftDiagnostic(
                id: "reserved-property-name",
                message:
                  "@Draft cannot generate its API because '\(identifier.identifier.text)' is a reserved draft member name"
              )
            )
          )
          hasErrors = true
          continue
        }

        let isModelOptional = propertyType.isOptionalType
        let nestedModelType: TypeSyntax?
        if let draftNestedAttribute {
          let candidate = propertyType.optionalWrappedType ?? propertyType
          guard candidate.isNominalTypeReference else {
            context.diagnose(
              Diagnostic(
                node: Syntax(draftNestedAttribute),
                message: DraftDiagnostic(
                  id: "nested-model-type",
                  message:
                    "@DraftNested requires a model type with a nested Draft type"
                )
              )
            )
            hasErrors = true
            continue
          }
          nestedModelType = candidate.trimmed
        } else {
          nestedModelType = nil
        }
        let requiresExplicitValue =
          variable.hasDraftRequiredAttribute
          && isModelOptional
        let modelDefault = binding.initializer.map { $0.value.trimmed }
        let defaultExpression =
          explicitDraftDefault
          ?? (requiresExplicitValue ? nil : modelDefault)

        properties.append(
          DraftProperty(
            name: identifier.identifier.trimmed,
            type: propertyType.trimmed,
            modifiers: variable.draftPropertyModifiers,
            accessLevel: variable.draftDeclaredAccessLevel,
            isModelOptional: isModelOptional,
            nestedModelType: nestedModelType,
            requiresExplicitValue: requiresExplicitValue,
            presenceName: nil,
            defaultExpression: defaultExpression,
            defaultProviderName: nil
          )
        )
      }
    }

    guard !hasErrors else {
      return []
    }

    properties = assigningGeneratedNames(
      to: properties,
      avoiding: declaredMemberNames(in: structure)
    )

    let modelAccess = structure.draftAccessLevel
    let metadataAccess = properties.reduce(modelAccess) { access, property in
      min(access, property.accessLevel)
    }
    let draftDeclaration = try makeDraftDeclaration(
      modelType: TypeSyntax(type),
      modelAccess: modelAccess,
      metadataAccess: metadataAccess,
      inheritanceClause: copiedInheritanceClause(from: structure),
      properties: properties,
      modelGenericParameterNames: Set(
        structure.genericParameterClause?.parameters.map { $0.name.text } ?? []
      ),
      customInitializer: customInitializer
    )
    let defaultProviderDeclarations = try makeDefaultProviderDeclarations(
      properties: properties
    )
    let generatedInitializer: InitializerDeclSyntax? =
      if customInitializer == nil {
        try makeModelInitializer(
          modelAccess: modelAccess,
          properties: properties
        )
      } else {
        nil
      }

    let extensionDeclaration = ExtensionDeclSyntax(
      extendedType: type
    ) {
      for declaration in defaultProviderDeclarations {
        declaration
      }
      draftDeclaration
      if let generatedInitializer {
        generatedInitializer
      }
    }

    return [extensionDeclaration]
  }

  private static func makeDraftDeclaration(
    modelType: TypeSyntax,
    modelAccess: DraftAccessLevel,
    metadataAccess: DraftAccessLevel,
    inheritanceClause: InheritanceClauseSyntax?,
    properties: [DraftProperty],
    modelGenericParameterNames: Set<String>,
    customInitializer: CustomDraftInitializer?
  ) throws -> StructDeclSyntax {
    let fieldDeclaration = makeFieldDeclaration(
      access: metadataAccess,
      properties: properties
    )
    let validationErrorDeclaration = makeValidationErrorDeclaration(
      access: metadataAccess
    )
    let emptyInitializer = try InitializerDeclSyntax(
      "\(raw: modelAccess.prefix)init()"
    ) {}
    let modelInitializer = try makeDraftFromModelInitializer(
      modelType: modelType,
      access: modelAccess,
      properties: properties
    )
    let missingFields = try makeMissingFieldsProperty(
      access: metadataAccess,
      properties: properties
    )
    let isComplete = try VariableDeclSyntax(
      "\(raw: modelAccess.prefix)var isComplete: Bool"
    ) {
      ExprSyntax("missingFields.isEmpty")
    }
    let make = try FunctionDeclSyntax(
      "\(raw: modelAccess.prefix)func make() -> \(modelType)?"
    ) {
      ExprSyntax("try? makeOrThrow()")
    }
    let unset = try makeUnsetFunction(
      access: modelAccess,
      properties: properties,
      modelGenericParameterNames: modelGenericParameterNames
    )
    let makeOrThrow = try makeOrThrowFunction(
      modelType: modelType,
      access: modelAccess,
      customInitializer: customInitializer
    )

    return StructDeclSyntax(
      modifiers: modelAccess.modifiers,
      name: .identifier("Draft"),
      inheritanceClause: inheritanceClause
    ) {
      for property in properties {
        property.declaration(modelType: modelType)
        if let presenceDeclaration = property.presenceDeclaration {
          presenceDeclaration
        }
      }
      fieldDeclaration
      validationErrorDeclaration
      emptyInitializer
      modelInitializer
      missingFields
      isComplete
      unset
      make
      makeOrThrow
    }
  }

  private static func makeDefaultProviderDeclarations(
    properties: [DraftProperty]
  ) throws -> [FunctionDeclSyntax] {
    try properties.compactMap { property in
      guard
        let expression = property.defaultExpression,
        let providerName = property.defaultProviderName
      else {
        return nil
      }

      return try FunctionDeclSyntax(
        "private static func \(providerName)() -> \(property.type)"
      ) {
        expression
      }
    }
  }

  private static func makeFieldDeclaration(
    access: DraftAccessLevel,
    properties: [DraftProperty]
  ) -> EnumDeclSyntax {
    EnumDeclSyntax(
      modifiers: access.modifiers,
      name: .identifier("Field"),
      inheritanceClause: inheritanceClause(
        names: ["Hashable", "Sendable"]
      )
    ) {
      for property in properties {
        EnumCaseDeclSyntax {
          EnumCaseElementSyntax(name: property.name)
        }
      }
    }
  }

  private static func makeValidationErrorDeclaration(
    access: DraftAccessLevel
  ) -> EnumDeclSyntax {
    let setOfFields = genericType(
      named: "Set",
      argument: IdentifierTypeSyntax(name: .identifier("Field"))
    )
    let missingFieldsParameters = EnumCaseParameterClauseSyntax(
      parameters: EnumCaseParameterListSyntax([
        EnumCaseParameterSyntax(type: setOfFields)
      ])
    )

    return EnumDeclSyntax(
      modifiers: access.modifiers,
      name: .identifier("ValidationError"),
      inheritanceClause: inheritanceClause(
        names: ["Error", "Equatable", "Sendable"]
      )
    ) {
      EnumCaseDeclSyntax {
        EnumCaseElementSyntax(
          name: .identifier("missingFields"),
          parameterClause: missingFieldsParameters
        )
      }
      EnumCaseDeclSyntax {
        EnumCaseElementSyntax(name: .identifier("rejectedByModel"))
      }
    }
  }

  private static func makeDraftFromModelInitializer(
    modelType: TypeSyntax,
    access: DraftAccessLevel,
    properties: [DraftProperty]
  ) throws -> InitializerDeclSyntax {
    try InitializerDeclSyntax(
      "\(raw: access.prefix)init(from model: \(modelType))"
    ) {
      for property in properties {
        if let nestedDraftType = property.nestedDraftType {
          if property.isModelOptional {
            ExprSyntax(
              "self.\(property.name) = model.\(property.name).map { \(nestedDraftType)(from: $0) }"
            )
          } else {
            ExprSyntax(
              "self.\(property.name) = \(nestedDraftType)(from: model.\(property.name))"
            )
          }
        } else {
          ExprSyntax("self.\(property.name) = model.\(property.name)")
        }
        if let presenceName = property.presenceName {
          ExprSyntax("self.\(presenceName) = true")
        }
      }
    }
  }

  private static func makeMissingFieldsProperty(
    access: DraftAccessLevel,
    properties: [DraftProperty]
  ) throws -> VariableDeclSyntax {
    let requiredProperties = properties.filter {
      $0.presenceName != nil || $0.requiresNonOptionalValue || $0.isNested
    }

    return try VariableDeclSyntax(
      "\(raw: access.prefix)var missingFields: Set<Field>"
    ) {
      if requiredProperties.isEmpty {
        StmtSyntax("return []")
      } else {
        DeclSyntax("var fields: Set<Field> = []")
        for property in requiredProperties {
          if let presenceName = property.presenceName {
            ExprSyntax(
              "if !\(presenceName) { fields.insert(.\(property.name)) }"
            )
          }

          if property.isNested {
            if property.isModelOptional {
              ExprSyntax(
                "if let \(property.name), !\(property.name).isComplete { fields.insert(.\(property.name)) }"
              )
            } else {
              ExprSyntax(
                "if !\(property.name).isComplete { fields.insert(.\(property.name)) }"
              )
            }
          } else if property.requiresNonOptionalValue {
            ExprSyntax(
              "if \(property.name) == nil { fields.insert(.\(property.name)) }"
            )
          }
        }
        StmtSyntax("return fields")
      }
    }
  }

  private static func makeUnsetFunction(
    access: DraftAccessLevel,
    properties: [DraftProperty],
    modelGenericParameterNames: Set<String>
  ) throws -> FunctionDeclSyntax {
    let valueType = uniqueName(
      startingWith: "DraftValue",
      avoiding: modelGenericParameterNames
    )

    return try FunctionDeclSyntax(
      "\(raw: access.prefix)mutating func unset<\(raw: valueType)>(_ keyPath: WritableKeyPath<Self, \(raw: valueType)?>)"
    ) {
      ExprSyntax("self[keyPath: keyPath] = nil")
      for property in properties {
        if let presenceName = property.presenceName {
          ExprSyntax(
            "if (keyPath as AnyKeyPath) == \\Self.\(property.name) { self.\(presenceName) = false }"
          )
        }
      }
    }
  }

  private static func makeOrThrowFunction(
    modelType: TypeSyntax,
    access: DraftAccessLevel,
    customInitializer: CustomDraftInitializer?
  ) throws -> FunctionDeclSyntax {
    let isFailable = customInitializer?.isFailable ?? true
    let isThrowing = customInitializer?.isThrowing ?? false

    return try FunctionDeclSyntax(
      "\(raw: access.prefix)func makeOrThrow() throws -> \(modelType)"
    ) {
      DeclSyntax("let missingFields = missingFields")
      StmtSyntax(
        "guard missingFields.isEmpty else { throw ValidationError.missingFields(missingFields) }"
      )

      if isFailable {
        if isThrowing {
          StmtSyntax(
            "guard let model = try \(modelType)(draft: self) else { throw ValidationError.rejectedByModel }"
          )
        } else {
          StmtSyntax(
            "guard let model = \(modelType)(draft: self) else { throw ValidationError.rejectedByModel }"
          )
        }
        StmtSyntax("return model")
      } else if isThrowing {
        StmtSyntax("return try \(modelType)(draft: self)")
      } else {
        StmtSyntax("return \(modelType)(draft: self)")
      }
    }
  }

  private static func makeModelInitializer(
    modelAccess: DraftAccessLevel,
    properties: [DraftProperty]
  ) throws -> InitializerDeclSyntax {
    let draftParameter = uniqueName(
      startingWith: "draft",
      avoiding: Set(properties.map(\.identifier))
    )
    var generatedNames = Set(properties.map(\.identifier))
    generatedNames.insert(draftParameter)
    let nestedDraftName = uniqueName(
      startingWith: "nestedDraft",
      avoiding: generatedNames
    )
    generatedNames.insert(nestedDraftName)
    let nestedModelName = uniqueName(
      startingWith: "nestedModel",
      avoiding: generatedNames
    )
    let header =
      if draftParameter == "draft" {
        "\(modelAccess.prefix)init?(draft: Draft)"
      } else {
        "\(modelAccess.prefix)init?(draft \(draftParameter): Draft)"
      }

    return try InitializerDeclSyntax("\(raw: header)") {
      for property in properties {
        if let presenceName = property.presenceName {
          try GuardStmtSyntax(
            "guard \(raw: draftParameter).\(presenceName) else"
          ) {
            StmtSyntax("return nil")
          }
        }

        if property.isNested {
          if property.isModelOptional {
            DeclSyntax("let \(property.name): \(property.type)")
            ExprSyntax(
              """
              if let \(raw: nestedDraftName) = \(raw: draftParameter).\(property.name) {
                guard let \(raw: nestedModelName) = \(raw: nestedDraftName).make() else {
                  return nil
                }
                \(property.name) = \(raw: nestedModelName)
              } else {
                \(property.name) = nil
              }
              """
            )
          } else {
            try GuardStmtSyntax(
              "guard let \(property.name) = \(raw: draftParameter).\(property.name).make() else"
            ) {
              StmtSyntax("return nil")
            }
          }
        } else if property.requiresNonOptionalValue {
          try GuardStmtSyntax(
            "guard let \(property.name) = \(raw: draftParameter).\(property.name) else"
          ) {
            StmtSyntax("return nil")
          }
        }
      }
      for property in properties {
        if property.usesDirectDraftValue {
          ExprSyntax(
            "self.\(property.name) = \(raw: draftParameter).\(property.name)"
          )
        } else {
          ExprSyntax("self.\(property.name) = \(property.name)")
        }
      }
    }
  }

  private static func assigningGeneratedNames(
    to properties: [DraftProperty],
    avoiding declaredNames: Set<String>
  ) -> [DraftProperty] {
    var usedNames = Set(properties.map(\.identifier))
      .union(DraftProperty.reservedNames)
      .union(declaredNames)

    return properties.map { property in
      var property = property

      if property.requiresExplicitValue {
        let presenceName = uniqueName(
          startingWith: "__swiftDraft_\(property.identifier)IsSet",
          avoiding: usedNames
        )
        usedNames.insert(presenceName)
        property = property.withPresenceName(.identifier(presenceName))
      }

      if property.defaultExpression != nil {
        let providerName = uniqueName(
          startingWith: "__swiftDraftDefault_\(property.identifier)",
          avoiding: usedNames
        )
        usedNames.insert(providerName)
        property = property.withDefaultProviderName(.identifier(providerName))
      }

      return property
    }
  }

  private static func declaredMemberNames(
    in structure: StructDeclSyntax
  ) -> Set<String> {
    var names: Set<String> = []

    for member in structure.memberBlock.members {
      if let variable = member.decl.as(VariableDeclSyntax.self) {
        for binding in variable.bindings {
          if let identifier = binding.pattern.as(IdentifierPatternSyntax.self) {
            names.insert(identifier.identifier.text)
          }
        }
      } else if let function = member.decl.as(FunctionDeclSyntax.self) {
        names.insert(function.name.text)
      } else if let structure = member.decl.as(StructDeclSyntax.self) {
        names.insert(structure.name.text)
      } else if let classDeclaration = member.decl.as(ClassDeclSyntax.self) {
        names.insert(classDeclaration.name.text)
      } else if let enumeration = member.decl.as(EnumDeclSyntax.self) {
        names.insert(enumeration.name.text)
      } else if let actor = member.decl.as(ActorDeclSyntax.self) {
        names.insert(actor.name.text)
      } else if let typeAlias = member.decl.as(TypeAliasDeclSyntax.self) {
        names.insert(typeAlias.name.text)
      }
    }

    return names
  }

  private static func copiedInheritanceClause(
    from structure: StructDeclSyntax
  ) -> InheritanceClauseSyntax? {
    guard let inheritedTypes = structure.inheritanceClause?.inheritedTypes else {
      return nil
    }

    let conformances = Array(
      inheritedTypes.filter { inheritedType in
        !inheritedType.type.trimmedDescription.hasPrefix("~")
      }
    )
    guard !conformances.isEmpty else {
      return nil
    }

    return InheritanceClauseSyntax(
      inheritedTypes: InheritedTypeListSyntax(
        conformances.enumerated().map { index, inheritedType in
          InheritedTypeSyntax(
            type: inheritedType.type.trimmed,
            trailingComma: index == conformances.count - 1
              ? nil
              : .commaToken()
          )
        }
      )
    )
  }

  private static func inheritanceClause(
    names: [String]
  ) -> InheritanceClauseSyntax {
    InheritanceClauseSyntax(
      inheritedTypes: InheritedTypeListSyntax(
        names.enumerated().map { index, name in
          InheritedTypeSyntax(
            type: IdentifierTypeSyntax(name: .identifier(name)),
            trailingComma: index == names.indices.last ? nil : .commaToken()
          )
        }
      )
    )
  }

  fileprivate static func genericType(
    named name: String,
    argument: some TypeSyntaxProtocol
  ) -> IdentifierTypeSyntax {
    IdentifierTypeSyntax(
      name: .identifier(name),
      genericArgumentClause: GenericArgumentClauseSyntax(
        arguments: GenericArgumentListSyntax([
          GenericArgumentSyntax(argument: .type(TypeSyntax(argument)))
        ])
      )
    )
  }

  private static func customDraftInitializer(
    in structure: StructDeclSyntax
  ) -> CustomDraftInitializer? {
    for member in structure.memberBlock.members {
      guard let initializer = member.decl.as(InitializerDeclSyntax.self) else {
        continue
      }
      let parameters = initializer.signature.parameterClause.parameters
      guard parameters.count == 1, let parameter = parameters.first else {
        continue
      }
      guard parameter.firstName.text == "draft" else {
        continue
      }

      let typeName = parameter.type.trimmedDescription
      let acceptedTypeNames: Set<String> = [
        "Draft",
        "Self.Draft",
        "\(structure.name.text).Draft",
      ]
      guard acceptedTypeNames.contains(typeName) else {
        continue
      }

      return CustomDraftInitializer(
        declaration: initializer,
        isFailable: initializer.optionalMark != nil,
        isThrowing: initializer.signature.effectSpecifiers?.throwsClause != nil,
        isAsync: initializer.signature.effectSpecifiers?.asyncSpecifier != nil
      )
    }
    return nil
  }

  private static func hasDraftDeclaration(in structure: StructDeclSyntax) -> Bool {
    structure.memberBlock.members.contains { member in
      if let nestedStruct = member.decl.as(StructDeclSyntax.self) {
        return nestedStruct.name.text == "Draft"
      }
      if let nestedClass = member.decl.as(ClassDeclSyntax.self) {
        return nestedClass.name.text == "Draft"
      }
      if let nestedEnum = member.decl.as(EnumDeclSyntax.self) {
        return nestedEnum.name.text == "Draft"
      }
      if let nestedActor = member.decl.as(ActorDeclSyntax.self) {
        return nestedActor.name.text == "Draft"
      }
      if let typeAlias = member.decl.as(TypeAliasDeclSyntax.self) {
        return typeAlias.name.text == "Draft"
      }
      return false
    }
  }

  private static func uniqueName(
    startingWith base: String,
    avoiding names: Set<String>
  ) -> String {
    guard names.contains(base) else {
      return base
    }

    var candidate = "\(base)Value"
    var suffix = 2
    while names.contains(candidate) {
      candidate = "\(base)Value\(suffix)"
      suffix += 1
    }
    return candidate
  }
}

private struct CustomDraftInitializer {
  let declaration: InitializerDeclSyntax
  let isFailable: Bool
  let isThrowing: Bool
  let isAsync: Bool
}

private struct DraftProperty {
  static let reservedNames: Set<String> = [
    "isComplete",
    "make",
    "makeOrThrow",
    "missingFields",
    "unset",
  ]

  let name: TokenSyntax
  let type: TypeSyntax
  let modifiers: DeclModifierListSyntax
  let accessLevel: DraftAccessLevel
  let isModelOptional: Bool
  let nestedModelType: TypeSyntax?
  let requiresExplicitValue: Bool
  let presenceName: TokenSyntax?
  let defaultExpression: ExprSyntax?
  let defaultProviderName: TokenSyntax?

  var identifier: String {
    name.text
  }

  var hasDefault: Bool {
    defaultExpression != nil
  }

  var isNested: Bool {
    nestedModelType != nil
  }

  var nestedDraftType: TypeSyntax? {
    nestedModelType.map {
      TypeSyntax(
        MemberTypeSyntax(
          baseType: $0,
          name: .identifier("Draft")
        )
      )
    }
  }

  var requiresNonOptionalValue: Bool {
    !isNested && !isModelOptional && !hasDefault
  }

  var usesDirectDraftValue: Bool {
    !isNested && (isModelOptional || hasDefault)
  }

  func declaration(modelType: TypeSyntax) -> VariableDeclSyntax {
    let fieldType: TypeSyntax
    let initialValue: ExprSyntax

    if let nestedDraftType {
      fieldType =
        isModelOptional
        ? TypeSyntax(OptionalTypeSyntax(wrappedType: nestedDraftType))
        : nestedDraftType

      if let defaultProviderName {
        if isModelOptional {
          initialValue = ExprSyntax(
            "\(modelType).\(defaultProviderName)().map { \(nestedDraftType)(from: $0) }"
          )
        } else {
          initialValue = ExprSyntax(
            "\(nestedDraftType)(from: \(modelType).\(defaultProviderName)())"
          )
        }
      } else if isModelOptional {
        initialValue = ExprSyntax(NilLiteralExprSyntax())
      } else {
        initialValue = ExprSyntax("\(nestedDraftType)()")
      }
    } else {
      fieldType =
        isModelOptional || hasDefault
        ? type
        : TypeSyntax(OptionalTypeSyntax(wrappedType: type))
      initialValue =
        if let defaultProviderName {
          ExprSyntax("\(modelType).\(defaultProviderName)()")
        } else {
          ExprSyntax(NilLiteralExprSyntax())
        }
    }
    let accessorBlock: AccessorBlockSyntax? = presenceName.map { presenceName in
      AccessorBlockSyntax(
        accessors: .accessors(
          AccessorDeclListSyntax([
            AccessorDeclSyntax(
              accessorSpecifier: .keyword(.didSet),
              body: CodeBlockSyntax {
                ExprSyntax("self.\(presenceName) = true")
              }
            )
          ])
        )
      )
    }

    return VariableDeclSyntax(
      modifiers: modifiers,
      bindingSpecifier: .keyword(.var)
    ) {
      PatternBindingSyntax(
        pattern: IdentifierPatternSyntax(identifier: name),
        typeAnnotation: TypeAnnotationSyntax(type: fieldType),
        initializer: InitializerClauseSyntax(value: initialValue),
        accessorBlock: accessorBlock
      )
    }
  }

  var presenceDeclaration: VariableDeclSyntax? {
    guard let presenceName else {
      return nil
    }

    return VariableDeclSyntax(
      modifiers: [.init(name: .keyword(.fileprivate))],
      bindingSpecifier: .keyword(.var)
    ) {
      PatternBindingSyntax(
        pattern: IdentifierPatternSyntax(identifier: presenceName),
        typeAnnotation: TypeAnnotationSyntax(
          type: IdentifierTypeSyntax(name: .identifier("Bool"))
        ),
        initializer: InitializerClauseSyntax(value: BooleanLiteralExprSyntax(false))
      )
    }
  }

  func withPresenceName(_ presenceName: TokenSyntax) -> Self {
    Self(
      name: name,
      type: type,
      modifiers: modifiers,
      accessLevel: accessLevel,
      isModelOptional: isModelOptional,
      nestedModelType: nestedModelType,
      requiresExplicitValue: requiresExplicitValue,
      presenceName: presenceName,
      defaultExpression: defaultExpression,
      defaultProviderName: defaultProviderName
    )
  }

  func withDefaultProviderName(_ defaultProviderName: TokenSyntax) -> Self {
    Self(
      name: name,
      type: type,
      modifiers: modifiers,
      accessLevel: accessLevel,
      isModelOptional: isModelOptional,
      nestedModelType: nestedModelType,
      requiresExplicitValue: requiresExplicitValue,
      presenceName: presenceName,
      defaultExpression: defaultExpression,
      defaultProviderName: defaultProviderName
    )
  }
}

private enum DraftAccessLevel: Int, Comparable {
  case privateAccess
  case fileprivateAccess
  case internalAccess
  case packageAccess
  case publicAccess

  static func < (lhs: Self, rhs: Self) -> Bool {
    lhs.rawValue < rhs.rawValue
  }

  var prefix: String {
    switch self {
    case .privateAccess:
      "private "
    case .fileprivateAccess:
      "fileprivate "
    case .internalAccess:
      ""
    case .packageAccess:
      "package "
    case .publicAccess:
      "public "
    }
  }

  var modifiers: DeclModifierListSyntax {
    guard let keyword else {
      return []
    }
    return DeclModifierListSyntax([
      DeclModifierSyntax(name: .keyword(keyword))
    ])
  }

  private var keyword: Keyword? {
    switch self {
    case .privateAccess:
      .private
    case .fileprivateAccess:
      .fileprivate
    case .internalAccess:
      nil
    case .packageAccess:
      .package
    case .publicAccess:
      .public
    }
  }
}

private struct DraftDiagnostic: DiagnosticMessage {
  let id: String
  let message: String

  var diagnosticID: MessageID {
    MessageID(domain: "SwiftDraft", id: id)
  }

  var severity: DiagnosticSeverity {
    .error
  }
}

extension StructDeclSyntax {
  fileprivate var draftAccessLevel: DraftAccessLevel {
    switch declaredAccessLevel {
    case .publicAccess:
      .publicAccess
    case .packageAccess:
      .packageAccess
    default:
      .internalAccess
    }
  }

  private var declaredAccessLevel: DraftAccessLevel {
    for modifier in modifiers where modifier.detail == nil {
      switch modifier.name.text {
      case "private":
        return .privateAccess
      case "fileprivate":
        return .fileprivateAccess
      case "package":
        return .packageAccess
      case "public", "open":
        return .publicAccess
      default:
        continue
      }
    }
    return .internalAccess
  }
}

extension VariableDeclSyntax {
  fileprivate var draftDeclaredAccessLevel: DraftAccessLevel {
    for modifier in modifiers where modifier.detail == nil {
      switch modifier.name.text {
      case "private":
        // The generated init(draft:) lives in a same-file extension of the
        // model, so it needs file-level read access to this nested field.
        return .fileprivateAccess
      case "fileprivate":
        return .fileprivateAccess
      case "package":
        return .packageAccess
      case "public", "open":
        return .publicAccess
      default:
        continue
      }
    }
    return .internalAccess
  }

  fileprivate var draftPropertyModifiers: DeclModifierListSyntax {
    DeclModifierListSyntax(
      modifiers.compactMap { modifier in
        guard modifier.isAccessModifier else {
          return nil
        }
        if modifier.name.text == "private", modifier.detail == nil {
          return DeclModifierSyntax(name: .keyword(.fileprivate))
        }
        return DeclModifierSyntax(
          name: modifier.name.trimmed,
          detail: modifier.detail?.trimmed
        )
      }
    )
  }

  fileprivate var hasDraftIgnoredAttribute: Bool {
    hasAttribute(named: "DraftIgnored")
  }

  fileprivate var hasDraftRequiredAttribute: Bool {
    hasAttribute(named: "DraftRequired")
  }

  fileprivate var draftDefaultAttribute: AttributeSyntax? {
    attribute(named: "DraftDefault")
  }

  fileprivate var draftNestedAttribute: AttributeSyntax? {
    attribute(named: "DraftNested")
  }

  fileprivate var draftDefaultExpression: ExprSyntax? {
    guard
      let arguments = draftDefaultAttribute?.arguments,
      case .argumentList(let argumentList) = arguments,
      argumentList.count == 1,
      let argument = argumentList.first,
      argument.label == nil
    else {
      return nil
    }

    return argument.expression.trimmed
  }

  private func hasAttribute(named name: String) -> Bool {
    attribute(named: name) != nil
  }

  private func attribute(named name: String) -> AttributeSyntax? {
    for element in attributes {
      guard case .attribute(let attribute) = element else {
        continue
      }
      let attributeName = attribute.attributeName.trimmedDescription
        .split(separator: ".")
        .last
      if attributeName == Substring(name) {
        return attribute
      }
    }
    return nil
  }

  fileprivate var isLazy: Bool {
    modifiers.contains { $0.name.tokenKind == .keyword(.lazy) }
  }

  fileprivate var isTypeProperty: Bool {
    modifiers.contains {
      $0.name.tokenKind == .keyword(.static)
        || $0.name.tokenKind == .keyword(.class)
    }
  }
}

extension DeclModifierSyntax {
  fileprivate var isAccessModifier: Bool {
    switch name.text {
    case "private", "fileprivate", "internal", "package", "public", "open":
      true
    default:
      false
    }
  }
}

extension TypeSyntax {
  fileprivate var containsSomeSpecifier: Bool {
    tokens(viewMode: .sourceAccurate).contains {
      $0.tokenKind == .keyword(.some)
    }
  }

  fileprivate var optionalWrappedType: TypeSyntax? {
    if let optionalType = self.as(OptionalTypeSyntax.self) {
      return optionalType.wrappedType
    }

    if let optionalType = self.as(ImplicitlyUnwrappedOptionalTypeSyntax.self) {
      return optionalType.wrappedType
    }

    if let attributedType = self.as(AttributedTypeSyntax.self) {
      return attributedType.baseType.optionalWrappedType
    }

    if let identifierType = self.as(IdentifierTypeSyntax.self),
      identifierType.name.text == "Optional",
      let argument = identifierType.genericArgumentClause?.arguments.first,
      case .type(let wrappedType) = argument.argument
    {
      return wrappedType
    }

    if let memberType = self.as(MemberTypeSyntax.self),
      memberType.name.text == "Optional",
      memberType.baseType.trimmedDescription == "Swift",
      let argument = memberType.genericArgumentClause?.arguments.first,
      case .type(let wrappedType) = argument.argument
    {
      return wrappedType
    }

    return nil
  }

  fileprivate var isOptionalType: Bool {
    optionalWrappedType != nil
  }

  fileprivate var isNominalTypeReference: Bool {
    self.is(IdentifierTypeSyntax.self) || self.is(MemberTypeSyntax.self)
  }
}

extension PatternBindingSyntax {
  fileprivate var isStoredProperty: Bool {
    guard let accessorBlock else {
      return true
    }

    switch accessorBlock.accessors {
    case .getter:
      return false
    case .accessors(let accessors):
      return accessors.allSatisfy { accessor in
        accessor.accessorSpecifier.tokenKind == .keyword(.willSet)
          || accessor.accessorSpecifier.tokenKind == .keyword(.didSet)
      }
    }
  }
}
