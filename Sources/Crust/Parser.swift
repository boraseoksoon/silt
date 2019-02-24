/// Parser.swift
///
/// Copyright 2017-2018, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.
import Lithosphere

extension Diagnostic.Message {
  static func unexpectedToken(
    _ token: TokenSyntax, expected: TokenKind? = nil) -> Diagnostic.Message {
    var msg: String
    switch token.tokenKind {
    case .leftBrace where token.isImplicit:
      msg = "unexpected opening scope"
    case .rightBrace where token.isImplicit:
      msg = "unexpected end of scope"
    case .semicolon where token.isImplicit:
      msg = "unexpected end of line"
    default:
      msg = "unexpected token '\(token.tokenKind.text)'"
    }
    if let kind = expected {
      msg += " (expected '\(kind.text)')"
    }
    return .init(.error, msg)
  }
  static let unexpectedEOF =
    Diagnostic.Message(.error, "unexpected end-of-file reached")

  static func expected(_ name: String) -> Diagnostic.Message {
    return Diagnostic.Message(.error, "expected \(name)")
  }

  static func declRequiresIndices(
    _ typeName: TokenSyntax) -> Diagnostic.Message {
      return .init(.error,
                   """
                   declaration of '\(typeName.triviaFreeSourceText)' is \
                   missing type ascription
                   """)
  }

  /// FIXME: Fix-It Candidate
  static let addBasicTypeIndex =
    Diagnostic.Message(.note, "add a type ascription; e.g. ': Type'")

  static let expectedTopLevelModule =
    Diagnostic.Message(
      .error, "missing required top level module")

  static let expectedNameInFuncDecl =
    Diagnostic.Message(
      .error, "expression may not be used as identifier in function name")

  static func unexpectedQualifiedName(
    _ syntax: QualifiedNameSyntax) -> Diagnostic.Message {
    let txt = syntax.triviaFreeSourceText
    return Diagnostic.Message(
      .error,
      "qualified name '\(txt)' is not allowed in this position")
  }

  static let unexpectedConstructor =
    Diagnostic.Message(.error,
                       """
                       data constructors may only appear within the scope of a \
                       data declaration
                       """)

  static let emptyDataDeclWithWhere =
    Diagnostic.Message(.error,
                       """
                       data declaration with no constructors cannot have a \
                       'where' clause
                       """)

  static let indentToMakeConstructor =
    Diagnostic.Message(.note, """
                              indent this declaration to make it a constructor
                              """)

  static let removeWhereClause =
    Diagnostic.Message(.note, """
                              remove 'where' to make an empty data declaration
                              """)
}

public class Parser {
  public let engine: DiagnosticEngine
  let tokens: [TokenSyntax]
  public var index = 0
  var offset: Int = 0
  let converter: SourceLocationConverter

  public init(diagnosticEngine: DiagnosticEngine, tokens: [TokenSyntax],
              converter: SourceLocationConverter) {
    self.engine = diagnosticEngine
    self.tokens = tokens
    self.converter = converter
  }

  public var currentToken: TokenSyntax? {
    return index < tokens.count ? tokens[index] : nil
  }

  /// Looks backwards from where we are in the token stream for
  /// the first non-implicit token to which we can attach a diagnostic.
  func previousNonImplicitToken() -> TokenSyntax? {
    var i = 0
    while let tok = peekToken(ahead: i) {
      defer { i -= 1 }
      if tok.isImplicit { continue }
      return tok
    }
    return nil
  }

  func expected(_ name: String) -> Diagnostic.Message {
    let highlightedToken = previousNonImplicitToken()
    return engine.diagnose(.expected(name),
                           location: .location(self.currentLocation)) {
      if let tok = highlightedToken {
        $0.highlight(tok)
      }
    }
  }

  public func unexpectedToken(
    expected: TokenKind? = nil) -> Diagnostic.Message {
    // If we've "unexpected" an implicit token from Shining, highlight
    // instead the previous token because the diagnostic will say that we've
    // begun or ended the scope/line.
    let highlightedToken = previousNonImplicitToken()
    guard let token = currentToken else {
      return engine.diagnose(.unexpectedEOF,
                             location: .location(self.currentLocation))
    }
    let msg = Diagnostic.Message.unexpectedToken(token, expected: expected)
    return engine.diagnose(msg, location: .location(self.currentLocation)) {
      if let tok = highlightedToken {
        $0.highlight(tok)
      }
    }
  }

  public func consumeIf(_ kinds: TokenKind...) throws -> TokenSyntax? {
    guard let token = currentToken else {
      throw unexpectedToken(expected: kinds.first)
    }
    if kinds.contains(token.tokenKind) {
      advance()
      return token
    }
    return nil
  }

  public func consume(_ kinds: TokenKind...) throws -> TokenSyntax {
    guard let token = currentToken, kinds.contains(token.tokenKind) else {
      throw unexpectedToken(expected: kinds.first)
    }
    advance()
    return token
  }

