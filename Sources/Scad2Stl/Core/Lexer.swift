import Foundation

public final class Lexer {
    private let source: String
    private var characters: [Character]
    private var index: Int = 0
    private var currentLine: Int = 1
    private var currentColumn: Int = 1
    private var lastEmittedToken: TokenType? = nil
    
    public init(_ source: String) {
        self.source = source
        self.characters = Array(source)
    }
    
    private var isAtEnd: Bool {
        return index >= characters.count
    }
    
    private var currentChar: Character {
        return isAtEnd ? "\0" : characters[index]
    }
    
    private func peekNext() -> Character {
        let nextIndex = index + 1
        return nextIndex < characters.count ? characters[nextIndex] : "\0"
    }
    
    @discardableResult
    private func advance() -> Character {
        guard !isAtEnd else { return "\0" }
        let c = characters[index]
        index += 1
        if c == "\n" {
            currentLine += 1
            currentColumn = 1
        } else {
            currentColumn += 1
        }
        return c
    }
    
    public func tokenize() -> [Token] {
        var tokens: [Token] = []
        
        while !isAtEnd {
            skipWhitespaceAndComments()
            guard !isAtEnd else { break }
            
            let startLine = currentLine
            let startColumn = currentColumn
            let startIndex = index
            let loc = SourceLocation(line: startLine, column: startColumn)
            
            // Check for path include: if last token was `include` or `use` and current is `<`
            if (lastEmittedToken == .include || lastEmittedToken == .use) && currentChar == "<" {
                advance() // consume '<'
                var pathStr = ""
                while !isAtEnd && currentChar != ">" && currentChar != "\n" {
                    pathStr.append(advance())
                }
                if currentChar == ">" {
                    advance() // consume '>'
                }
                let tok = Token(type: .pathString(pathStr), location: loc, raw: "<" + pathStr + ">")
                tokens.append(tok)
                lastEmittedToken = tok.type
                continue
            }
            
            let c = advance()
            
            switch c {
            case "(": tokens.append(Token(type: .leftParen, location: loc, raw: "("))
            case ")": tokens.append(Token(type: .rightParen, location: loc, raw: ")"))
            case "{": tokens.append(Token(type: .leftBrace, location: loc, raw: "{"))
            case "}": tokens.append(Token(type: .rightBrace, location: loc, raw: "}"))
            case "[": tokens.append(Token(type: .leftBracket, location: loc, raw: "["))
            case "]": tokens.append(Token(type: .rightBracket, location: loc, raw: "]"))
            case ";": tokens.append(Token(type: .semicolon, location: loc, raw: ";"))
            case ",": tokens.append(Token(type: .comma, location: loc, raw: ","))
            case ":": tokens.append(Token(type: .colon, location: loc, raw: ":"))
            case "?": tokens.append(Token(type: .question, location: loc, raw: "?"))
            case "^": tokens.append(Token(type: .caret, location: loc, raw: "^"))
            case "#": tokens.append(Token(type: .modifierHash, location: loc, raw: "#"))
                
            case ".":
                tokens.append(Token(type: .dot, location: loc, raw: "."))
                
            case "+":
                tokens.append(Token(type: .plus, location: loc, raw: "+"))
                
            case "-":
                tokens.append(Token(type: .minus, location: loc, raw: "-"))
                
            case "*":
                tokens.append(Token(type: .star, location: loc, raw: "*"))
                
            case "/":
                tokens.append(Token(type: .slash, location: loc, raw: "/"))
                
            case "%":
                tokens.append(Token(type: .percent, location: loc, raw: "%"))
                
            case "=":
                if currentChar == "=" {
                    advance()
                    tokens.append(Token(type: .equalEqual, location: loc, raw: "=="))
                } else {
                    tokens.append(Token(type: .equals, location: loc, raw: "="))
                }
                
            case "!":
                if currentChar == "=" {
                    advance()
                    tokens.append(Token(type: .notEqual, location: loc, raw: "!="))
                } else {
                    tokens.append(Token(type: .bang, location: loc, raw: "!"))
                }
                
            case "<":
                if currentChar == "=" {
                    advance()
                    tokens.append(Token(type: .lessEqual, location: loc, raw: "<="))
                } else {
                    tokens.append(Token(type: .less, location: loc, raw: "<"))
                }
                
            case ">":
                if currentChar == "=" {
                    advance()
                    tokens.append(Token(type: .greaterEqual, location: loc, raw: ">="))
                } else {
                    tokens.append(Token(type: .greater, location: loc, raw: ">"))
                }
                
            case "&":
                if currentChar == "&" {
                    advance()
                    tokens.append(Token(type: .and, location: loc, raw: "&&"))
                } else {
                    // unexpected single &, still emit or ignore
                    tokens.append(Token(type: .identifier("&"), location: loc, raw: "&"))
                }
                
            case "|":
                if currentChar == "|" {
                    advance()
                    tokens.append(Token(type: .or, location: loc, raw: "||"))
                } else {
                    tokens.append(Token(type: .identifier("|"), location: loc, raw: "|"))
                }
                
            case "\"":
                let str = scanString()
                let raw = String(characters[startIndex..<index])
                tokens.append(Token(type: .string(str), location: loc, raw: raw))
                
            case "$":
                let ident = scanIdentifierBody()
                let fullName = "$" + ident
                tokens.append(Token(type: .specialVar(fullName), location: loc, raw: fullName))
                
            default:
                if c.isNumber {
                    index -= 1
                    currentColumn -= 1
                    let (numVal, raw) = scanNumber()
                    tokens.append(Token(type: .number(numVal), location: loc, raw: raw))
                } else if isIdentifierStart(c) {
                    index -= 1
                    currentColumn -= 1
                    let ident = scanIdentifier()
                    let tokenType = keywordOrIdentifier(ident)
                    tokens.append(Token(type: tokenType, location: loc, raw: ident))
                } else {
                    // Unknown character, skip
                    break
                }
            }
            
            if let last = tokens.last {
                lastEmittedToken = last.type
            }
        }
        
        tokens.append(Token(type: .eof, location: SourceLocation(line: currentLine, column: currentColumn), raw: ""))
        return tokens
    }
    
