import Foundation

public struct ParseError: Error, CustomStringConvertible, Sendable {
    public let message: String
    public let location: SourceLocation
    
    public init(_ message: String, location: SourceLocation) {
        self.message = message
        self.location = location
    }
    
    public var description: String {
        return "Line \(location.line), Column \(location.column): \(message)"
    }
}

public final class Parser {
    private let tokens: [Token]
    private var current: Int = 0
    public var errors: [ParseError] = []
    
    public init(tokens: [Token]) {
        self.tokens = tokens
    }
    
    public convenience init(source: String) {
        let lexer = Lexer(source)
        let tokens = lexer.tokenize()
        self.init(tokens: tokens)
    }
    
    private var isAtEnd: Bool {
        return peek().type == .eof
    }
    
    private func peek() -> Token {
        return current < tokens.count ? tokens[current] : Token(type: .eof, location: SourceLocation(line: 0, column: 0), raw: "")
    }
    
    private func previous() -> Token {
        return tokens[max(0, current - 1)]
    }
    
    @discardableResult
    private func advance() -> Token {
        if !isAtEnd {
            current += 1
        }
        return previous()
    }
    
    private func check(_ type: TokenType) -> Bool {
        if isAtEnd { return false }
        return peek().type == type
    }
    
    private func match(_ types: TokenType...) -> Bool {
        for type in types {
            if check(type) {
                advance()
                return true
            }
        }
        return false
    }
    
    @discardableResult
    private func consume(_ type: TokenType, _ message: String) throws -> Token {
        if check(type) {
            return advance()
        }
        throw ParseError(message, location: peek().location)
    }
    
    public func parse() -> Program {
        var statements: [Statement] = []
        while !isAtEnd {
            do {
                if let stmt = try parseStatement() {
                    statements.append(stmt)
                }
            } catch let err as ParseError {
                errors.append(err)
                synchronize()
            } catch {
                errors.append(ParseError(error.localizedDescription, location: peek().location))
                synchronize()
            }
        }
        return Program(statements: statements)
    }
    
    private func synchronize() {
        advance()
        while !isAtEnd {
            if previous().type == .semicolon { return }
            switch peek().type {
            case .module, .function, .if, .for, .let, .include, .use, .echo, .assert:
                return
            default:
                advance()
            }
        }
    }
    
    // MARK: - Statements
    