  public func consumeUntil(_ kind: TokenKind) {
    while let token = currentToken, token.tokenKind != kind {
      advance()
    }
  }

  public func peek(ahead n: Int = 0) -> TokenKind {
    return peekToken(ahead: n)?.tokenKind ?? .eof
  }

  public func peekToken(ahead n: Int = 0) -> TokenSyntax? {
    guard index + n < tokens.count else { return nil }
    return tokens[index + n]
  }

  public func advance(_ n: Int = 1) {
    for i in 0..<n {
      guard let tok = peekToken(ahead: i), tok.isPresent else {
        break
      }
      offset += tok.byteSize
    }
    index += n
  }

  public var currentLocation: SourceLocation {
    return self.converter.location(for:
      AbsolutePosition(utf8Offset: self.offset))
  }

  public func peekLocation(ahead n: Int = 0) -> SourceLocation {
    var off = self.offset
    for i in 0..<n {
      guard let tok = peekToken(ahead: i), tok.isPresent else {
        break
      }
      off += tok.byteSize
    }
    return self.converter.location(for: AbsolutePosition(utf8Offset: off))
  }
}

extension Parser {
  public func parseTopLevelModule() -> ModuleDeclSyntax? {
    do {
      guard peek() == .moduleKeyword else {
        throw engine.diagnose(.expectedTopLevelModule,
                              location: .location(self.peekLocation(ahead: 1)))
      }
      let module = try parseModule()
      _ = try consume(.eof)
      return module
    } catch {
      return nil
    }
  }
}

extension Parser {
  public func parseIdentifierToken() throws -> TokenSyntax {
    guard case .identifier(_) = peek() else {
      throw unexpectedToken()
    }

    let name = currentToken!
    advance()
    return name
  }

  public func parseQualifiedName() throws -> QualifiedNameSyntax {
    var pieces = [QualifiedNamePieceSyntax]()
    while true {
      guard case .identifier(_) = peek() else { continue }
      let id = try parseIdentifierToken()
      if case .period = peek() {
        let period = try consume(.period)
        pieces.append(SyntaxFactory.makeQualifiedNamePiece(name: id,
                                               trailingPeriod: period))
      } else {
        pieces.append(SyntaxFactory.makeQualifiedNamePiece(name: id,
                                               trailingPeriod: nil))
        break
      }
    }

    // No pieces, no qualified name.
    guard !pieces.isEmpty else {
      throw expected("name")
    }

    return SyntaxFactory.makeQualifiedNameSyntax(pieces)
  }

  /// Ensures all of the QualifiedNameSyntax nodes passed in are basic names,
  /// not actually fully qualified names.
  func ensureAllNamesSimple(
    _ names: [QualifiedNameSyntax], _ locs: [SourceLocation]
  ) -> [TokenSyntax] {
    return zip(names, locs).map { (qn, loc) -> TokenSyntax in
      let name = qn.first!
      if name.trailingPeriod != nil || qn.count != 1 {
        // Diagnose the qualified name and recover by using just the
        // first piece.
        engine.diagnose(.unexpectedQualifiedName(qn),
                        location: .location(loc)) {
          $0.highlight(qn)
        }
      }
      return name.name
    }
  }

  func parseIdentifierList() throws -> IdentifierListSyntax {
    var names = [QualifiedNameSyntax]()
    var locs = [SourceLocation]()
    loop: while true {
      switch peek() {
      case .identifier(_), .underscore:
        // Parse qualified names, then verify they are all identifiers.
        locs.append(self.currentLocation)
        names.append(try parseQualifiedName())
      default: break loop
      }
    }
    return SyntaxFactory.makeIdentifierListSyntax(ensureAllNamesSimple(names,
                                                                       locs))
  }
}

extension Parser {
  func parseDeclList() throws -> DeclListSyntax {
    var pieces = [DeclSyntax]()
    while peek() != .rightBrace {
      guard peek() != .eof else {
        throw engine.diagnose(.unexpectedEOF)
      }


      // Recover from invalid declarations by ignoring them and parsing to the
      // next semicolon.
      let declLoc = self.peekLocation(ahead: 1)
      guard let decl = try? parseDecl() else {
        consumeUntil(.semicolon)
        _ = try consume(.semicolon)
        continue
      }

      // If this is a function declaration directly after an empty data
      // declaration with a `where` clause (which should have caused an error),
      // diagnose this as a possible constructor.
      if decl is FunctionDeclSyntax,
         let lastData = pieces.last as? DataDeclSyntax,
         lastData.constructorList.isEmpty {
        engine.diagnose(.unexpectedConstructor, location: .location(declLoc)) {
          $0.highlight(decl)
          $0.note(.indentToMakeConstructor, location: .location(declLoc))
        }
      }
      pieces.append(decl)
    }
    return SyntaxFactory.makeDeclListSyntax(pieces)
  }

