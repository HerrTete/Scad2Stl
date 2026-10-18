import XCTest
@testable import Scad2Stl

final class ParserTests: XCTestCase {
    func testPrimitivesParse() {
        let script = """
        cube(10);
        cube([10, 20, 30], center = true);
        sphere(r = 5);
        cylinder(h = 20, r1 = 10, r2 = 5, center = false);
        """
        let parser = Parser(source: script)
        let prog = parser.parse()
        XCTAssertEqual(parser.errors.count, 0)
        XCTAssertEqual(prog.statements.count, 4)
    }
    
    func testTransformationsAndBooleans() {
        let script = """
        translate([10, 0, 0])
        rotate([0, 45, 90])
        scale([2, 1, 1])
        difference() {
            cube(20);
            sphere(12);
        }
        """
        let parser = Parser(source: script)
        let prog = parser.parse()
        XCTAssertEqual(parser.errors.count, 0)
        XCTAssertEqual(prog.statements.count, 1)
        if case .moduleCall(let name, _, let children, _, _) = prog.statements[0] {
            XCTAssertEqual(name, "translate")
            XCTAssertEqual(children.count, 1)
        } else {
            XCTFail("Expected translate module call")
        }
    }
    
    func testControlFlowAndExpressions() {
        let script = """
        a = 10 + 20 * 2;
        b = a > 30 ? "yes" : "no";
        for (i = [0:2:10]) {
            translate([i, 0, 0]) cube(2);
        }
        """
        let parser = Parser(source: script)
        let prog = parser.parse()
        XCTAssertEqual(parser.errors.count, 0)
        XCTAssertEqual(prog.statements.count, 3)
    }
    
    func testFunctionsAndModules() {
        let script = """
        function add(x, y = 5) = x + y;
        module my_box(w, h) {
            cube([w, h, add(w, h)]);
        }
        my_box(10, 20);
        """
        let parser = Parser(source: script)
        let prog = parser.parse()
        XCTAssertEqual(parser.errors.count, 0)
        XCTAssertEqual(prog.statements.count, 3)
    }
}
