import SwiftUI
import AppKit

public struct ScadCodeEditorView: NSViewRepresentable {
    @Binding public var text: String
    public var onCompile: (() -> Void)?
    
    public init(text: Binding<String>, onCompile: (() -> Void)? = nil) {
        self._text = text
        self.onCompile = onCompile
    }
    
    public func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        scrollView.backgroundColor = NSColor(red: 0.14, green: 0.15, blue: 0.17, alpha: 1.0)
        
        let textView = NSTextView(usingTextLayoutManager: false)
        
        // Sizing and layout configuration
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = NSSize(width: 0.0, height: 0.0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainerInset = NSSize(width: 6, height: 8)
        textView.textContainer?.lineFragmentPadding = 4
        
        // Editor behavior
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        
        // Appearance
        let font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        let textColor = NSColor(red: 0.88, green: 0.89, blue: 0.92, alpha: 1.0)
        textView.font = font
        textView.backgroundColor = NSColor(red: 0.14, green: 0.15, blue: 0.17, alpha: 1.0)
        textView.insertionPointColor = NSColor.white
        textView.textColor = textColor
        textView.typingAttributes = [
            .font: font,
            .foregroundColor: textColor
        ]
        textView.selectedTextAttributes = [
            .backgroundColor: NSColor.selectedTextBackgroundColor,
            .foregroundColor: NSColor.white
        ]
        
        textView.delegate = context.coordinator
        context.coordinator.textView = textView
        context.coordinator.onCompile = onCompile
        
        scrollView.documentView = textView
        
        // Add line number gutter
        let gutter = LineNumberGutter(textView: textView)
        scrollView.verticalRulerView = gutter
        scrollView.hasVerticalRuler = true
        scrollView.rulersVisible = true
        
        // Populate initial text
        textView.string = text
        if let textStorage = textView.textStorage {
            context.coordinator.highlighter.highlight(textStorage: textStorage)
        }
        
        return scrollView
    }
    
    public func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        if textView.string != text {
            textView.string = text
            if let textStorage = textView.textStorage {
                context.coordinator.highlighter.highlight(textStorage: textStorage)
            }
            nsView.verticalRulerView?.needsDisplay = true
        }
    }
    
    public func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    public final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: ScadCodeEditorView
        weak var textView: NSTextView?
        let highlighter = SyntaxHighlighter()
        var onCompile: (() -> Void)?
        
        init(_ parent: ScadCodeEditorView) {
            self.parent = parent
        }
        
        public func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            let newText = tv.string
            if self.parent.text != newText {
                self.parent.text = newText
            }
            if let textStorage = tv.textStorage {
                highlighter.highlight(textStorage: textStorage)
            }
            tv.enclosingScrollView?.verticalRulerView?.needsDisplay = true
        }
        
        public func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSStandardKeyBindingResponding.insertTab(_:)) {
                textView.insertText("    ", replacementRange: textView.selectedRange())
                return true
            }
            return false
        }
    }
}