  func parseDecl() throws -> DeclSyntax {
    switch peek() {
    case .moduleKeyword:
      return try self.parseModule()
    case .dataKeyword:
      let declLoc = self.peekLocation(ahead: 1)
      let decl = try self.parseDataDecl()

      // If there's a regular data decl and an empty constructor list,
      // throw an error.
      if let dataDecl = decl as? DataDeclSyntax,
        dataDecl.constructorList.isEmpty {
        engine.diagnose(.emptyDataDeclWithWhere, location: .location(declLoc)) {
          $0.highlight(decl)
          $0.note(.removeWhereClause, location: .location(declLoc),
                  highlights: [dataDecl.whereToken])
        }
      }
      return decl
    case .recordKeyword:
      return try self.parseRecordDecl()
    case .openKeyword:
      return try self.parseOpenImportDecl()
    case .importKeyword:
      return try self.parseImportDecl()
    case .infixKeyword, .infixlKeyword, .infixrKeyword:
      return try self.parseInfixDecl()
    case _ where isStartOfBasicExpr():
      return try self.parseFunctionDeclOrClause()
    default:
      advance()
      throw expected("declaration")
    }
  }

  func parseModule() throws -> ModuleDeclSyntax {
    let moduleKw = try consume(.moduleKeyword)
    let moduleId = try parseQualifiedName()
    let paramList = try parseTypedParameterList()
    let whereKw = try consume(.whereKeyword)
    let leftBrace = try consume(.leftBrace)
    let declList = try parseDeclList()
    let rightBrace = try consume(.rightBrace)
    let semi = try consume(.semicolon)
    return SyntaxFactory.makeModuleDecl(
      moduleToken: moduleKw,
      moduleIdentifier: moduleId,
      typedParameterList: paramList,
      whereToken: whereKw,
      leftBraceToken: leftBrace,
      declList: declList,
      rightBraceToken: rightBrace,
      trailingSemicolon: semi
    )
  }

  func parseOpenImportDecl() throws -> OpenImportDeclSyntax {
    return SyntaxFactory.makeOpenImportDecl(
      openToken: try consume(.openKeyword),
      importToken: try consume(.importKeyword),
      importIdentifier: try parseQualifiedName(),
      trailingSemicolon: try consume(.semicolon)
    )
  }

  func parseImportDecl() throws -> ImportDeclSyntax {
    return SyntaxFactory.makeImportDecl(
      importToken: try consume(.importKeyword),
      importIdentifier: try parseQualifiedName(),
      trailingSemicolon: try consume(.semicolon)
    )
  }
}

extension Parser {
  func parseInfixDecl() throws -> FixityDeclSyntax {
    switch peek() {
    case .infixKeyword:
      return try self.parseNonFixDecl()
    case .infixlKeyword:
      return try self.parseLeftFixDecl()
    case .infixrKeyword:
      return try self.parseRightFixDecl()
    default:
      throw unexpectedToken()
    }
  }

  func parseNonFixDecl() throws -> NonFixDeclSyntax {
    let tok = try consume(.infixKeyword)
    let prec = try parseIdentifierToken()
    let ids = try parseIdentifierList()
    let semi = try consume(.semicolon)
    return SyntaxFactory.makeNonFixDecl(
      infixToken: tok,
      precedence: prec,
      names: ids,
      trailingSemicolon: semi
    )
  }

  func parseLeftFixDecl() throws -> LeftFixDeclSyntax {
    let tok = try consume(.infixlKeyword)
    let prec = try parseIdentifierToken()
    let ids = try parseIdentifierList()
    let semi = try consume(.semicolon)
    return SyntaxFactory.makeLeftFixDecl(
      infixlToken: tok,
      precedence: prec,
      names: ids,
      trailingSemicolon: semi
    )
  }

  func parseRightFixDecl() throws -> RightFixDeclSyntax {
    let tok = try consume(.infixrKeyword)
    let prec = try parseIdentifierToken()
    let ids = try parseIdentifierList()
    let semi = try consume(.semicolon)
    return SyntaxFactory.makeRightFixDecl(
      infixrToken: tok,
      precedence: prec,
      names: ids,
      trailingSemicolon: semi
    )
  }
}

extension Parser {
  func parseRecordDecl() throws -> RecordDeclSyntax {
    let recordTok = try consume(.recordKeyword)
    let recName = try parseIdentifierToken()
    let paramList = try parseTypedParameterList()
    let indices = try parseTypeIndices(recName, self.currentLocation)
    let whereTok = try consume(.whereKeyword)
    let leftTok = try consume(.leftBrace)
    let elemList = try parseRecordElementList()
    let rightTok = try consume(.rightBrace)
    let trailingSemi = try consume(.semicolon)
    return SyntaxFactory.makeRecordDecl(
      recordToken: recordTok,
      recordName: recName,
      parameterList: paramList,
      typeIndices: indices,
      whereToken: whereTok,
      leftParenToken: leftTok,
      recordElementList: elemList,
      rightParenToken: rightTok,
      trailingSemicolon: trailingSemi
    )
  }