    private func skipWhitespaceAndComments() {
        while !isAtEnd {
            let c = currentChar
            if c.isWhitespace {
                advance()
            } else if c == "/" && peekNext() == "/" {
                // Line comment
                advance() // /
                advance() // /
                while !isAtEnd && currentChar != "\n" {
                    advance()
                }
            } else if c == "/" && peekNext() == "*" {
                // Block comment
                advance() // /
                advance() // *
                while !isAtEnd {
                    if currentChar == "*" && peekNext() == "/" {
                        advance() // *
                        advance() // /
                        break
                    }
                    advance()
                }
            } else {
                break
            }
        }
    }
    
    private func scanString() -> String {
        var result = ""
        while !isAtEnd {
            let c = advance()
            if c == "\"" {
                break
            }
            if c == "\\" && !isAtEnd {
                let escaped = advance()
                switch escaped {
                case "n": result.append("\n")
                case "t": result.append("\t")
                case "r": result.append("\r")
                case "\\": result.append("\\")
                case "\"": result.append("\"")
                case "u":
                    // Unicode escape \uXXXX or \u{XXXX}
                    if currentChar == "{" {
                        advance() // {
                        var hexStr = ""
                        while !isAtEnd && currentChar != "}" {
                            hexStr.append(advance())
                        }
                        if currentChar == "}" { advance() }
                        if let code = UInt32(hexStr, radix: 16), let scalar = UnicodeScalar(code) {
                            result.append(Character(scalar))
                        }
                    } else {
                        var hexStr = ""
                        for _ in 0..<4 {
                            if !isAtEnd && currentChar.isHexDigit {
                                hexStr.append(advance())
                            }
                        }
                        if let code = UInt32(hexStr, radix: 16), let scalar = UnicodeScalar(code) {
                            result.append(Character(scalar))
                        }
                    }
                default:
                    result.append(escaped)
                }
            } else {
                result.append(c)
            }
        }
        return result
    }
    
    private func scanNumber() -> (Double, String) {
        let startIndex = index
        while !isAtEnd && currentChar.isNumber {
            advance()
        }
        if currentChar == "." && peekNext().isNumber {
            advance() // .
            while !isAtEnd && currentChar.isNumber {
                advance()
            }
        }
        // Exponent: e or E
        if currentChar == "e" || currentChar == "E" {
            let next = peekNext()
            if next.isNumber || next == "+" || next == "-" {
                advance() // e
                if currentChar == "+" || currentChar == "-" {
                    advance()
                }
                while !isAtEnd && currentChar.isNumber {
                    advance()
                }
            }
        }
        let raw = String(characters[startIndex..<index])
        let value = Double(raw) ?? 0.0
        return (value, raw)
    }
    
    private func isIdentifierStart(_ c: Character) -> Bool {
        return c.isLetter || c == "_"
    }
    
    private func isIdentifierChar(_ c: Character) -> Bool {
        return c.isLetter || c.isNumber || c == "_"
    }
    
    private func scanIdentifier() -> String {
        let startIndex = index
        while !isAtEnd && isIdentifierChar(currentChar) {
            advance()
        }
        return String(characters[startIndex..<index])
    }
    
    private func scanIdentifierBody() -> String {
        let startIndex = index
        while !isAtEnd && isIdentifierChar(currentChar) {
            advance()
        }
        return String(characters[startIndex..<index])
    }
    
    private func keywordOrIdentifier(_ text: String) -> TokenType {
        switch text {
        case "module": return .module
        case "function": return .function
        case "if": return .if
        case "else": return .else
        case "for": return .for
        case "intersection_for": return .intersection_for
        case "let": return .let
        case "each": return .each
        case "true": return .true
        case "false": return .false
        case "undef": return .undef
        case "include": return .include
        case "use": return .use
        case "assert": return .assert
        case "echo": return .echo
        default: return .identifier(text)
        }
    }
}
