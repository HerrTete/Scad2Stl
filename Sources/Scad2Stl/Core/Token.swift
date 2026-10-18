import Foundation

public enum TokenType: Equatable, Sendable {
    // Literals
    case number(Double)
    case string(String)
    case identifier(String)
    case specialVar(String) // starts with $ (e.g. $fn, $fa, $t)
    
    // Keywords
    case module
    case function
    case `if`
    case `else`
    case `for`
    case intersection_for
    case `let`
    case each
    case `true`
    case `false`
    case undef
    case include
    case use
    case assert
    case echo
    
    // Operators
    case plus           // +
    case minus          // -
    case star           // *
    case slash          // /
    case percent        // %
    case caret          // ^
    
    // Comparison
    case equalEqual     // ==
    case notEqual       // !=
    case less           // <
    case lessEqual      // <=
    case greater        // >
    case greaterEqual   // >=
    
    // Logical
    case and            // &&
    case or             // ||
    case bang           // !
    
    // Punctuation
    case question       // ?
    case colon          // :
    case equals         // =
    case semicolon      // ;
    case comma          // ,
    case dot            // .
    case leftParen      // (
    case rightParen     // )
    case leftBrace      // {
    case rightBrace     // }
    case leftBracket    // [
    case rightBracket   // ]
    
    // Geometry Modifiers
    case modifierHash   // # (highlight / debug)
    case modifierPercent// % (transparent background)
    case modifierStar   // * (disable)
    case modifierBang   // ! (show only / root)
    
    // Special include bracket: <...>
    case pathString(String) // inside <...> for include/use
    
    case eof
}

public struct SourceLocation: Equatable, Sendable {
    public let line: Int
    public let column: Int
    
    public init(line: Int, column: Int) {
        self.line = line
        self.column = column
    }
}

public struct Token: Equatable, Sendable {
    public let type: TokenType
    public let location: SourceLocation
    public let raw: String
    
    public init(type: TokenType, location: SourceLocation, raw: String) {
        self.type = type
        self.location = location
        self.raw = raw
    }
}