  func parseRecordElementList() throws -> DeclListSyntax {
    var pieces = [DeclSyntax]()
    loop: while true {
      switch peek() {
      case .identifier(_):
        pieces.append(try parseFunctionDeclOrClause())
      case .fieldKeyword:
        pieces.append(try parseFieldDecl())
      case .constructorKeyword:
        pieces.append(try parseRecordConstructorDecl())
      default:
        break loop
      }
    }
    return SyntaxFactory.makeDeclListSyntax(pieces)
  }

  func parseRecordElement() throws -> DeclSyntax {
    switch peek() {
    case .fieldKeyword:
      return try self.parseFieldDecl()
    case .identifier(_):
      return try self.parseFunctionDeclOrClause()
    case .constructorKeyword:
      return try parseRecordConstructorDecl()
    default:
      throw expected("field or function declaration")
    }
  }

  func parseFieldDecl() throws -> FieldDeclSyntax {
    let fieldTok = try consume(.fieldKeyword)
    let ascription = try parseAscription()
    let trailingSemi = try consume(.semicolon)
    return SyntaxFactory.makeFieldDecl(
      fieldToken: fieldTok,
      ascription: ascription,
      trailingSemicolon: trailingSemi
    )
  }

  func parseRecordConstructorDecl() throws -> RecordConstructorDeclSyntax {
    let constrTok = try consume(.constructorKeyword)
    let constrName = try parseIdentifierToken()
    let trailingSemi = try consume(.semicolon)
    return SyntaxFactory.makeRecordConstructorDecl(
      constructorToken: constrTok,
      constructorName: constrName,
      trailingSemicolon: trailingSemi
    )
  }
}

extension Parser {
  func isStartOfTypedParameter() -> Bool {
    guard self.index + 1 < self.tokens.endIndex else { return false }
    switch (peek(), peek(ahead: 1)) {
    case (.leftBrace, .identifier(_)): return true
    case (.leftParen, .identifier(_)): return true
    default: return false
    }
  }

  func parseTypedParameterList() throws -> TypedParameterListSyntax {
    var pieces = [TypedParameterSyntax]()
    while isStartOfTypedParameter() {
      pieces.append(try parseTypedParameter())
    }
    return SyntaxFactory.makeTypedParameterListSyntax(pieces)
  }

  func parseTypedParameter() throws -> TypedParameterSyntax {
    switch peek() {
    case .leftParen:
      return try self.parseExplicitTypedParameter()
    case .leftBrace:
      return try self.parseImplicitTypedParameter()
    default:
      throw expected("typed parameter")
    }
  }

  func parseExplicitTypedParameter() throws -> ExplicitTypedParameterSyntax {
    let leftParen = try consume(.leftParen)
    let ascription = try parseAscription()
    let rightParen = try consume(.rightParen)
    return SyntaxFactory.makeExplicitTypedParameter(
      leftParenToken: leftParen,
      ascription: ascription,
      rightParenToken: rightParen)
  }

  func parseImplicitTypedParameter() throws -> ImplicitTypedParameterSyntax {
    let leftBrace = try consume(.leftBrace)
    let ascription = try parseAscription()
    let rightBrace = try consume(.rightBrace)
    return SyntaxFactory.makeImplicitTypedParameter(
      leftBraceToken: leftBrace,
      ascription: ascription,
      rightBraceToken: rightBrace)
  }

  func parseTypeIndices(
    _ parentName: TokenSyntax, _ loc: SourceLocation
  ) throws -> TypeIndicesSyntax {
    // If we see a semicolon or 'where' after the identifier, the
    // user likely forgot to provide indices for this data type.
    // Recover by inserting `: Type`.
    guard [.semicolon, .whereKeyword].contains(peek()) else {
      let colon = try consume(.colon)
      let expr = try parseExpr()
      return SyntaxFactory.makeTypeIndices(colonToken: colon, indexExpr: expr)
    }

    let indices = SyntaxFactory.makeTypeIndices(
      colonToken: SyntaxFactory.makeColon(),
      indexExpr: implicitNamedExpr(.typeKeyword))
    engine.diagnose(.declRequiresIndices(parentName),
                    location: .location(loc)) {
      $0.highlight(parentName)
      $0.note(.addBasicTypeIndex, location: .location(loc))
    }
    return indices
  }

  func parseAscription() throws -> AscriptionSyntax {
    let boundNames = try parseIdentifierList()
    let colonToken = try consume(.colon)
    let expr = try parseExpr()
    return SyntaxFactory.makeAscription(
      boundNames: boundNames,
      colonToken: colonToken,
      typeExpr: expr)
  }
}

extension Parser {
  func implicitNamedExpr(_ name: TokenKind) -> NamedBasicExprSyntax {
    let tok = SyntaxFactory.makeToken(name, presence: .implicit)
    let piece = SyntaxFactory.makeQualifiedNamePiece(name: tok,
                                                     trailingPeriod: nil)
    return SyntaxFactory.makeNamedBasicExpr(
      name: SyntaxFactory.makeQualifiedNameSyntax([piece]))
  }

