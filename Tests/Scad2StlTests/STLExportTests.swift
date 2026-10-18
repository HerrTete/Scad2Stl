import XCTest
import Euclid
@testable import Scad2Stl

final class STLExportTests: XCTestCase {
    func testBinarySTLExport() {
        let cube = Mesh.cube(size: 10)
        let data = STLExporter.export(mesh: cube, format: .binary, name: "Cube")
        
        // 80 byte header + 4 byte count + 12 triangles * 50 bytes = 84 + 600 = 684 bytes
        XCTAssertGreaterThan(data.count, 84)
        
        // Read triangle count at byte 80
        let triangleCount: UInt32 = data.subdata(in: 80..<84).withUnsafeBytes { ptr in
            ptr.load(as: UInt32.self)
        }
        XCTAssertEqual(triangleCount, 12)
        XCTAssertEqual(data.count, 84 + 12 * 50)
    }
    
    func testASCIIExport() {
        let cube = Mesh.cube(size: 10)
        let data = STLExporter.export(mesh: cube, format: .ascii, name: "TestCube")
        let str = String(data: data, encoding: .utf8)
        
        XCTAssertNotNil(str)
        XCTAssertTrue(str!.hasPrefix("solid TestCube"))
        XCTAssertTrue(str!.hasSuffix("endsolid TestCube"))
        XCTAssertTrue(str!.contains("facet normal"))
        XCTAssertTrue(str!.contains("outer loop"))
        XCTAssertTrue(str!.contains("endfacet"))
    }
}
