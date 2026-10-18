import SwiftUI

@MainActor
public struct TabBarView: View {
    @ObservedObject public var model: AppModel
    
    public init(model: AppModel) {
        self.model = model
    }
    
    public var body: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    ForEach(model.tabs) { tab in
                        TabItemView(
                            tab: tab,
                            isActive: tab.id == model.activeTabId,
                            onSelect: {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    model.activeTabId = tab.id
                                }
                            },
                            onClose: {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    model.closeTab(id: tab.id)
                                }
                            }
                        )
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
            }
            
            // New Tab (+) Button
            Button(action: {
                withAnimation(.easeInOut(duration: 0.15)) {
                    _ = model.addNewTab()
                }
            }) {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("New Tab (Cmd+T)")
            .padding(.trailing, 8)
        }
        .frame(height: 32)
        .background(Color(NSColor.windowBackgroundColor))
        .overlay(
            Divider(),
            alignment: .bottom
        )
    }
}

@MainActor
struct TabItemView: View {
    @ObservedObject var tab: ProjectTab
    let isActive: Bool
    let onSelect: () -> Void
    let onClose: () -> Void
    
    @State private var isHovering = false
    @State private var isCloseHovering = false
    
    var body: some View {
        HStack(spacing: 6) {
            // Document icon
            Image(systemName: "doc.text")
                .font(.system(size: 11))
                .foregroundColor(isActive ? .primary : .secondary)
            
            // Tab Title
            Text(tab.title)
                .font(.system(size: 12, weight: isActive ? .medium : .regular))
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundColor(isActive ? .primary : .secondary)
            
            // Edited dot indicator
            if tab.isEdited {
                Circle()
                    .fill(Color.orange)
                    .frame(width: 6, height: 6)
                    .help("Unsaved changes")
            }
            
            // Close Button (visible on active or hover)
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(isCloseHovering ? .primary : .secondary)
                    .frame(width: 14, height: 14)
                    .background(
                        RoundedRectangle(cornerRadius: 3)
                            .fill(isCloseHovering ? Color.primary.opacity(0.12) : Color.clear)
                    )
            }
            .buttonStyle(.plain)
            .opacity((isActive || isHovering) ? 1.0 : 0.0)
            .onHover { hovering in
                isCloseHovering = hovering
            }
            .help("Close Tab (Cmd+W)")
        }
        .padding(.horizontal, 10)
        .frame(height: 25)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isActive ? Color(NSColor.controlBackgroundColor) : (isHovering ? Color.primary.opacity(0.05) : Color.clear))
                .shadow(color: isActive ? Color.black.opacity(0.08) : Color.clear, radius: 1, y: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect()
        }
        .onHover { hovering in
            isHovering = hovering
        }
    }
}