  func parseDataDecl() throws -> DeclSyntax {
    let dataTok = try consume(.dataKeyword)
    let dataId = try parseIdentifierToken()
    let paramList = try parseTypedParameterList()
    let indices = try parseTypeIndices(dataId, self.currentLocation)
    if let whereTok = try consumeIf(.whereKeyword) {
      let leftBrace = try consume(.leftBrace)
      let constrList = try parseConstructorList()
      let rightBrace = try consume(.rightBrace)
      let semi = try consume(.semicolon)
      return SyntaxFactory.makeDataDecl(
        dataToken: dataTok,
        dataIdentifier: dataId,
        typedParameterList: paramList,
        typeIndices: indices,
        whereToken: whereTok,
        leftBraceToken: leftBrace,
        constructorList: constrList,
        rightBraceToken: rightBrace,
        trailingSemicolon: semi)
    } else {
      let semi = try consume(.semicolon)
      return SyntaxFactory.makeEmptyDataDecl(
        dataToken: dataTok,
        dataIdentifier: dataId,
        typedParameterList: paramList,
        typeIndices: indices,
        trailingSemicolon: semi)
    }
  }

  func parseConstructorList() throws -> ConstructorListSyntax {
    var pieces = [ConstructorDeclSyntax]()
    while peek() != .rightBrace {
      pieces.append(try parseConstructor())
    }
    return SyntaxFactory.makeConstructorListSyntax(pieces)
  }

  func parseConstructor() throws -> ConstructorDeclSyntax {
    let ascription = try parseAscription()
    let semi = try consume(.semicolon)
    return SyntaxFactory.makeConstructorDecl(
      ascription: ascription,
      trailingSemicolon: semi)
  }
}

extension Parser {
  func parseFunctionDeclOrClause() throws -> DeclSyntax {

    let (exprs, exprLocs) = try parseBasicExprList()
    switch peek() {
    case .colon:
      return try self.finishParsingFunctionDecl(exprs, exprLocs)
    case .equals, .withKeyword:
      return try self.finishParsingFunctionClause(exprs)
    default:
      return try self.finishParsingAbsurdFunctionClause(exprs)
    }
  }

  func finishParsingFunctionDecl(
    _ exprs: BasicExprListSyntax, _ locs: [SourceLocation]
  ) throws -> FunctionDeclSyntax {
    let colonTok = try self.consume(.colon)
    let boundNames = SyntaxFactory
      .makeIdentifierListSyntax(try zip(exprs, locs).map { (expr, loc) in
      guard let namedExpr = expr as? NamedBasicExprSyntax else {
        throw engine.diagnose(.expectedNameInFuncDecl, location: .location(loc))
      }

      guard let name = namedExpr.name.first, namedExpr.name.count == 1 else {
        throw engine.diagnose(.unexpectedQualifiedName(namedExpr.name),
                              location: .location(loc))
      }
      return name.name
    })
    let typeExpr = try self.parseExpr()
    let ascription = SyntaxFactory.makeAscription(
      boundNames: boundNames,
      colonToken: colonTok,
      typeExpr: typeExpr
    )
    return SyntaxFactory.makeFunctionDecl(
      ascription: ascription,
      trailingSemicolon: try consume(.semicolon))
  }

  func finishParsingFunctionClause(
        _ exprs: BasicExprListSyntax) throws -> FunctionClauseDeclSyntax {
    if case .withKeyword = peek() {
      return SyntaxFactory.makeWithRuleFunctionClauseDecl(
        basicExprList: exprs,
        withToken: try consume(.withKeyword),
        withExpr: try parseExpr(),
        withPatternClause: try parseBasicExprList().0,
        equalsToken: try consume(.equals),
        rhsExpr: try parseExpr(),
        whereClause: try maybeParseWhereClause(),
        trailingSemicolon: try consume(.semicolon))
    }
    assert(peek() == .equals)
    return SyntaxFactory.makeNormalFunctionClauseDecl(
      basicExprList: exprs,
      equalsToken: try consume(.equals),
      rhsExpr: try parseExpr(),
      whereClause: try maybeParseWhereClause(),
      trailingSemicolon: try consume(.semicolon))
  }

  func finishParsingAbsurdFunctionClause(
    _ exprs: BasicExprListSyntax) throws -> AbsurdFunctionClauseDeclSyntax {
    return SyntaxFactory.makeAbsurdFunctionClauseDecl(
      basicExprList: exprs,
      trailingSemicolon: try consume(.semicolon)
    )
  }

  func maybeParseWhereClause() throws -> FunctionWhereClauseDeclSyntax? {
    guard case .whereKeyword = peek() else {
      return nil
    }

    return SyntaxFactory.makeFunctionWhereClauseDecl(
      whereToken: try consume(.whereKeyword),
      leftBraceToken: try consume(.leftBrace),
      declList: try parseDeclList(),
      rightBraceToken: try consume(.rightBrace)
    )
  }
}

extension Parser {
  func isStartOfExpr() -> Bool {
    if isStartOfBasicExpr() { return true }
    switch peek() {
    case .backSlash, .forallSymbol, .forallKeyword, .letKeyword:
      return true
    default:
      return false
    }
  }

