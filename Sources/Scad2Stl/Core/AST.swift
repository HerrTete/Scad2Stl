import Foundation

public enum GeometryModifier: Equatable, Sendable {
    case disable    // *
    case showOnly   // !
    case highlight  // #
    case background // %
}

public struct ParamDef: Equatable, Sendable {
    public let name: String
    public let defaultValue: Expression?
    
    public init(name: String, defaultValue: Expression? = nil) {
        self.name = name
        self.defaultValue = defaultValue
    }
}

public struct CallArg: Equatable, Sendable {
    public let name: String? // nil for positional argument
    public let value: Expression
    
    public init(name: String? = nil, value: Expression) {
        self.name = name
        self.value = value
    }
}

public struct ForBinding: Equatable, Sendable {
    public let name: String
    public let range: Expression
    
    public init(name: String, range: Expression) {
        self.name = name
        self.range = range
    }
}

public struct LetBinding: Equatable, Sendable {
    public let name: String
    public let value: Expression
    
    public init(name: String, value: Expression) {
        self.name = name
        self.value = value
    }
}

public enum UnaryOp: Equatable, Sendable {
    case negate // -
    case not    // !
    case plus   // +
}

public enum BinaryOp: Equatable, Sendable {
    case add, subtract, multiply, divide, modulo, power
    case equal, notEqual, less, lessEqual, greater, greaterEqual
    case and, or
}

public enum ListCompElement: Equatable, Sendable {
    case expression(Expression)
    case each(Expression)
    case forLoop(variables: [ForBinding], elements: [ListCompElement])
    case ifCond(condition: Expression, thenElements: [ListCompElement], elseElements: [ListCompElement]?)
    case letBinding(bindings: [LetBinding], elements: [ListCompElement])
}

public indirect enum Expression: Equatable, Sendable {
    case number(Double)
    case string(String)
    case bool(Bool)
    case undef
    case variable(String)
    case vector([Expression])
    case range(from: Expression, step: Expression?, to: Expression)
    case unary(op: UnaryOp, expr: Expression)
    case binary(left: Expression, op: BinaryOp, right: Expression)
    case ternary(condition: Expression, thenExpr: Expression, elseExpr: Expression)
    case subscriptAccess(expr: Expression, index: Expression)
    case memberAccess(expr: Expression, member: String)
    case call(name: String, args: [CallArg])
    case functionLiteral(params: [ParamDef], body: Expression)
    case letExpr(bindings: [LetBinding], body: Expression)
    case listComprehension([ListCompElement])
    case assertExpr(condition: Expression, message: Expression?, body: Expression)
    case echoExpr(args: [CallArg], body: Expression)
}

public indirect enum Statement: Equatable, Sendable {
    case assignment(name: String, value: Expression, location: SourceLocation)
    case moduleDef(name: String, params: [ParamDef], body: [Statement], location: SourceLocation)
    case functionDef(name: String, params: [ParamDef], body: Expression, location: SourceLocation)
    case moduleCall(name: String, args: [CallArg], children: [Statement], modifier: GeometryModifier?, location: SourceLocation)
    case ifStatement(condition: Expression, thenBranch: [Statement], elseBranch: [Statement]?, location: SourceLocation)
    case forLoop(variables: [ForBinding], body: [Statement], location: SourceLocation)
    case intersectionFor(variables: [ForBinding], body: [Statement], location: SourceLocation)
    case echoStatement(args: [CallArg], location: SourceLocation)
    case assertStatement(condition: Expression, message: Expression?, location: SourceLocation)
    case includeDirective(path: String, location: SourceLocation)
    case useDirective(path: String, location: SourceLocation)
}

public struct Program: Equatable, Sendable {
    public let statements: [Statement]
    
    public init(statements: [Statement]) {
        self.statements = statements
    }
}
