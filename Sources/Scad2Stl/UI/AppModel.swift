import SwiftUI
import Euclid
import AppKit
import UniformTypeIdentifiers
import Combine

public struct ConsoleMessage: Identifiable, Equatable, Sendable {
    public let id = UUID()
    public enum MessageType: Sendable {
        case info
        case warning
        case error
        case echo
    }
    public let type: MessageType
    public let text: String
    public let timestamp = Date()
}

// MARK: - Project Tab (Independent Project Document)

@MainActor
public final class ProjectTab: ObservableObject, Identifiable {
    public let id = UUID()
    @Published public var title: String
    @Published public var fileURL: URL?
    @Published public var isEdited: Bool = false
    
    @Published public var sourceCode: String {
        didSet {
            if sourceCode != oldValue {
                isEdited = true
            }
        }
    }
    
    @Published public var currentMesh: Mesh = Mesh.cube(size: 20)
    @Published public var camera = Camera() {
        didSet {
            observeCamera()
        }
    }
    @Published public var isCompiling: Bool = false
    @Published public var compileTime: Double = 0
    @Published public var consoleMessages: [ConsoleMessage] = []
    @Published public var polygonCount: Int = 6
    @Published public var boundsString: String = "20 x 20 x 20 mm"
    
    private var compileTask: Task<Void, Never>?
    private var cameraCancellable: AnyCancellable?
    
    public init(
        title: String = "Untitled.scad",
        fileURL: URL? = nil,
        sourceCode: String = AppModel.defaultScript,
        autoCompile: Bool = true
    ) {
        self.title = title
        self.fileURL = fileURL
        self.sourceCode = sourceCode
        self.isEdited = false
        observeCamera()
        if autoCompile {
            compile()
        }
    }
    
    private func observeCamera() {
        cameraCancellable = camera.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
    }
    
    public func fitView() {
        camera.fit(bounds: currentMesh.bounds)
        objectWillChange.send()
    }
    
    public func resetCamera() {
        camera.reset()
        objectWillChange.send()
    }
    
    public func toggleWireframe() {
        camera.showWireframe.toggle()
        objectWillChange.send()
    }
    
    public func toggleGrid() {
        camera.showGrid.toggle()
        objectWillChange.send()
    }
    
    public var defaultSTLName: String {
        if let url = fileURL {
            return url.deletingPathExtension().appendingPathExtension("stl").lastPathComponent
        }
        let base = (title as NSString).deletingPathExtension
        if base == "Untitled" || base.isEmpty {
            return "Model.stl"
        }
        let clean = base.replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "(", with: "")
            .replacingOccurrences(of: ")", with: "")
        let name = clean.isEmpty ? "Model" : clean
        return name + ".stl"
    }
    
    public func compile() {
        compileTask?.cancel()
        isCompiling = true
        let script = sourceCode
        
        let parser = Parser(source: script)
        let program = parser.parse()
        
        if !parser.errors.isEmpty {
            for err in parser.errors {
                consoleMessages.append(ConsoleMessage(type: .error, text: "\(err)"))
            }
            isCompiling = false
            return
        }
        
        compileTask = Task.detached(priority: .userInitiated) {
            let evaluator = Evaluator()
            let startTime = Date()
            let mesh = evaluator.evaluate(program: program)
            let elapsed = Date().timeIntervalSince(startTime)
            
            await MainActor.run {
                self.compileTime = elapsed
                for out in evaluator.consoleOutput {
                    self.consoleMessages.append(ConsoleMessage(type: .echo, text: out))
                }
                for err in evaluator.errors {
                    self.consoleMessages.append(ConsoleMessage(type: .error, text: "\(err)"))
                }
                
                self.currentMesh = mesh
                self.polygonCount = mesh.polygons.count
                
                let size = mesh.bounds.max - mesh.bounds.min
                self.boundsString = String(format: "%.1f × %.1f × %.1f mm", size.x, size.y, size.z)
                self.isCompiling = false
            }
        }
    }
}

// MARK: - AppModel (Workspace & Multi-Project Manager)

@MainActor
public final class AppModel: ObservableObject {
    @Published public var tabs: [ProjectTab] = []
    @Published public var activeTabId: UUID = UUID()
    