    private func parseStatement() throws -> Statement? {
        let loc = peek().location
        
        // Check for directives
        if match(.include) {
            let path = try parseIncludePath()
            _ = match(.semicolon)
            return .includeDirective(path: path, location: loc)
        }
        
        if match(.use) {
            let path = try parseIncludePath()
            _ = match(.semicolon)
            return .useDirective(path: path, location: loc)
        }
        
        // Module definition: module name(params) { ... }
        if match(.module) {
            let nameTok = try consumeIdentifier("Expected module name after 'module'")
            let params = try parseParameterList()
            let body = try parseBlockOrSingleStatement()
            return .moduleDef(name: nameTok, params: params, body: body, location: loc)
        }
        
        // Function definition: function name(params) = expr;
        if match(.function) {
            let nameTok = try consumeIdentifier("Expected function name after 'function'")
            let params = try parseParameterList()
            try consume(.equals, "Expected '=' in function definition")
            let expr = try parseExpression()
            try consume(.semicolon, "Expected ';' after function definition")
            return .functionDef(name: nameTok, params: params, body: expr, location: loc)
        }
        
        // If statement: if (condition) stmt [else stmt]
        if match(.if) {
            try consume(.leftParen, "Expected '(' after 'if'")
            let condition = try parseExpression()
            try consume(.rightParen, "Expected ')' after if condition")
            let thenBranch = try parseBlockOrSingleStatement()
            var elseBranch: [Statement]? = nil
            if match(.else) {
                elseBranch = try parseBlockOrSingleStatement()
            }
            return .ifStatement(condition: condition, thenBranch: thenBranch, elseBranch: elseBranch, location: loc)
        }
        
        // For loop: for (i = range, ...) stmt
        if match(.for) {
            let bindings = try parseForBindings()
            let body = try parseBlockOrSingleStatement()
            return .forLoop(variables: bindings, body: body, location: loc)
        }
        
        // Intersection for: intersection_for (i = range) stmt
        if match(.intersection_for) {
            let bindings = try parseForBindings()
            let body = try parseBlockOrSingleStatement()
            return .intersectionFor(variables: bindings, body: body, location: loc)
        }
        
        // Echo statement
        if match(.echo) {
            let args = try parseArgumentList()
            try consume(.semicolon, "Expected ';' after echo")
            return .echoStatement(args: args, location: loc)
        }
        
        // Assert statement
        if match(.assert) {
            try consume(.leftParen, "Expected '(' after 'assert'")
            let cond = try parseExpression()
            var msg: Expression? = nil
            if match(.comma) {
                msg = try parseExpression()
            }
            try consume(.rightParen, "Expected ')' after assert condition")
            try consume(.semicolon, "Expected ';' after assert")
            return .assertStatement(condition: cond, message: msg, location: loc)
        }
        
        // Assignment: ident = expr; or $ident = expr;
        if case .identifier(let name) = peek().type, peekNextTokenIsEquals() {
            advance() // identifier
            try consume(.equals, "Expected '=' in assignment")
            let expr = try parseExpression()
            try consume(.semicolon, "Expected ';' after assignment")
            return .assignment(name: name, value: expr, location: loc)
        }
        
        if case .specialVar(let name) = peek().type, peekNextTokenIsEquals() {
            advance() // specialVar
            try consume(.equals, "Expected '=' in assignment")
            let expr = try parseExpression()
            try consume(.semicolon, "Expected ';' after assignment")
            return .assignment(name: name, value: expr, location: loc)
        }
        
        // Module call (with optional modifier *, !, #, %)
        var modifier: GeometryModifier? = nil
        if match(.modifierHash) {
            modifier = .highlight
        } else if match(.percent) {
            modifier = .background
        } else if match(.star) {
            modifier = .disable
        } else if match(.bang) {
            modifier = .showOnly
        }
        
        // Now expect identifier or special module name
        let moduleName: String
        if case .identifier(let id) = peek().type {
            advance()
            moduleName = id
        } else if case .specialVar(let s) = peek().type {
            advance()
            moduleName = s
        } else {
            // Unexpected token
            let tok = advance()
            throw ParseError("Unexpected token '\(tok.raw)'", location: tok.location)
        }
        
        let args: [CallArg]
        if check(.leftParen) {
            args = try parseArgumentList()
        } else {
            args = []
        }
        
        // Module call children:
        // Case 1: ends with semicolon ';' -> no children
        if match(.semicolon) {
            return .moduleCall(name: moduleName, args: args, children: [], modifier: modifier, location: loc)
        }
        
        // Case 2: followed by block or child statement
        let children = try parseBlockOrSingleStatement()
        return .moduleCall(name: moduleName, args: args, children: children, modifier: modifier, location: loc)
    }
    
    private func peekNextTokenIsEquals() -> Bool {
        guard current + 1 < tokens.count else { return false }
        return tokens[current + 1].type == .equals
    }
    
    private func parseIncludePath() throws -> String {
        if case .pathString(let p) = peek().type {
            advance()
            return p
        } else if case .string(let s) = peek().type {
            advance()
            return s
        }
        throw ParseError("Expected file path after include or use", location: peek().location)
    }
    
    private func consumeIdentifier(_ message: String) throws -> String {
        if case .identifier(let id) = peek().type {
            advance()
            return id
        }
        throw ParseError(message, location: peek().location)
    }
    
    private func parseParameterList() throws -> [ParamDef] {
        try consume(.leftParen, "Expected '(' for parameter list")
        var params: [ParamDef] = []
        
        if !check(.rightParen) {
            repeat {
                let name: String
                if case .identifier(let id) = peek().type {
                    advance()
                    name = id
                } else if case .specialVar(let sp) = peek().type {
                    advance()
                    name = sp
                } else {
                    throw ParseError("Expected parameter name", location: peek().location)
                }
                
                var defaultVal: Expression? = nil
                if match(.equals) {
                    defaultVal = try parseExpression()
                }
                params.append(ParamDef(name: name, defaultValue: defaultVal))
            } while match(.comma)
        }
        
        try consume(.rightParen, "Expected ')' after parameter list")
        return params
    }
    