  func isStartOfBasicExpr(parseGIR: Bool = false) -> Bool {
    if parseGIR && peekToken()!.leadingTrivia.containsNewline {
      return false
    }
    switch peek() {
    case .underscore, .typeKeyword,
         .leftParen,
         .recordKeyword, .identifier(_):
      return true
    case .leftBrace where !parseGIR:
      return true
    default:
      return false
    }
  }

  // Breaks the ambiguity in parsing the beginning of a typed parameter
  //
  // (a b c ... : <expr>)
  //
  // and the beginning of an application expression
  //
  // (a b c ...)
  func parseParenthesizedExpr() throws -> BasicExprSyntax {
    let leftParen = try consume(.leftParen)
    if case .rightParen = peek() {
      let rightParen = try consume(.rightParen)
      return SyntaxFactory.makeAbsurdExpr(leftParenToken: leftParen,
                              rightParenToken: rightParen)
    }

    // If we've hit a non-identifier token, start parsing a parenthesized
    // expression.
    guard case .identifier(_) = peek() else {
      let expr = try parseExpr()
      let rightParen = try consume(.rightParen)
      return SyntaxFactory.makeParenthesizedExpr(
        leftParenToken: leftParen,
        expr: expr,
        rightParenToken: rightParen
      )
    }

    // Gather all the subexpressions.
    var exprs = [BasicExprSyntax]()
    var exprLocs = [SourceLocation]()
    while isStartOfBasicExpr() {
      exprLocs.append(self.currentLocation)
      exprs.append(try parseBasicExpr())
    }

    // If we've not hit the matching closing paren, we must be parsing a typed
    // parameter group
    //
    // (a b c ... : <expr>) {d e f ... : <expr>} ...
    if case .colon = peek() {
      return try self.finishParsingTypedParameterGroupExpr(leftParen,
                                                           exprs, exprLocs)
    }

    // Else consume the closing paren.
    let rightParen = try consume(.rightParen)

    // If there's only one named expression like '(a)', return it.
    guard exprs.count >= 1 else {
      return SyntaxFactory.makeParenthesizedExpr(
        leftParenToken: leftParen,
        expr: exprs[0],
        rightParenToken: rightParen
      )
    }

    // Else form an application expression.
    let appExprs = SyntaxFactory.makeBasicExprListSyntax(exprs)
    let app = SyntaxFactory.makeApplicationExpr(exprs: appExprs)
    return SyntaxFactory.makeParenthesizedExpr(
      leftParenToken: leftParen,
      expr: app,
      rightParenToken: rightParen
    )
  }

  func parseExpr() throws -> ExprSyntax {
    switch peek() {
    case .backSlash:
      return try self.parseLambdaExpr()
    case .forallSymbol, .forallKeyword:
      return try self.parseQuantifiedExpr()
    case .letKeyword:
      return try self.parseLetExpr()
    default:
      // If we're looking at another basic expr, then we're trying to parse
      // either an application or an -> expression. Either way, parse the
      // remaining list of expressions and construct a BasicExprList with the
      // first expression at the beginning.
      var exprs = [BasicExprSyntax]()
      while isStartOfBasicExpr() || peek() == .arrow {
        // If we see an arrow at the start, then consume it and move on.
        if case .arrow = peek() {
          let arrow = try consume(.arrow)
          let name = SyntaxFactory.makeQualifiedNameSyntax([
            SyntaxFactory.makeQualifiedNamePiece(name: arrow,
                                                 trailingPeriod: nil)
          ])
          exprs.append(SyntaxFactory.makeNamedBasicExpr(name: name))
        } else {
          exprs.append(contentsOf: try parseBasicExprs().0)
        }
      }

      if exprs.isEmpty {
        throw expected("expression")
      }

      // If there's only one expression in this "application", then just return
      // it without constructing an application.
      guard exprs.count > 1 else {
        return exprs[0]
      }
      return SyntaxFactory.makeApplicationExpr(
        exprs: SyntaxFactory.makeBasicExprListSyntax(exprs))
    }
  }

  func parseTypedParameterGroupExpr() throws -> TypedParameterGroupExprSyntax {
    let parameters = try parseTypedParameterList()
    guard !parameters.isEmpty else {
      throw expected("type ascription")
    }
    return SyntaxFactory.makeTypedParameterGroupExpr(
      parameters: parameters
    )
  }