    private var cancellables = Set<AnyCancellable>()
    
    public var activeTab: ProjectTab {
        if let tab = tabs.first(where: { $0.id == activeTabId }) {
            return tab
        }
        if let first = tabs.first {
            activeTabId = first.id
            return first
        }
        let newTab = ProjectTab()
        observeTab(newTab)
        tabs.append(newTab)
        activeTabId = newTab.id
        return newTab
    }
    
    // Transparent forwarders for existing single-tab callers & tests
    public var sourceCode: String {
        get { activeTab.sourceCode }
        set { activeTab.sourceCode = newValue }
    }
    public var currentMesh: Mesh {
        get { activeTab.currentMesh }
        set { activeTab.currentMesh = newValue }
    }
    public var camera: Camera {
        get { activeTab.camera }
        set { activeTab.camera = newValue }
    }
    public var documentTitle: String {
        get { activeTab.title }
        set { activeTab.title = newValue }
    }
    public var currentFileURL: URL? {
        get { activeTab.fileURL }
        set { activeTab.fileURL = newValue }
    }
    public var isDocumentEdited: Bool {
        get { activeTab.isEdited }
        set { activeTab.isEdited = newValue }
    }
    public var consoleMessages: [ConsoleMessage] {
        get { activeTab.consoleMessages }
        set { activeTab.consoleMessages = newValue }
    }
    public var polygonCount: Int { activeTab.polygonCount }
    public var boundsString: String { activeTab.boundsString }
    public var compileTime: Double { activeTab.compileTime }
    public var isCompiling: Bool { activeTab.isCompiling }
    public var defaultSTLName: String { activeTab.defaultSTLName }
    
    public init() {
        let initialTab = ProjectTab()
        self.tabs = [initialTab]
        self.activeTabId = initialTab.id
        observeTab(initialTab)
    }
    
