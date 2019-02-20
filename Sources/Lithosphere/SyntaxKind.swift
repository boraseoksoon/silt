/// SyntaxKind.swift
/// Automatically generated by SyntaxGen. Do not edit!
///
/// Copyright 2017-2019, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.
public enum SyntaxKind {
  case token
  case unknown
  case identifierList
  case qualifiedName
  case qualifiedNamePiece
  case moduleDecl
  case declList
  case openImportDecl
  case importDecl
  case dataDecl
  case emptyDataDecl
  case typeIndices
  case typedParameterList
  case ascription
  case explicitTypedParameter
  case implicitTypedParameter
  case constructorList
  case constructorDecl
  case recordDecl
  case fieldDecl
  case recordConstructorDecl
  case recordFieldAssignmentList
  case recordFieldAssignment
  case functionDecl
  case withRuleFunctionClauseDecl
  case normalFunctionClauseDecl
  case absurdFunctionClauseDecl
  case functionWhereClauseDecl
  case letBindingDecl
  case nonFixDecl
  case leftFixDecl
  case rightFixDecl
  case patternClauseList
  case lambdaExpr
  case quantifiedExpr
  case letExpr
  case applicationExpr
  case bindingList
  case namedBinding
  case typedBinding
  case anonymousBinding
  case basicExprList
  case namedBasicExpr
  case underscoreExpr
  case absurdExpr
  case typeBasicExpr
  case parenthesizedExpr
  case typedParameterGroupExpr
  case recordExpr
  case functionClauseList
  case reparsedFunctionDecl
  case reparsedApplicationExpr
  case decl
  case expr
  case typedParameter
  case functionClauseDecl
  case fixityDecl
  case binding
  case basicExpr
}

/// Creates a Syntax node from the provided RawSyntax using the
/// appropriate Syntax type, as specified by its kind.
/// - Parameters:
///   - raw: The raw syntax with which to create this node.
///   - root: The root of this tree, or `nil` if the new node is the root.
func makeSyntax(_ raw: RawSyntax) -> Syntax {
  let data = SyntaxData(raw: raw)
  return makeSyntax(root: nil, data: data)
}

