import AppKit

public final class LineNumberGutter: NSRulerView {
    public var font: NSFont = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
    public var textColor: NSColor = NSColor(red: 0.45, green: 0.48, blue: 0.54, alpha: 1.0)
    public var backgroundColor: NSColor = NSColor(red: 0.12, green: 0.13, blue: 0.15, alpha: 1.0)
    public var borderColor: NSColor = NSColor(red: 0.20, green: 0.22, blue: 0.25, alpha: 1.0)
    
    public override var isFlipped: Bool {
        return true
    }
    
    public init(textView: NSTextView) {
        super.init(scrollView: textView.enclosingScrollView, orientation: .verticalRuler)
        self.clientView = textView
        self.ruleThickness = 42.0
    }
    
    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let textView = clientView as? NSTextView,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else {
            return
        }
        
        // Strictly fill only within gutter bounds so it NEVER paints over the text view!
        let gutterBounds = NSRect(x: 0, y: 0, width: bounds.width, height: bounds.height)
        let fillRect = NSIntersectionRect(gutterBounds, rect)
        guard !fillRect.isEmpty else { return }
        
        backgroundColor.setFill()
        fillRect.fill()
        
        // Right border line
        borderColor.setStroke()
        let borderPath = NSBezierPath()
        borderPath.move(to: NSPoint(x: bounds.maxX - 0.5, y: fillRect.minY))
        borderPath.line(to: NSPoint(x: bounds.maxX - 0.5, y: fillRect.maxY))
        borderPath.lineWidth = 1.0
        borderPath.stroke()
        
        let visibleRect = scrollView?.contentView.bounds ?? bounds
        let visibleGlyphRange = layoutManager.glyphRange(forBoundingRect: visibleRect, in: textContainer)
        let text = textView.string as NSString
        
        // Dynamically adjust rule thickness based on line count
        var lineCount = 1
        for i in 0..<text.length {
            if text.character(at: i) == 10 { // newline \n
                lineCount += 1
            }
        }
        let neededWidth = max(42.0, CGFloat(String(lineCount).count) * 8.5 + 18.0)
        if abs(ruleThickness - neededWidth) > 2.0 {
            DispatchQueue.main.async { [weak self] in
                self?.ruleThickness = neededWidth
            }
        }
        
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: textColor
        ]
        
        var lineNumber = 1
        var charIndex = 0
        let visibleStart = layoutManager.characterIndexForGlyph(at: visibleGlyphRange.location)
        
        // Count lines up to visible range start
        while charIndex < visibleStart && charIndex < text.length {
            if text.character(at: charIndex) == 10 {
                lineNumber += 1
            }
            charIndex += 1
        }
        
        let insetY = textView.textContainerInset.height
        var glyphIndex = visibleGlyphRange.location
        while glyphIndex < NSMaxRange(visibleGlyphRange) && glyphIndex < layoutManager.numberOfGlyphs {
            var lineRange = NSRange()
            let lineRect = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: &lineRange)
            
            let label = "\(lineNumber)" as NSString
            let labelSize = label.size(withAttributes: attributes)
            let drawX = bounds.width - labelSize.width - 8.0
            let drawY = lineRect.origin.y + insetY + (lineRect.height - labelSize.height) / 2.0 - visibleRect.origin.y
            
            label.draw(at: NSPoint(x: drawX, y: drawY), withAttributes: attributes)
            
            lineNumber += 1
            glyphIndex = NSMaxRange(lineRange)
        }
    }
}