    private func parseArgumentList() throws -> [CallArg] {
        try consume(.leftParen, "Expected '(' for argument list")
        var args: [CallArg] = []
        
        if !check(.rightParen) {
            repeat {
                var argName: String? = nil
                // Check for named argument: identifier = expr
                if case .identifier(let id) = peek().type, peekNextTokenIsEquals() {
                    advance() // identifier
                    advance() // =
                    argName = id
                } else if case .specialVar(let sp) = peek().type, peekNextTokenIsEquals() {
                    advance() // specialVar
                    advance() // =
                    argName = sp
                }
                let val = try parseExpression()
                args.append(CallArg(name: argName, value: val))
            } while match(.comma)
        }
        
        try consume(.rightParen, "Expected ')' after argument list")
        return args
    }
    
    private func parseForBindings() throws -> [ForBinding] {
        try consume(.leftParen, "Expected '(' after for loop")
        var bindings: [ForBinding] = []
        
        repeat {
            let name: String
            if case .identifier(let id) = peek().type {
                advance()
                name = id
            } else if case .specialVar(let sp) = peek().type {
                advance()
                name = sp
            } else {
                throw ParseError("Expected variable name in for loop", location: peek().location)
            }
            
            try consume(.equals, "Expected '=' after variable name in for loop")
            let range = try parseExpression()
            bindings.append(ForBinding(name: name, range: range))
        } while match(.comma)
        
        try consume(.rightParen, "Expected ')' after for bindings")
        return bindings
    }
    
    private func parseBlockOrSingleStatement() throws -> [Statement] {
        if match(.leftBrace) {
            var body: [Statement] = []
            while !check(.rightBrace) && !isAtEnd {
                if let stmt = try parseStatement() {
                    body.append(stmt)
                }
            }
            try consume(.rightBrace, "Expected '}' to close block")
            return body
        } else {
            if let stmt = try parseStatement() {
                return [stmt]
            }
            return []
        }
    }
    
    // MARK: - Expressions (Pratt Parser / Operator Precedence)
    
    public func parseExpression() throws -> Expression {
        return try parseTernary()
    }
    
    private func parseTernary() throws -> Expression {
        var expr = try parseLogicalOr()
        if match(.question) {
            let thenExpr = try parseExpression()
            try consume(.colon, "Expected ':' in ternary conditional expression")
            let elseExpr = try parseExpression()
            expr = .ternary(condition: expr, thenExpr: thenExpr, elseExpr: elseExpr)
        }
        return expr
    }
    
    private func parseLogicalOr() throws -> Expression {
        var expr = try parseLogicalAnd()
        while match(.or) {
            let right = try parseLogicalAnd()
            expr = .binary(left: expr, op: .or, right: right)
        }
        return expr
    }
    
    private func parseLogicalAnd() throws -> Expression {
        var expr = try parseEquality()
        while match(.and) {
            let right = try parseEquality()
            expr = .binary(left: expr, op: .and, right: right)
        }
        return expr
    }
    
    private func parseEquality() throws -> Expression {
        var expr = try parseRelational()
        while true {
            if match(.equalEqual) {
                let right = try parseRelational()
                expr = .binary(left: expr, op: .equal, right: right)
            } else if match(.notEqual) {
                let right = try parseRelational()
                expr = .binary(left: expr, op: .notEqual, right: right)
            } else {
                break
            }
        }
        return expr
    }
    
    private func parseRelational() throws -> Expression {
        var expr = try parseAdditive()
        while true {
            if match(.less) {
                let right = try parseAdditive()
                expr = .binary(left: expr, op: .less, right: right)
            } else if match(.lessEqual) {
                let right = try parseAdditive()
                expr = .binary(left: expr, op: .lessEqual, right: right)
            } else if match(.greater) {
                let right = try parseAdditive()
                expr = .binary(left: expr, op: .greater, right: right)
            } else if match(.greaterEqual) {
                let right = try parseAdditive()
                expr = .binary(left: expr, op: .greaterEqual, right: right)
            } else {
                break
            }
        }
        return expr
    }
    
