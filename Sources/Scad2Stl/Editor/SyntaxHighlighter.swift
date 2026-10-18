import AppKit

public final class SyntaxHighlighter {
    public struct Theme {
        public var background = NSColor(red: 0.14, green: 0.15, blue: 0.17, alpha: 1.0)
        public var defaultText = NSColor(red: 0.87, green: 0.88, blue: 0.90, alpha: 1.0)
        public var keyword = NSColor(red: 0.78, green: 0.47, blue: 0.87, alpha: 1.0)      // Purple
        public var builtin = NSColor(red: 0.38, green: 0.69, blue: 0.94, alpha: 1.0)      // Blue
        public var specialVar = NSColor(red: 0.90, green: 0.75, blue: 0.48, alpha: 1.0)   // Gold
        public var number = NSColor(red: 0.82, green: 0.60, blue: 0.40, alpha: 1.0)       // Orange
        public var string = NSColor(red: 0.60, green: 0.76, blue: 0.47, alpha: 1.0)       // Green
        public var comment = NSColor(red: 0.45, green: 0.49, blue: 0.55, alpha: 1.0)      // Muted Gray
        
        public static let defaultDark = Theme()
    }
    
    private let theme: Theme
    private let font: NSFont
    
    private let keywordRegex: NSRegularExpression?
    private let builtinRegex: NSRegularExpression?
    private let specialVarRegex: NSRegularExpression?
    private let numberRegex: NSRegularExpression?
    private let stringRegex: NSRegularExpression?
    private let lineCommentRegex: NSRegularExpression?
    private let blockCommentRegex: NSRegularExpression?
    
    public init(theme: Theme = .defaultDark, font: NSFont = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)) {
        self.theme = theme
        self.font = font
        
        let keywords = ["module", "function", "if", "else", "for", "intersection_for", "let", "each", "true", "false", "undef", "include", "use", "echo", "assert"]
        let builtins = ["cube", "sphere", "cylinder", "polyhedron", "square", "circle", "polygon", "translate", "rotate", "scale", "mirror", "color", "union", "difference", "intersection", "hull", "linear_extrude", "rotate_extrude", "sin", "cos", "tan", "asin", "acos", "atan", "atan2", "abs", "sign", "floor", "ceil", "round", "sqrt", "exp", "log", "ln", "pow", "min", "max", "norm", "cross", "rands", "str", "chr", "ord", "len", "concat", "lookup", "children"]
        
        self.keywordRegex = try? NSRegularExpression(pattern: "\\b(" + keywords.joined(separator: "|") + ")\\b")
        self.builtinRegex = try? NSRegularExpression(pattern: "\\b(" + builtins.joined(separator: "|") + ")\\b")
        self.specialVarRegex = try? NSRegularExpression(pattern: "\\$[a-zA-Z_][a-zA-Z0-9_]*")
        self.numberRegex = try? NSRegularExpression(pattern: "\\b[0-9]+(\\.[0-9]+)?([eE][+-]?[0-9]+)?\\b")
        self.stringRegex = try? NSRegularExpression(pattern: "\"[^\"\\\\]*(\\\\.[^\"\\\\]*)*\"")
        self.lineCommentRegex = try? NSRegularExpression(pattern: "//.*$", options: [.anchorsMatchLines])
        self.blockCommentRegex = try? NSRegularExpression(pattern: "/\\*[\\s\\S]*?\\*/")
    }
    
    public func highlight(textStorage: NSTextStorage) {
        let string = textStorage.string
        let fullRange = NSRange(location: 0, length: (string as NSString).length)
        guard fullRange.length > 0 else { return }
        
        textStorage.beginEditing()
        
        // Base attributes
        textStorage.setAttributes([
            .font: font,
            .foregroundColor: theme.defaultText
        ], range: fullRange)
        
        // 1. Numbers
        if let regex = numberRegex {
            regex.enumerateMatches(in: string, range: fullRange) { match, _, _ in
                if let r = match?.range {
                    textStorage.addAttribute(.foregroundColor, value: theme.number, range: r)
                }
            }
        }
        
        // 2. Builtins
        if let regex = builtinRegex {
            regex.enumerateMatches(in: string, range: fullRange) { match, _, _ in
                if let r = match?.range {
                    textStorage.addAttribute(.foregroundColor, value: theme.builtin, range: r)
                }
            }
        }
        
        // 3. Special Variables ($fn, $t, etc.)
        if let regex = specialVarRegex {
            regex.enumerateMatches(in: string, range: fullRange) { match, _, _ in
                if let r = match?.range {
                    textStorage.addAttribute(.foregroundColor, value: theme.specialVar, range: r)
                }
            }
        }
        
        // 4. Keywords
        if let regex = keywordRegex {
            regex.enumerateMatches(in: string, range: fullRange) { match, _, _ in
                if let r = match?.range {
                    textStorage.addAttribute(.foregroundColor, value: theme.keyword, range: r)
                }
            }
        }
        
        // 5. Strings
        if let regex = stringRegex {
            regex.enumerateMatches(in: string, range: fullRange) { match, _, _ in
                if let r = match?.range {
                    textStorage.addAttribute(.foregroundColor, value: theme.string, range: r)
                }
            }
        }
        
        // 6. Block Comments
        if let regex = blockCommentRegex {
            regex.enumerateMatches(in: string, range: fullRange) { match, _, _ in
                if let r = match?.range {
                    textStorage.addAttribute(.foregroundColor, value: theme.comment, range: r)
                }
            }
        }
        
        // 7. Line Comments
        if let regex = lineCommentRegex {
            regex.enumerateMatches(in: string, range: fullRange) { match, _, _ in
                if let r = match?.range {
                    textStorage.addAttribute(.foregroundColor, value: theme.comment, range: r)
                }
            }
        }
        
        textStorage.endEditing()
    }
}
