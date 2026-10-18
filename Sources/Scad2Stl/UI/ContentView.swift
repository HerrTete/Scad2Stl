import SwiftUI

@MainActor
public struct ContentView: View {
    @ObservedObject public var model: AppModel
    
    public init(model: AppModel) {
        self.model = model
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // Top Tab Bar for multi-project management
            TabBarView(model: model)
            
            HSplitView {
                // Left Pane: Editor + Console
                VSplitView {
                    VStack(spacing: 0) {
                        ScadCodeEditorView(text: $model.sourceCode) {
                            model.compile()
                        }
                        .id(model.activeTabId)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .frame(minWidth: 350, maxWidth: .infinity, minHeight: 250, maxHeight: .infinity)
                    
                    ConsoleView(model: model)
                        .id(model.activeTabId)
                        .frame(minHeight: 100, maxHeight: 250)
                }
                .frame(minWidth: 350, maxWidth: .infinity, maxHeight: .infinity)
                
                // Right Pane: 3D Metal Viewport
                ZStack(alignment: .bottomTrailing) {
                    CADViewportView(mesh: model.currentMesh, camera: model.camera)
                        .id(model.activeTabId)
                        .frame(minWidth: 400, minHeight: 300)
                    
                    // HUD Information Overlay
                    HudOverlayView(
                        polygonCount: model.polygonCount,
                        boundsString: model.boundsString,
                        compileTime: model.compileTime
                    )
                    .padding(12)
                }
            }
        }
        .navigationTitle(model.documentTitle + (model.isDocumentEdited ? " — Edited" : ""))
        .navigationSubtitle(model.currentFileURL?.deletingLastPathComponent().path ?? "")
        .toolbar {
            toolbarItems
        }
        .modifier(NotificationHandlersModifier(model: model))
        .onDrop(of: [.fileURL], isTargeted: nil, perform: handleDrop)
    }
    
    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Button(action: { model.newFile() }) {
                Label("New", systemImage: "doc.badge.plus")
            }
            .keyboardShortcut("n", modifiers: [.command])
            .help("New Tab (Cmd+N)")
            
            Button(action: { model.openFile() }) {
                Label("Open", systemImage: "folder")
            }
            .keyboardShortcut("o", modifiers: [.command])
            .help("Open OpenSCAD Script (Cmd+O)")
            
            Button(action: { model.saveFile() }) {
                Label("Save", systemImage: "square.and.arrow.down")
            }
            .keyboardShortcut("s", modifiers: [.command])
            .help("Save Script (Cmd+S)")
        }
        
        ToolbarItemGroup(placement: .primaryAction) {
            Button(action: { model.compile() }) {
                Label("Render", systemImage: "play.fill")
            }
            .keyboardShortcut("r", modifiers: [.command])
            .help("Render OpenSCAD Script (Cmd+R or F5)")
            
            Button(action: { model.exportSTL() }) {
                Label("Export STL", systemImage: "shippingbox")
            }
            .keyboardShortcut("e", modifiers: [.command])
            .help("Export Model as Binary STL (Cmd+E)")
            
            Divider()
            
            Button(action: { model.fitView() }) {
                Image(systemName: "viewfinder")
            }
            .help("Fit View to Model")
            
            Button(action: { model.resetCamera() }) {
                Image(systemName: "arrow.counterclockwise")
            }
            .help("Reset Camera")
            
            Toggle(isOn: Binding(
                get: { model.camera.showWireframe },
                set: { _ in model.toggleWireframe() }
            )) {
                Image(systemName: "cube.transparent")
            }
            .help(model.camera.showWireframe ? "Wireframe Active (Click to switch to Solid)" : "Solid Active (Click to switch to Wireframe)")
            
            Toggle(isOn: Binding(
                get: { model.camera.showGrid },
                set: { _ in model.toggleGrid() }
            )) {
                Image(systemName: "grid")
            }
            .help(model.camera.showGrid ? "Ground Grid Visible (Click to hide)" : "Ground Grid Hidden (Click to show)")
            
            Picker("Projection", selection: Binding(
                get: { model.camera.isOrthographic },
                set: { newValue in
                    model.camera.isOrthographic = newValue
                    model.objectWillChange.send()
                }
            )) {
                Image(systemName: "cube").tag(false)
                Image(systemName: "square").tag(true)
            }
            .pickerStyle(.segmented)
            .help("Perspective vs. Orthographic View")
        }
    }
    
    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        _ = provider.loadObject(ofClass: URL.self) { url, _ in
            if let url = url {
                DispatchQueue.main.async {
                    self.model.loadFile(from: url)
                }
            }
        }
        return true
    }
}

@MainActor
private struct NotificationHandlersModifier: ViewModifier {
    @ObservedObject var model: AppModel
    
    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .scadTriggerCompile)) { _ in model.compile() }
            .onReceive(NotificationCenter.default.publisher(for: .scadTriggerNew)) { _ in model.newFile() }
            .onReceive(NotificationCenter.default.publisher(for: .scadTriggerOpen)) { _ in model.openFile() }
            .onReceive(NotificationCenter.default.publisher(for: .scadTriggerSave)) { _ in model.saveFile() }
            .onReceive(NotificationCenter.default.publisher(for: .scadTriggerSaveAs)) { _ in model.saveFileAs() }
            .onReceive(NotificationCenter.default.publisher(for: .scadTriggerExportSTL)) { _ in model.exportSTL() }
            .onReceive(NotificationCenter.default.publisher(for: .scadTriggerNewTab)) { _ in model.addNewTab() }
            .onReceive(NotificationCenter.default.publisher(for: .scadTriggerCloseTab)) { _ in model.closeActiveTab() }
            .onReceive(NotificationCenter.default.publisher(for: .scadTriggerNextTab)) { _ in model.selectNextTab() }
            .onReceive(NotificationCenter.default.publisher(for: .scadTriggerPrevTab)) { _ in model.selectPreviousTab() }
    }
}

@MainActor
struct HudOverlayView: View {
    let polygonCount: Int
    let boundsString: String
    let compileTime: Double
    
    var body: some View {
        HStack(spacing: 8) {
            Label("\(polygonCount) polys", systemImage: "square.3.layers.3d")
            Text("•")
            Label(boundsString, systemImage: "ruler")
            Text("•")
            Label(String(format: "%.0f ms", compileTime * 1000), systemImage: "bolt.fill")
        }
        .font(.system(size: 11, weight: .medium, design: .monospaced))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
        .shadow(radius: 2)
    }
}