  func finishParsingTypedParameterGroupExpr(
    _ leftParen: TokenSyntax, _ exprs: [ExprSyntax], _ locs: [SourceLocation]
  ) throws -> TypedParameterGroupExprSyntax {
    let colonTok = try consume(.colon)

    // Ensure all expressions are simple names
    let names = try zip(exprs, locs).map { (expr, loc) -> QualifiedNameSyntax in
      guard let namedExpr = expr as? NamedBasicExprSyntax else {
        throw engine.diagnose(.expected("identifier"),
                              location: .location(loc)) {
          $0.highlight(expr)
        }
      }
      return namedExpr.name
    }

    let tokens = ensureAllNamesSimple(names, locs)
    let identList = SyntaxFactory.makeIdentifierListSyntax(tokens)
    let typeExpr = try self.parseExpr()
    let ascription = SyntaxFactory.makeAscription(boundNames: identList,
                                      colonToken: colonTok,
                                      typeExpr: typeExpr)
    let rightParen = try consume(.rightParen)
    let firstParam = SyntaxFactory.makeExplicitTypedParameter(
      leftParenToken: leftParen,
      ascription: ascription,
      rightParenToken: rightParen)
    let parameters = try parseTypedParameterList().prepending(firstParam)
    guard !parameters.isEmpty else {
      throw expected("type ascription")
    }
    return SyntaxFactory.makeTypedParameterGroupExpr(parameters: parameters)
  }

  func parseLambdaExpr() throws -> LambdaExprSyntax {
    let slashTok = try consume(.backSlash)
    let bindingList = try parseBindingList()
    let arrowTok = try consume(.arrow)
    let bodyExpr = try parseExpr()
    return SyntaxFactory.makeLambdaExpr(
      slashToken: slashTok,
      bindingList: bindingList,
      arrowToken: arrowTok,
      bodyExpr: bodyExpr
    )
  }

  func parseQuantifiedExpr() throws -> QuantifiedExprSyntax {
    let forallTok = try consume(.forallSymbol, .forallKeyword)
    let bindingList = try parseTypedParameterList()
    let arrow = try consume(.arrow)
    let outputExpr = try parseExpr()
    return SyntaxFactory.makeQuantifiedExpr(
      forallToken: forallTok,
      bindingList: bindingList,
      arrowToken: arrow,
      outputExpr: outputExpr
    )
  }

  func parseLetExpr() throws -> LetExprSyntax {
    let letTok = try consume(.letKeyword)
    let leftBrace = try consume(.leftBrace)
    let declList = try parseDeclList()
    let rightBrace = try consume(.rightBrace)
    let inTok = try consume(.inKeyword)
    let outputExpr = try parseExpr()
    return SyntaxFactory.makeLetExpr(
      letToken: letTok,
      leftBraceToken: leftBrace,
      declList: declList,
      rightBraceToken: rightBrace,
      inToken: inTok,
      outputExpr: outputExpr)
  }

  func parseBasicExprs(
    diagType: String = "expression",
    parseGIR: Bool = false) throws -> ([BasicExprSyntax], [SourceLocation]) {
    var pieces = [BasicExprSyntax]()
    var locs = [SourceLocation]()
    while isStartOfBasicExpr(parseGIR: parseGIR) {
      if parseGIR && peekToken()!.leadingTrivia.containsNewline {
        return (pieces, locs)
      }
      locs.append(self.currentLocation)
      pieces.append(try parseBasicExpr(parseGIR: parseGIR))
    }

    guard !pieces.isEmpty else {
      throw expected(diagType)
    }
    return (pieces, locs)
  }

  func parseBasicExprList() throws -> (BasicExprListSyntax, [SourceLocation]) {
    let (exprs, locs) = try parseBasicExprs(diagType: "list of expressions")
    return (SyntaxFactory.makeBasicExprListSyntax(exprs), locs)
  }

  public func parseBasicExpr(parseGIR: Bool = false) throws -> BasicExprSyntax {
    switch peek() {
    case .underscore:
      return try self.parseUnderscoreExpr()
    case .typeKeyword:
      return try self.parseTypeBasicExpr()
    case .leftParen:
      return try self.parseParenthesizedExpr()
    case .leftBrace where !parseGIR:
      return try self.parseTypedParameterGroupExpr()
    case .recordKeyword:
      return try self.parseRecordExpr()
    case .identifier(_):
      return try self.parseNamedBasicExpr()
    default:
      throw expected("expression")
    }
  }

  func parseRecordExpr() throws -> RecordExprSyntax {
    let recordTok = try consume(.recordKeyword)
    let parameterExpr = isStartOfBasicExpr() ? try parseBasicExpr() : nil
    let leftBrace = try consume(.leftBrace)
    let fieldAssigns = try parseRecordFieldAssignmentList()
    let rightBrace = try consume(.rightBrace)
    return SyntaxFactory.makeRecordExpr(
      recordToken: recordTok,
      parameterExpr: parameterExpr,
      leftBraceToken: leftBrace,
      fieldAssignments: fieldAssigns,
      rightBraceToken: rightBrace
    )
  }

  func parseRecordFieldAssignmentList() throws
    -> RecordFieldAssignmentListSyntax {
      var pieces = [RecordFieldAssignmentSyntax]()
      while case .identifier(_) = peek() {
        pieces.append(try parseRecordFieldAssignment())
      }
      return SyntaxFactory.makeRecordFieldAssignmentListSyntax(pieces)
  }