    private func observeTab(_ tab: ProjectTab) {
        tab.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Tab Management
    
    @discardableResult
    public func addNewTab(
        title: String = "Untitled.scad",
        sourceCode: String = AppModel.defaultScript,
        fileURL: URL? = nil
    ) -> ProjectTab {
        let newTab = ProjectTab(title: title, fileURL: fileURL, sourceCode: sourceCode)
        observeTab(newTab)
        tabs.append(newTab)
        activeTabId = newTab.id
        return newTab
    }
    
    public func closeTab(id: UUID) {
        guard let idx = tabs.firstIndex(where: { $0.id == id }) else { return }
        if tabs.count > 1 {
            if activeTabId == id {
                let nextIdx = (idx == tabs.count - 1) ? idx - 1 : idx + 1
                activeTabId = tabs[nextIdx].id
            }
            tabs.remove(at: idx)
        } else {
            let freshTab = ProjectTab()
            observeTab(freshTab)
            tabs = [freshTab]
            activeTabId = freshTab.id
        }
    }
    
    public func closeActiveTab() {
        closeTab(id: activeTabId)
    }
    
    public func selectNextTab() {
        guard let idx = tabs.firstIndex(where: { $0.id == activeTabId }), !tabs.isEmpty else { return }
        let nextIdx = (idx + 1) % tabs.count
        activeTabId = tabs[nextIdx].id
    }
    
    public func selectPreviousTab() {
        guard let idx = tabs.firstIndex(where: { $0.id == activeTabId }), !tabs.isEmpty else { return }
        let prevIdx = (idx - 1 + tabs.count) % tabs.count
        activeTabId = tabs[prevIdx].id
    }
    
    public func compile() {
        activeTab.compile()
    }
    
    // MARK: - Camera Controls
    
    public func fitView() {
        activeTab.fitView()
        objectWillChange.send()
    }
    
    public func resetCamera() {
        activeTab.resetCamera()
        objectWillChange.send()
    }
    
    public func toggleWireframe() {
        activeTab.toggleWireframe()
        objectWillChange.send()
    }
    
    public func toggleGrid() {
        activeTab.toggleGrid()
        objectWillChange.send()
    }
    
    // MARK: - Document & File Operations
    
    public func newFile() {
        addNewTab()
    }
    
    public func openFile() {
        let openPanel = NSOpenPanel()
        openPanel.title = "Open OpenSCAD Script"
        openPanel.prompt = "Open"
        openPanel.canChooseFiles = true
        openPanel.canChooseDirectories = false
        openPanel.allowsMultipleSelection = false
        openPanel.allowsOtherFileTypes = true
        
        var types: [UTType] = []
        if let scadType = UTType(filenameExtension: "scad") {
            types.append(scadType)
        }
        types.append(contentsOf: [.plainText, .sourceCode, .item])
        openPanel.allowedContentTypes = types
        
        if let currentURL = currentFileURL {
            openPanel.directoryURL = currentURL.deletingLastPathComponent()
        }
        
        NSApp.activate(ignoringOtherApps: true)
        
        openPanel.begin { [weak self] response in
            guard let self = self, response == .OK, let url = openPanel.url else { return }
            self.loadFile(from: url)
        }
    }
    
    public func loadFile(from url: URL) {
        do {
            let content = try String(contentsOf: url, encoding: .utf8)
            // If current tab is an unedited Untitled document, reuse it; otherwise open in new tab
            if activeTab.fileURL == nil && !activeTab.isEdited && activeTab.title == "Untitled.scad" {
                activeTab.sourceCode = content
                activeTab.fileURL = url
                activeTab.title = url.lastPathComponent
                activeTab.isEdited = false
                activeTab.consoleMessages.append(ConsoleMessage(type: .info, text: "Loaded \(url.lastPathComponent)"))
                activeTab.compile()
                activeTab.camera.fit(bounds: activeTab.currentMesh.bounds)
            } else {
                let newTab = addNewTab(title: url.lastPathComponent, sourceCode: content, fileURL: url)
                newTab.isEdited = false
                newTab.consoleMessages.append(ConsoleMessage(type: .info, text: "Loaded \(url.lastPathComponent)"))
                newTab.camera.fit(bounds: newTab.currentMesh.bounds)
            }
        } catch {
            activeTab.consoleMessages.append(ConsoleMessage(type: .error, text: "Failed to open \(url.lastPathComponent): \(error.localizedDescription)"))
        }
    }
    
    public func saveFile() {
        if let currentURL = activeTab.fileURL {
            do {
                try activeTab.sourceCode.write(to: currentURL, atomically: true, encoding: .utf8)
                activeTab.isEdited = false
                activeTab.consoleMessages.append(ConsoleMessage(type: .info, text: "Saved \(currentURL.lastPathComponent)"))
            } catch {
                activeTab.consoleMessages.append(ConsoleMessage(type: .error, text: "Save failed: \(error.localizedDescription)"))
            }
        } else {
            saveFileAs()
        }
    }
    
    public func saveFileAs() {
        let savePanel = NSSavePanel()
        savePanel.title = "Save OpenSCAD Script"
        savePanel.prompt = "Save"
        savePanel.canCreateDirectories = true
        
        var types: [UTType] = []
        if let scadType = UTType(filenameExtension: "scad") {
            types.append(scadType)
        }
        types.append(.plainText)
        savePanel.allowedContentTypes = types
        
        if let currentURL = activeTab.fileURL {
            savePanel.directoryURL = currentURL.deletingLastPathComponent()
            savePanel.nameFieldStringValue = currentURL.lastPathComponent
        } else {
            let defaultName = activeTab.title.hasSuffix(".scad") ? activeTab.title : "\(activeTab.title).scad"
            savePanel.nameFieldStringValue = defaultName
        }
        
        NSApp.activate(ignoringOtherApps: true)
        
        savePanel.begin { [weak self] response in
            guard let self = self, response == .OK, let url = savePanel.url else { return }
            do {
                try self.activeTab.sourceCode.write(to: url, atomically: true, encoding: .utf8)
                self.activeTab.fileURL = url
                self.activeTab.title = url.lastPathComponent
                self.activeTab.isEdited = false
                self.activeTab.consoleMessages.append(ConsoleMessage(type: .info, text: "Saved as \(url.lastPathComponent)"))
            } catch {
                self.activeTab.consoleMessages.append(ConsoleMessage(type: .error, text: "Save failed: \(error.localizedDescription)"))
            }
        }
    }
    
    public func exportSTL() {
        let savePanel = NSSavePanel()
        var types: [UTType] = []
        if let stlType = UTType(filenameExtension: "stl") {
            types.append(stlType)
        }
        types.append(.data)
        savePanel.allowedContentTypes = types
        
        savePanel.nameFieldStringValue = defaultSTLName
        savePanel.title = "Export Model as Binary STL"
        savePanel.prompt = "Export"
        savePanel.canCreateDirectories = true
        
        if let currentURL = activeTab.fileURL {
            savePanel.directoryURL = currentURL.deletingLastPathComponent()
        }
        
        NSApp.activate(ignoringOtherApps: true)
        
        savePanel.begin { [weak self] response in
            guard let self = self, response == .OK, let url = savePanel.url else { return }
            do {
                let modelName = url.deletingPathExtension().lastPathComponent
                try STLExporter.exportToFile(mesh: self.activeTab.currentMesh, at: url, format: .binary, name: modelName)
                self.activeTab.consoleMessages.append(ConsoleMessage(type: .info, text: "Successfully exported STL to \(url.path)"))
            } catch {
                self.activeTab.consoleMessages.append(ConsoleMessage(type: .error, text: "Export failed: \(error.localizedDescription)"))
            }
        }
    }
    
    public func openSampleInNewTab(at index: Int) {
        guard index >= 0 && index < samples.count else { return }
        let sample = samples[index]
        let tab = addNewTab(title: "\(sample.name).scad", sourceCode: sample.code)
        tab.isEdited = false
        tab.consoleMessages.append(ConsoleMessage(type: .info, text: "Opened sample '\(sample.name)' in new tab"))
    }
    
    public func loadSample(at index: Int) {
        openSampleInNewTab(at: index)
    }
    
    public struct SampleModel {
        public let name: String
        public let code: String
    }
    
    public let samples: [SampleModel] = [
        SampleModel(
            name: "CSG Tree & Sphere Difference",
            code: defaultScript
        ),
        SampleModel(
            name: "Perforated Cube",
            code: """
            // Perforated Hollow Cube
            difference() {
                cube(30, center = true);
                sphere(r = 18, $fn = 32);
                cylinder(h = 35, r = 8, center = true, $fn = 24);
                rotate([90, 0, 0])
                    cylinder(h = 35, r = 8, center = true, $fn = 24);
                rotate([0, 90, 0])
                    cylinder(h = 35, r = 8, center = true, $fn = 24);
            }
            """
        ),
        SampleModel(
            name: "Parametric Wheel / Gear",
            code: """
            // Parametric Spoke Wheel
            $fn = 32;
            hub_r = 6;
            rim_r = 25;
            spokes = 6;
            
            difference() {
                union() {
                    // Central hub
                    cylinder(h = 10, r = hub_r, center = true);
                    // Outer rim
                    difference() {
                        cylinder(h = 8, r = rim_r, center = true);
                        cylinder(h = 9, r = rim_r - 3, center = true);
                    }
                    // Spokes
                    for (i = [0 : spokes - 1]) {
                        rotate([0, 0, i * (360 / spokes)])
                            translate([0, 0, 0])
                                cube([rim_r * 2, 2.5, 6], center = true);
                    }
                }
                // Center axle hole
                cylinder(h = 12, r = 2.5, center = true);
            }
            """
        ),
        SampleModel(
            name: "Linear Extrusion with Twist",
            code: """
            // Twisted Star Pillar
            linear_extrude(height = 40, twist = 90, slices = 30) {
                union() {
                    square([16, 16], center = true);
                    rotate(45)
                        square([16, 16], center = true);
                }
            }
            """
        ),
        SampleModel(
            name: "Basketball Piggy Bank",
            code: """
            // =========================================================================
            // BASKETBALL SPARBÜCHSE (Durchmesser: 23 cm / 230 mm)
            // GEOMETRISCH KORRIGIERT: Voller Ball mit passgenauem Boden
            // =========================================================================

            // --- QUALITÄTS-EINSTELLUNGEN ---
            $fn = 80; // Für den finalen Export (F6) bitte auf 120 erhöhen!

            // --- HAUPTMASSE (23 cm Durchmesser) ---
            durchmesser = 230;
            radius = durchmesser / 2; // 115 mm
            wanddicke = 4.5;          // Wandstärke der Kugel

            // --- DETAILS DER BASKETBALL-NÄHTE ---
            naht_breite = 3.5;        
            naht_tiefe = 1.6;         

            // --- GELDSCHLITZ (Oben in der Mitte) ---
            schlitz_laenge = 40;      
            schlitz_breite = 4;

            // --- UNTERSEITE & SCHRAUBDECKEL ---
            abflachung = 15;          // Kugel wird unten um exakt 15 mm abgeschnitten
            z_boden = -radius + abflachung; // Höhe der flachen Standfläche liegt bei -100 mm

            deckel_radius = 35;       // Der Deckel hat 70 mm Durchmesser
            gewinde_hoehe = 12;       // Höhe des Gewindes
            gewinde_pitch = 4;        // Gewindesteigung
            gewinde_toleranz = 0.5;   // Spaltmaß für leichtgängiges Schrauben


            // =========================================================================
            // 0. HILFS-WERKZEUG (Gegen Mathe-Fehler)
            // =========================================================================
            // Schneidet garantiert alles weg, was sich unter der Höhe 'z' befindet
            module cut_below(z) {
                translate([0, 0, z - 500])
                    cube([1000, 1000, 1000], center = true);
            }


            // =========================================================================
            // 1. MATHEMATISCH EXAKTE BASKETBALL-KURVE
            // =========================================================================
            function naht_punkt(t, r) = 
                let(
                    a = 23, 
                    w = (90 - a) * cos(t),
                    theta = t/2 + a * sin(2*t),
                    x_orig = r * cos(w) * cos(theta),
                    y_orig = r * cos(w) * sin(theta),
                    z_orig = r * sin(w)
                )
                [ x_orig, z_orig, -y_orig ];

            module basketball_naehte() {
                r_spur = radius + (naht_breite / 2) - naht_tiefe;
                
                // 1. HORIZONTALER GROSSKREIS 
                rotate_extrude()
                    translate([r_spur, 0, 0]) circle(d = naht_breite, $fn = 20);
                        
                // 2. VERTIKALER GROSSKREIS 
                rotate([0, 90, 0])
                    rotate_extrude() translate([r_spur, 0, 0]) circle(d = naht_breite, $fn = 20);
                            
                // 3. DIE ENDLOSE 3D-SCHLEIFE
                schritte = 240; 
                dt = 720 / schritte; 
                
                for(i = [0 : schritte - 1]) {
                    hull() {
                        translate(naht_punkt(i * dt, r_spur)) sphere(d = naht_breite, $fn = 12);
                        translate(naht_punkt((i + 1) * dt, r_spur)) sphere(d = naht_breite, $fn = 12);
                    }
                }
            }


            // =========================================================================
            // 2. GEWINDE-MODUL FÜR DEN SCHRAUBDECKEL
            // =========================================================================
            module gewinde_helix(r, h, pitch, d) {
                twist_angle = -360 * (h / pitch);
                for (start_winkel = [0, 180]) {
                    rotate([0, 0, start_winkel])
                        linear_extrude(height = h, twist = twist_angle, slices = h * 15)
                            translate([r, 0, 0])
                                circle(d = d, $fn = 20);
                }
            }


            // =========================================================================
            // 3. HAUPTKÖRPER DER SPARBÜCHSE 
            // =========================================================================
            module sparbuechse() {
                difference() {
                    
                    // --- GRUNDFORM (Kugel + massiver Fußboden + Gewinde-Ring) ---
                    union() {
                        // Die hohle Kugel mit exakt flachem Boden (4,5 mm dick)
                        difference() {
                            // Außenhülle
                            difference() {
                                sphere(r = radius);
                                cut_below(z_boden); // Schneidet exakt die letzten 15 mm ab!
                            }
                            // Innenraum (wird etwas höher abgeschnitten, damit der Boden stehen bleibt)
                            difference() {
                                sphere(r = radius - wanddicke);
                                cut_below(z_boden + wanddicke); 
                            }
                        }
                        
                        // Ein dicker Ring auf dem Boden, um dem Gewinde Futter zu geben
                        translate([0, 0, z_boden])
                            cylinder(h = gewinde_hoehe + 3, r = deckel_radius + 6);
                    }
                    
                    // --- AUSSPARUNGEN UND LÖCHER ---
                    
                    // 1. Vertiefung für die Basisplatte des Deckels (0.5 mm Spaltmaß für Passgenauigkeit)
                    translate([0, 0, z_boden - 0.1])
                        cylinder(h = 3.2, r = deckel_radius + 5.5);
                        
                    // 2. Das glatte Kernloch für den Deckel 
                    translate([0, 0, z_boden - 0.1])
                        cylinder(h = gewinde_hoehe + 5, r = deckel_radius);
                        
                    // 3. Innengewinde-Rillen fräsen
                    translate([0, 0, z_boden + 3])
                        gewinde_helix(deckel_radius, gewinde_hoehe, gewinde_pitch, 3.2);
                        
                    // 4. Geldschlitz oben am Pol
                    translate([0, 0, radius - wanddicke - 2])
                        cube([schlitz_breite, schlitz_laenge, 20], center = true);
                        
                    // 5. Basketball-Nähte abziehen
                    basketball_naehte();
                }
            }


            // =========================================================================
            // 4. SCHRAUBDECKEL
            // =========================================================================
            module deckel() {
                r_gewinde = deckel_radius - gewinde_toleranz; 
                
                difference() {
                    union() {
                        // Basisplatte des Deckels (Schließt perfekt bündig ab)
                        cylinder(h = 3, r = deckel_radius + 5.0);
                        
                        // Kernzylinder für das Außengewinde
                        translate([0, 0, 3])
                            cylinder(h = gewinde_hoehe - 3, r = r_gewinde);
                            
                        // Außengewinde
                        translate([0, 0, 3])
                            intersection() {
                                gewinde_helix(r_gewinde, gewinde_hoehe - 3, gewinde_pitch, 2.8);
                                // Fase oben für extrem leichtes Ansetzen des Gewindes
                                cylinder(h = gewinde_hoehe - 3, r1 = r_gewinde + 2, r2 = r_gewinde - 1);
                            }
                    }
                    
                    // Münz-Schlitz zum Aufdrehen (2.5 mm tief in der Basisplatte)
                    translate([-deckel_radius*0.75, -2.5, 0])
                        cube([deckel_radius * 1.5, 5, 2.5]);
                        
                    // Deckel innen aushöhlen, spart Material und Druckzeit
                    translate([0, 0, 6])
                        cylinder(h = gewinde_hoehe, r = r_gewinde - 4);
                }
            }


            // =========================================================================
            // 5. ANSICHT & EXPORT
            // =========================================================================

            // Zeigt die Hauptkugel (jetzt ist es wieder eine Kugel!)
            sparbuechse();

            // Zeigt den Deckel (zum Betrachten leicht nach unten geschoben)
            translate([0, 0, z_boden - 25]) 
                deckel();
            """
        )
    ]
    
    nonisolated public static let defaultScript = """
// Welcome to Scad2Stl!
// Native macOS Apple Silicon OpenSCAD
$fn = 32;

module tree(trunk_h = 30, crown_r = 16) {
    union() {
        color("brown")
            cylinder(h = trunk_h, r = trunk_h / 6, center = false);
        translate([0, 0, trunk_h])
            color("green")
                sphere(r = crown_r);
    }
}

difference() {
    tree(35, 18);
    // Subtract cutting box
    translate([0, 0, 20])
        cube([50, 50, 10], center = true);
}
"""
}

public extension Notification.Name {
    static let scadTriggerCompile = Notification.Name("scadTriggerCompile")
    static let scadTriggerNew = Notification.Name("scadTriggerNew")
    static let scadTriggerOpen = Notification.Name("scadTriggerOpen")
    static let scadTriggerSave = Notification.Name("scadTriggerSave")
    static let scadTriggerSaveAs = Notification.Name("scadTriggerSaveAs")
    static let scadTriggerExportSTL = Notification.Name("scadTriggerExportSTL")
    static let scadTriggerNewTab = Notification.Name("scadTriggerNewTab")
    static let scadTriggerCloseTab = Notification.Name("scadTriggerCloseTab")
    static let scadTriggerNextTab = Notification.Name("scadTriggerNextTab")
    static let scadTriggerPrevTab = Notification.Name("scadTriggerPrevTab")
}


