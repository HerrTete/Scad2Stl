import SwiftUI

@MainActor
public struct Scad2StlApp: App {
    @StateObject private var model = AppModel()
    
    public init() {}
    
    public var body: some Scene {
        WindowGroup {
            ContentView(model: model)
                .frame(minWidth: 800, minHeight: 500)
                .onOpenURL { url in
                    model.loadFile(from: url)
                }
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Tab") {
                    model.addNewTab()
                }
                .keyboardShortcut("t", modifiers: [.command])
                
                Button("New Document") {
                    model.newFile()
                }
                .keyboardShortcut("n", modifiers: [.command])
                
                Button("Open...") {
                    model.openFile()
                }
                .keyboardShortcut("o", modifiers: [.command])
                
                Divider()
                
                Button("Close Tab") {
                    model.closeActiveTab()
                }
                .keyboardShortcut("w", modifiers: [.command])
            }
            
            CommandGroup(replacing: .saveItem) {
                Button("Save") {
                    model.saveFile()
                }
                .keyboardShortcut("s", modifiers: [.command])
                
                Button("Save As...") {
                    model.saveFileAs()
                }
                .keyboardShortcut("S", modifiers: [.command, .shift])
            }
            
            CommandGroup(after: .importExport) {
                Button("Export STL...") {
                    model.exportSTL()
                }
                .keyboardShortcut("e", modifiers: [.command])
            }
            
            CommandMenu("Design") {
                Button("Render") {
                    model.compile()
                }
                .keyboardShortcut("r", modifiers: [.command])
                
                Divider()
                
                Button("Fit View to Model") {
                    model.fitView()
                }
                
                Button("Reset Camera") {
                    model.resetCamera()
                }
                
                Button("Toggle Wireframe") {
                    model.toggleWireframe()
                }
                
                Button("Toggle Ground Grid") {
                    model.toggleGrid()
                }
            }
            
            CommandMenu("Samples") {
                ForEach(Array(model.samples.enumerated()), id: \.offset) { index, sample in
                    Button(sample.name) {
                        model.openSampleInNewTab(at: index)
                    }
                }
            }
            
            CommandMenu("Tabs") {
                Button("Next Tab") {
                    model.selectNextTab()
                }
                .keyboardShortcut("}", modifiers: [.command, .shift])
                
                Button("Previous Tab") {
                    model.selectPreviousTab()
                }
                .keyboardShortcut("{", modifiers: [.command, .shift])
            }
        }
    }
}