  func parseRecordFieldAssignment() throws -> RecordFieldAssignmentSyntax {
    let fieldName = try parseIdentifierToken()
    let equalsTok = try consume(.equals)
    let fieldInit = try parseExpr()
    let trailingSemi = try consume(.semicolon)
    return SyntaxFactory.makeRecordFieldAssignment(
      fieldName: fieldName,
      equalsToken: equalsTok,
      fieldInitExpr: fieldInit,
      trailingSemicolon: trailingSemi
    )
  }

  func parseNamedBasicExpr() throws -> NamedBasicExprSyntax {
    let name = try parseQualifiedName()
    return SyntaxFactory.makeNamedBasicExpr(name: name)
  }

  func parseUnderscoreExpr() throws -> UnderscoreExprSyntax {
    let underscore = try consume(.underscore)
    return SyntaxFactory.makeUnderscoreExpr(underscoreToken: underscore)
  }

  func parseTypeBasicExpr() throws -> TypeBasicExprSyntax {
    let typeTok = try consume(.typeKeyword)
    return SyntaxFactory.makeTypeBasicExpr(typeToken: typeTok)
  }

  func parseBindingList() throws -> BindingListSyntax {
    var pieces = [BindingSyntax]()
    while true {
      if isStartOfTypedParameter() {
        pieces.append(try parseTypedBinding())
      } else if case .underscore = peek() {
        pieces.append(try parseAnonymousBinding())
      } else if case .identifier(_) = peek(), peek() != .arrow {
        pieces.append(try parseNamedBinding())
      } else {
        break
      }
    }

    guard !pieces.isEmpty else {
      throw expected("binding list")
    }

    return SyntaxFactory.makeBindingListSyntax(pieces)
  }

  func parseNamedBinding() throws -> NamedBindingSyntax {
    let name = try parseQualifiedName()
    return SyntaxFactory.makeNamedBinding(name: name)
  }

  func parseTypedBinding() throws -> TypedBindingSyntax {
    let parameter = try parseTypedParameter()
    return SyntaxFactory.makeTypedBinding(parameter: parameter)
  }

  func parseAnonymousBinding() throws -> AnonymousBindingSyntax {
    let underscore = try consume(.underscore)
    return SyntaxFactory.makeAnonymousBinding(underscoreToken: underscore)
  }
}

extension Parser {
  func isStartOfGIRTypedParameter() -> Bool {
    guard self.index + 1 < self.tokens.endIndex else { return false }
    switch (peek(), peek(ahead: 1)) {
    case (.leftParen, .identifier(_)): return true
    default: return false
    }
  }

  func parseGIRTypedParameterList() throws -> TypedParameterListSyntax {
    var pieces = [TypedParameterSyntax]()
    while isStartOfGIRTypedParameter() {
      pieces.append(try parseGIRTypedParameter())
    }
    return SyntaxFactory.makeTypedParameterListSyntax(pieces)
  }

  func parseGIRTypedParameter() throws -> TypedParameterSyntax {
    switch peek() {
    case .leftParen:
      return try self.parseExplicitTypedParameter()
    default:
      throw expected("typed parameter")
    }
  }

  func parseGIRQuantifiedExpr() throws -> QuantifiedExprSyntax {
    let forallTok = try consume(.forallSymbol, .forallKeyword)
    let bindingList = try parseGIRTypedParameterList()
    let arrow = try consume(.arrow)
    let outputExpr = try parseExpr()
    return SyntaxFactory.makeQuantifiedExpr(
      forallToken: forallTok,
      bindingList: bindingList,
      arrowToken: arrow,
      outputExpr: outputExpr
    )
  }

  public func parseGIRTypeExpr() throws -> ExprSyntax {
    switch peek() {
    case .backSlash:
      return try self.parseLambdaExpr()
    case .forallSymbol, .forallKeyword:
      return try self.parseGIRQuantifiedExpr()
    default:
      // If we're looking at another basic expr, then we're trying to parse
      // either an application or an -> expression. Either way, parse the
      // remaining list of expressions and construct a BasicExprList with the
      // first expression at the beginning.
      var exprs = [BasicExprSyntax]()
      while isStartOfBasicExpr(parseGIR: true) || peek() == .arrow {
        // If we see an arrow at the start, then consume it and move on.
        if case .arrow = peek() {
          let arrow = try consume(.arrow)
          let name = SyntaxFactory.makeQualifiedNameSyntax([
            SyntaxFactory.makeQualifiedNamePiece(name: arrow,
                                                 trailingPeriod: nil),
          ])
          exprs.append(SyntaxFactory.makeNamedBasicExpr(name: name))
        } else {
          exprs.append(contentsOf: try parseBasicExprs(parseGIR: true).0)
        }
      }

      if exprs.isEmpty {
        throw expected("expression")
      }

      // If there's only one expression in this "application", then just return
      // it without constructing an application.
      guard exprs.count > 1 else {
        return exprs[0]
      }

      return SyntaxFactory.makeApplicationExpr(
        exprs: SyntaxFactory.makeBasicExprListSyntax(exprs))
    }
  }
}