    private func parseAdditive() throws -> Expression {
        var expr = try parseMultiplicative()
        while true {
            if match(.plus) {
                let right = try parseMultiplicative()
                expr = .binary(left: expr, op: .add, right: right)
            } else if match(.minus) {
                let right = try parseMultiplicative()
                expr = .binary(left: expr, op: .subtract, right: right)
            } else {
                break
            }
        }
        return expr
    }
    
    private func parseMultiplicative() throws -> Expression {
        var expr = try parsePower()
        while true {
            if match(.star) {
                let right = try parsePower()
                expr = .binary(left: expr, op: .multiply, right: right)
            } else if match(.slash) {
                let right = try parsePower()
                expr = .binary(left: expr, op: .divide, right: right)
            } else if match(.percent) {
                let right = try parsePower()
                expr = .binary(left: expr, op: .modulo, right: right)
            } else {
                break
            }
        }
        return expr
    }
    
    private func parsePower() throws -> Expression {
        let expr = try parseUnary()
        if match(.caret) {
            let right = try parsePower() // Right-associative
            return .binary(left: expr, op: .power, right: right)
        }
        return expr
    }
    
    private func parseUnary() throws -> Expression {
        if match(.minus) {
            let expr = try parseUnary()
            return .unary(op: .negate, expr: expr)
        }
        if match(.bang) {
            let expr = try parseUnary()
            return .unary(op: .not, expr: expr)
        }
        if match(.plus) {
            let expr = try parseUnary()
            return .unary(op: .plus, expr: expr)
        }
        return try parsePostfix()
    }
    
    private func parsePostfix() throws -> Expression {
        var expr = try parsePrimary()
        
        while true {
            if match(.leftBracket) {
                // Index access: expr[index]
                let idx = try parseExpression()
                try consume(.rightBracket, "Expected ']' after index")
                expr = .subscriptAccess(expr: expr, index: idx)
            } else if match(.dot) {
                // Member access: expr.x
                let mem = try consumeIdentifier("Expected property name after '.'")
                expr = .memberAccess(expr: expr, member: mem)
            } else {
                break
            }
        }
        return expr
    }
    
    private func parsePrimary() throws -> Expression {
        // Literals
        if case .number(let n) = peek().type {
            advance()
            return .number(n)
        }
        if case .string(let s) = peek().type {
            advance()
            return .string(s)
        }
        if match(.true) {
            return .bool(true)
        }
        if match(.false) {
            return .bool(false)
        }
        if match(.undef) {
            return .undef
        }
        
        // Identifiers and function calls
        if case .identifier(let id) = peek().type {
            advance()
            if check(.leftParen) {
                let args = try parseArgumentList()
                return .call(name: id, args: args)
            }
            return .variable(id)
        }
        
        // Special variables ($fn, $t, etc.)
        if case .specialVar(let sp) = peek().type {
            advance()
            if check(.leftParen) {
                let args = try parseArgumentList()
                return .call(name: sp, args: args)
            }
            return .variable(sp)
        }
        
        // Function literal: function(params) expr
        if match(.function) {
            let params = try parseParameterList()
            let body = try parseExpression()
            return .functionLiteral(params: params, body: body)
        }
        
        // Let expression: let(bindings) expr
        if match(.let) {
            let bindings = try parseLetBindings()
            let body = try parseExpression()
            return .letExpr(bindings: bindings, body: body)
        }
        
        // Echo expression: echo(...) expr
        if match(.echo) {
            let args = try parseArgumentList()
            let body = try parseExpression()
            return .echoExpr(args: args, body: body)
        }
        
        // Assert expression: assert(cond, msg) expr
        if match(.assert) {
            try consume(.leftParen, "Expected '(' after assert")
            let cond = try parseExpression()
            var msg: Expression? = nil
            if match(.comma) {
                msg = try parseExpression()
            }
            try consume(.rightParen, "Expected ')' after assert")
            let body = try parseExpression()
            return .assertExpr(condition: cond, message: msg, body: body)
        }
        
        // Parenthesized expression: (expr)
        if match(.leftParen) {
            let expr = try parseExpression()
            try consume(.rightParen, "Expected ')' after expression")
            return expr
        }
        
        // Bracketed: vector literal, range, or list comprehension: [...]
        if match(.leftBracket) {
            return try parseBracketedExpression()
        }
        
        throw ParseError("Expected expression but found '\(peek().raw)'", location: peek().location)
    }
    
