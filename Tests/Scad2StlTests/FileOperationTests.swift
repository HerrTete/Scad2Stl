import XCTest
import SwiftUI
@testable import Scad2Stl

@MainActor
final class FileOperationTests: XCTestCase {
    
    func testFileLoadingAndSaving() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let scadFile = tempDir.appendingPathComponent("test_model_\(UUID().uuidString).scad")
        let initialCode = "cube([15, 25, 35], center = true);"
        try initialCode.write(to: scadFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: scadFile) }
        
        let model = AppModel()
        
        // Test loading
        model.loadFile(from: scadFile)
        XCTAssertEqual(model.sourceCode, initialCode)
        XCTAssertEqual(model.currentFileURL, scadFile)
        XCTAssertEqual(model.documentTitle, scadFile.lastPathComponent)
        XCTAssertFalse(model.isDocumentEdited)
        XCTAssertEqual(model.defaultSTLName, scadFile.deletingPathExtension().appendingPathExtension("stl").lastPathComponent)
        
        // Modify code
        let modifiedCode = "sphere(r = 12, $fn = 20);"
        model.sourceCode = modifiedCode
        XCTAssertTrue(model.isDocumentEdited)
        
        // Save code
        model.saveFile()
        XCTAssertFalse(model.isDocumentEdited)
        
        let savedContent = try String(contentsOf: scadFile, encoding: .utf8)
        XCTAssertEqual(savedContent, modifiedCode)
        
        // New file
        model.newFile()
        XCTAssertNil(model.currentFileURL)
        XCTAssertEqual(model.documentTitle, "Untitled.scad")
        XCTAssertFalse(model.isDocumentEdited)
        XCTAssertEqual(model.defaultSTLName, "Model.stl")
    }
    
    func testDefaultSTLNameSanitization() {
        let model = AppModel()
        model.documentTitle = "Basketball Piggy Bank (Sparbüchse).scad"
        model.currentFileURL = nil
        XCTAssertEqual(model.defaultSTLName, "Basketball_Piggy_Bank_Sparbüchse.stl")
    }
    
    func testMultipleProjectTabs() {
        let model = AppModel()
        XCTAssertEqual(model.tabs.count, 1)
        let firstTab = model.activeTab
        let firstTabInitialCode = model.sourceCode
        
        // Add second tab
        let secondTab = model.addNewTab(title: "Project2.scad", sourceCode: "cylinder(h=10, r=5);")
        XCTAssertEqual(model.tabs.count, 2)
        XCTAssertEqual(model.activeTabId, secondTab.id)
        XCTAssertEqual(model.sourceCode, "cylinder(h=10, r=5);")
        XCTAssertEqual(firstTab.sourceCode, firstTabInitialCode)
        
        // Cycle tabs
        model.selectNextTab()
        XCTAssertEqual(model.activeTabId, firstTab.id)
        
        model.selectPreviousTab()
        XCTAssertEqual(model.activeTabId, secondTab.id)
        
        // Close second tab
        model.closeActiveTab()
        XCTAssertEqual(model.tabs.count, 1)
        XCTAssertEqual(model.activeTabId, firstTab.id)
    }
    
    func testOpenSampleInNewTab() {
        let model = AppModel()
        let initialTab = model.activeTab
        
        model.openSampleInNewTab(at: 1)
        XCTAssertEqual(model.tabs.count, 2)
        XCTAssertNotEqual(model.activeTabId, initialTab.id)
        XCTAssertEqual(model.activeTab.title, "\(model.samples[1].name).scad")
        XCTAssertEqual(model.sourceCode, model.samples[1].code)
    }
    
    func testCameraControls() {
        let model = AppModel()
        
        // Initial state
        XCTAssertFalse(model.camera.showWireframe)
        XCTAssertTrue(model.camera.showGrid)
        
        // Toggle wireframe
        model.toggleWireframe()
        XCTAssertTrue(model.camera.showWireframe)
        model.toggleWireframe()
        XCTAssertFalse(model.camera.showWireframe)
        
        // Toggle grid
        model.toggleGrid()
        XCTAssertFalse(model.camera.showGrid)
        model.toggleGrid()
        XCTAssertTrue(model.camera.showGrid)
        
        // Reset camera
        model.camera.yaw = 100
        model.resetCamera()
        XCTAssertEqual(model.camera.yaw, -45.0)
        
        // Fit view
        model.fitView()
        XCTAssertTrue(model.camera.distance > 0)
    }
}
