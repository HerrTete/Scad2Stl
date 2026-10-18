import SwiftUI

public struct ConsoleView: View {
    @ObservedObject public var model: AppModel
    
    public init(model: AppModel) {
        self.model = model
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // Header bar
            HStack {
                Text("Console")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Button(action: {
                    model.consoleMessages.removeAll()
                }) {
                    Image(systemName: "trash")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .help("Clear Console")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Color(NSColor.windowBackgroundColor))
            
            Divider()
            
            // Log messages
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        if model.consoleMessages.isEmpty {
                            Text("No output yet. Hit Preview (F5) or Render.")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.secondary)
                                .padding(8)
                        } else {
                            ForEach(model.consoleMessages) { msg in
                                HStack(alignment: .top, spacing: 6) {
                                    icon(for: msg.type)
                                    Text(msg.text)
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundColor(color(for: msg.type))
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 1)
                                .id(msg.id)
                            }
                        }
                    }
                }
                .background(Color(red: 0.11, green: 0.12, blue: 0.14))
                .onChange(of: model.consoleMessages.count) { _, _ in
                    if let last = model.consoleMessages.last {
                        withAnimation {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private func icon(for type: ConsoleMessage.MessageType) -> some View {
        switch type {
        case .info:
            Image(systemName: "info.circle.fill")
                .foregroundColor(.blue)
                .font(.system(size: 10))
        case .warning:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.yellow)
                .font(.system(size: 10))
        case .error:
            Image(systemName: "xmark.octagon.fill")
                .foregroundColor(.red)
                .font(.system(size: 10))
        case .echo:
            Image(systemName: "chevron.right")
                .foregroundColor(.green)
                .font(.system(size: 9, weight: .bold))
        }
    }
    
    private func color(for type: ConsoleMessage.MessageType) -> Color {
        switch type {
        case .info: return Color(red: 0.7, green: 0.8, blue: 0.95)
        case .warning: return Color(red: 0.95, green: 0.85, blue: 0.5)
        case .error: return Color(red: 0.95, green: 0.45, blue: 0.45)
        case .echo: return Color(red: 0.85, green: 0.88, blue: 0.92)
        }
    }
}