    private func parseLetBindings() throws -> [LetBinding] {
        try consume(.leftParen, "Expected '(' for let bindings")
        var bindings: [LetBinding] = []
        if !check(.rightParen) {
            repeat {
                let name: String
                if case .identifier(let id) = peek().type {
                    advance()
                    name = id
                } else if case .specialVar(let sp) = peek().type {
                    advance()
                    name = sp
                } else {
                    throw ParseError("Expected variable name in let binding", location: peek().location)
                }
                try consume(.equals, "Expected '=' in let binding")
                let val = try parseExpression()
                bindings.append(LetBinding(name: name, value: val))
            } while match(.comma)
        }
        try consume(.rightParen, "Expected ')' after let bindings")
        return bindings
    }
    
    private func parseBracketedExpression() throws -> Expression {
        // Check for empty vector []
        if match(.rightBracket) {
            return .vector([])
        }
        
        // Check for list comprehension keywords: for, if, let, each
        if check(.for) || check(.if) || check(.let) || check(.each) {
            let elements = try parseListCompElements()
            try consume(.rightBracket, "Expected ']' after list comprehension")
            return .listComprehension(elements)
        }
        
        // Parse first element
        let first = try parseExpression()
        
        // Check for range: [first : last] or [first : step : last]
        if match(.colon) {
            let second = try parseExpression()
            if match(.colon) {
                let third = try parseExpression()
                try consume(.rightBracket, "Expected ']' after range")
                return .range(from: first, step: second, to: third)
            } else {
                try consume(.rightBracket, "Expected ']' after range")
                return .range(from: first, step: nil, to: second)
            }
        }
        
        // Otherwise it's a vector: [first, second, ...]
        var elements: [Expression] = [first]
        while match(.comma) {
            if check(.rightBracket) { break } // allow trailing comma
            elements.append(try parseExpression())
        }
        try consume(.rightBracket, "Expected ']' after vector")
        return .vector(elements)
    }
    
    private func parseListCompElements() throws -> [ListCompElement] {
        var elements: [ListCompElement] = []
        while !check(.rightBracket) && !isAtEnd {
            if match(.for) {
                let bindings = try parseForBindings()
                let sub = try parseListCompSubElements()
                elements.append(.forLoop(variables: bindings, elements: sub))
            } else if match(.if) {
                try consume(.leftParen, "Expected '(' after if in list comprehension")
                let cond = try parseExpression()
                try consume(.rightParen, "Expected ')' after if condition")
                let thenElements = try parseListCompSubElements()
                var elseElements: [ListCompElement]? = nil
                if match(.else) {
                    elseElements = try parseListCompSubElements()
                }
                elements.append(.ifCond(condition: cond, thenElements: thenElements, elseElements: elseElements))
            } else if match(.let) {
                let bindings = try parseLetBindings()
                let sub = try parseListCompSubElements()
                elements.append(.letBinding(bindings: bindings, elements: sub))
            } else if match(.each) {
                let expr = try parseExpression()
                elements.append(.each(expr))
            } else {
                let expr = try parseExpression()
                elements.append(.expression(expr))
            }
            _ = match(.comma)
        }
        return elements
    }
    
    private func parseListCompSubElements() throws -> [ListCompElement] {
        if check(.for) || check(.if) || check(.let) || check(.each) {
            return try parseListCompElements()
        }
        let expr = try parseExpression()
        return [.expression(expr)]
    }
}