/// Creates a Syntax node from the provided SyntaxData using the
/// appropriate Syntax type, as specified by its kind.
/// - Parameters:
///   - root: The root of this tree, or `nil` if the new node is the root.
///   - data: The data for this new node.
// swiftlint:disable function_body_length
func makeSyntax(root: SyntaxData?, data: SyntaxData) -> Syntax {
  let root = root ?? data
  switch data.raw.kind {
  case .token: return TokenSyntax(root: root, data: data)
  case .unknown: return UnknownSyntax(root: root, data: data)
  case .decl:
    fatalError("cannot construct DeclSyntax directly")
  case .expr:
    fatalError("cannot construct ExprSyntax directly")
  case .typedParameter:
    fatalError("cannot construct TypedParameterSyntax directly")
  case .functionClauseDecl:
    fatalError("cannot construct FunctionClauseDeclSyntax directly")
  case .fixityDecl:
    fatalError("cannot construct FixityDeclSyntax directly")
  case .binding:
    fatalError("cannot construct BindingSyntax directly")
  case .basicExpr:
    fatalError("cannot construct BasicExprSyntax directly")
  case .identifierList:
    return IdentifierListSyntax(root: root, data: data)
  case .qualifiedName:
    return QualifiedNameSyntax(root: root, data: data)
  case .qualifiedNamePiece:
    return QualifiedNamePieceSyntax(root: root, data: data)
  case .moduleDecl:
    return ModuleDeclSyntax(root: root, data: data)
  case .declList:
    return DeclListSyntax(root: root, data: data)
  case .openImportDecl:
    return OpenImportDeclSyntax(root: root, data: data)
  case .importDecl:
    return ImportDeclSyntax(root: root, data: data)
  case .dataDecl:
    return DataDeclSyntax(root: root, data: data)
  case .emptyDataDecl:
    return EmptyDataDeclSyntax(root: root, data: data)
  case .typeIndices:
    return TypeIndicesSyntax(root: root, data: data)
  case .typedParameterList:
    return TypedParameterListSyntax(root: root, data: data)
  case .ascription:
    return AscriptionSyntax(root: root, data: data)
  case .explicitTypedParameter:
    return ExplicitTypedParameterSyntax(root: root, data: data)
  case .implicitTypedParameter:
    return ImplicitTypedParameterSyntax(root: root, data: data)
  case .constructorList:
    return ConstructorListSyntax(root: root, data: data)
  case .constructorDecl:
    return ConstructorDeclSyntax(root: root, data: data)
  case .recordDecl:
    return RecordDeclSyntax(root: root, data: data)
  case .fieldDecl:
    return FieldDeclSyntax(root: root, data: data)
  case .recordConstructorDecl:
    return RecordConstructorDeclSyntax(root: root, data: data)
  case .recordFieldAssignmentList:
    return RecordFieldAssignmentListSyntax(root: root, data: data)
  case .recordFieldAssignment:
    return RecordFieldAssignmentSyntax(root: root, data: data)
  case .functionDecl:
    return FunctionDeclSyntax(root: root, data: data)
  case .withRuleFunctionClauseDecl:
    return WithRuleFunctionClauseDeclSyntax(root: root, data: data)
  case .normalFunctionClauseDecl:
    return NormalFunctionClauseDeclSyntax(root: root, data: data)
  case .absurdFunctionClauseDecl:
    return AbsurdFunctionClauseDeclSyntax(root: root, data: data)
  case .functionWhereClauseDecl:
    return FunctionWhereClauseDeclSyntax(root: root, data: data)
  case .letBindingDecl:
    return LetBindingDeclSyntax(root: root, data: data)
  case .nonFixDecl:
    return NonFixDeclSyntax(root: root, data: data)
  case .leftFixDecl:
    return LeftFixDeclSyntax(root: root, data: data)
  case .rightFixDecl:
    return RightFixDeclSyntax(root: root, data: data)
  case .patternClauseList:
    return PatternClauseListSyntax(root: root, data: data)
  case .lambdaExpr:
    return LambdaExprSyntax(root: root, data: data)
  case .quantifiedExpr:
    return QuantifiedExprSyntax(root: root, data: data)
  case .letExpr:
    return LetExprSyntax(root: root, data: data)
  case .applicationExpr:
    return ApplicationExprSyntax(root: root, data: data)
  case .bindingList:
    return BindingListSyntax(root: root, data: data)
  case .namedBinding:
    return NamedBindingSyntax(root: root, data: data)
  case .typedBinding:
    return TypedBindingSyntax(root: root, data: data)
  case .anonymousBinding:
    return AnonymousBindingSyntax(root: root, data: data)
  case .basicExprList:
    return BasicExprListSyntax(root: root, data: data)
  case .namedBasicExpr:
    return NamedBasicExprSyntax(root: root, data: data)
  case .underscoreExpr:
    return UnderscoreExprSyntax(root: root, data: data)
  case .absurdExpr:
    return AbsurdExprSyntax(root: root, data: data)
  case .typeBasicExpr:
    return TypeBasicExprSyntax(root: root, data: data)
  case .parenthesizedExpr:
    return ParenthesizedExprSyntax(root: root, data: data)
  case .typedParameterGroupExpr:
    return TypedParameterGroupExprSyntax(root: root, data: data)
  case .recordExpr:
    return RecordExprSyntax(root: root, data: data)
  case .functionClauseList:
    return FunctionClauseListSyntax(root: root, data: data)
  case .reparsedFunctionDecl:
    return ReparsedFunctionDeclSyntax(root: root, data: data)
  case .reparsedApplicationExpr:
    return ReparsedApplicationExprSyntax(root: root, data: data)
  }
}
