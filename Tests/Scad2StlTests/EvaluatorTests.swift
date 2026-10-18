import XCTest
import SwiftUI
import Euclid
@testable import Scad2Stl

final class EvaluatorTests: XCTestCase {
    func testCubeEvaluation() {
        let script = "cube([10, 20, 30], center = true);"
        let parser = Parser(source: script)
        let prog = parser.parse()
        let evaluator = Evaluator()
        let mesh = evaluator.evaluate(program: prog)
        
        XCTAssertEqual(evaluator.errors.count, 0)
        XCTAssertFalse(mesh.polygons.isEmpty)
        XCTAssertEqual(mesh.bounds.min, Euclid.Vector(-5, -10, -15))
        XCTAssertEqual(mesh.bounds.max, Euclid.Vector(5, 10, 15))
    }
    
    func testDifferenceEvaluation() {
        let script = """
        difference() {
            cube(20, center = true);
            sphere(r = 12, $fn = 16);
        }
        """
        let parser = Parser(source: script)
        let prog = parser.parse()
        let evaluator = Evaluator()
        let mesh = evaluator.evaluate(program: prog)
        
        XCTAssertEqual(evaluator.errors.count, 0)
        XCTAssertFalse(mesh.polygons.isEmpty)
    }
    
    func testForLoopUnion() {
        let script = """
        for (i = [0 : 2]) {
            translate([i * 10, 0, 0])
                cube(5, center = false);
        }
        """
        let parser = Parser(source: script)
        let prog = parser.parse()
        let evaluator = Evaluator()
        let mesh = evaluator.evaluate(program: prog)
        
        XCTAssertEqual(evaluator.errors.count, 0)
        XCTAssertFalse(mesh.polygons.isEmpty)
        XCTAssertEqual(mesh.bounds.min.x, 0)
        XCTAssertEqual(mesh.bounds.max.x, 25)
    }
    
    func testLinearExtrude() {
        let script = """
        linear_extrude(height = 15)
            square([10, 10], center = true);
        """
        let parser = Parser(source: script)
        let prog = parser.parse()
        let evaluator = Evaluator()
        let mesh = evaluator.evaluate(program: prog)
        
        XCTAssertEqual(evaluator.errors.count, 0)
        XCTAssertFalse(mesh.polygons.isEmpty)
        XCTAssertEqual(mesh.bounds.max.z - mesh.bounds.min.z, 15)
    }
    
    func testMathFunctions() {
        let script = """
        s = sin(90);
        c = cos(0);
        l = len([1, 2, 3, 4]);
        sq = sqrt(16);
        echo(s = s, c = c, l = l, sq = sq);
        """
        let parser = Parser(source: script)
        let prog = parser.parse()
        let evaluator = Evaluator()
        _ = evaluator.evaluate(program: prog)
        
        XCTAssertEqual(evaluator.errors.count, 0)
        XCTAssertFalse(evaluator.consoleOutput.isEmpty)
        XCTAssertTrue(evaluator.consoleOutput[0].contains("s = 1"))
        XCTAssertTrue(evaluator.consoleOutput[0].contains("c = 1"))
        XCTAssertTrue(evaluator.consoleOutput[0].contains("l = 4"))
        XCTAssertTrue(evaluator.consoleOutput[0].contains("sq = 4"))
    }
    
    func testHullEvaluation() {
        let script = """
        hull() {
            translate([0, 0, 0]) sphere(r = 5, $fn = 12);
            translate([20, 0, 0]) sphere(r = 5, $fn = 12);
        }
        """
        let parser = Parser(source: script)
        let prog = parser.parse()
        let evaluator = Evaluator()
        let mesh = evaluator.evaluate(program: prog)
        
        XCTAssertEqual(evaluator.errors.count, 0)
        XCTAssertFalse(mesh.polygons.isEmpty)
        // Bounds should encompass both spheres [-5, 25] along X
        XCTAssertEqual(mesh.bounds.min.x, -5, accuracy: 0.5)
        XCTAssertEqual(mesh.bounds.max.x, 25, accuracy: 0.5)
    }
    
    func testRotateExtrude() {
        let script = """
        rotate_extrude($fn = 20)
            translate([10, 0, 0])
                circle(r = 2, $fn = 12);
        """
        let parser = Parser(source: script)
        let prog = parser.parse()
        let evaluator = Evaluator()
        let mesh = evaluator.evaluate(program: prog)
        
        XCTAssertEqual(evaluator.errors.count, 0)
        XCTAssertFalse(mesh.polygons.isEmpty)
        // Torus centered around Z axis: radius 10 +/- 2 = [8, 12] in XY, [-2, 2] in Z
        XCTAssertEqual(mesh.bounds.max.x, 12, accuracy: 0.5)
        XCTAssertEqual(mesh.bounds.min.x, -12, accuracy: 0.5)
        XCTAssertEqual(mesh.bounds.max.z, 2, accuracy: 0.5)
        XCTAssertEqual(mesh.bounds.min.z, -2, accuracy: 0.5)
    }
    
    func testNahtPunktMath() {
        let script = """
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
            
        p = naht_punkt(0, 100);
        echo(px = p[0], py = p[1], pz = p[2]);
        """
        let parser = Parser(source: script)
        let prog = parser.parse()
        let evaluator = Evaluator()
        _ = evaluator.evaluate(program: prog)
        
        XCTAssertEqual(evaluator.errors.count, 0)
        XCTAssertFalse(evaluator.consoleOutput.isEmpty)
        XCTAssertTrue(evaluator.consoleOutput[0].contains("px"))
    }
    
    func testBasketballDeckel() {
        let script = """
        $fn = 24;
        deckel_radius = 35;
        gewinde_hoehe = 12;
        gewinde_pitch = 4;
        gewinde_toleranz = 0.5;

        module gewinde_helix(r, h, pitch, d) {
            twist_angle = -360 * (h / pitch);
            for (start_winkel = [0, 180]) {
                rotate([0, 0, start_winkel])
                    linear_extrude(height = h, twist = twist_angle, slices = h * 4)
                        translate([r, 0, 0])
                            circle(d = d, $fn = 12);
            }
        }

        module deckel() {
            r_gewinde = deckel_radius - gewinde_toleranz; 
            difference() {
                union() {
                    cylinder(h = 3, r = deckel_radius + 5.0);
                    translate([0, 0, 3])
                        cylinder(h = gewinde_hoehe - 3, r = r_gewinde);
                    translate([0, 0, 3])
                        intersection() {
                            gewinde_helix(r_gewinde, gewinde_hoehe - 3, gewinde_pitch, 2.8);
                            cylinder(h = gewinde_hoehe - 3, r1 = r_gewinde + 2, r2 = r_gewinde - 1);
                        }
                }
                translate([-deckel_radius*0.75, -2.5, 0])
                    cube([deckel_radius * 1.5, 5, 2.5]);
                translate([0, 0, 6])
                    cylinder(h = gewinde_hoehe, r = r_gewinde - 4);
            }
        }

        deckel();
        """
        let parser = Parser(source: script)
        let prog = parser.parse()
        let evaluator = Evaluator()
        let mesh = evaluator.evaluate(program: prog)
        XCTAssertEqual(evaluator.errors.count, 0)
        XCTAssertFalse(mesh.polygons.isEmpty)
        let smoothed = mesh.smoothingNormals(forAnglesGreaterThan: .degrees(45))
        XCTAssertEqual(smoothed.polygons.count, mesh.polygons.count)
    }
    
    func testBasketballNaehte() {
        let script = """
        radius = 115;
        naht_breite = 3.5;
        naht_tiefe = 1.6;
        r_spur = radius + (naht_breite / 2) - naht_tiefe;
        
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

        schritte = 24; 
        dt = 720 / schritte; 
        
        for(i = [0 : schritte - 1]) {
            hull() {
                translate(naht_punkt(i * dt, r_spur)) sphere(d = naht_breite, $fn = 8);
                translate(naht_punkt((i + 1) * dt, r_spur)) sphere(d = naht_breite, $fn = 8);
            }
        }
        """
        let parser = Parser(source: script)
        let prog = parser.parse()
        let evaluator = Evaluator()
        let mesh = evaluator.evaluate(program: prog)
        
        XCTAssertEqual(evaluator.errors.count, 0)
        XCTAssertFalse(mesh.polygons.isEmpty)
    }
    
    @MainActor
    func testEditorRendering() {
        var text = "cube([10, 20, 30]);"
        let binding = Binding<String>(get: { text }, set: { text = $0 })
        let editor = ScadCodeEditorView(text: binding)
        let coordinator = editor.makeCoordinator()
        
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        scrollView.backgroundColor = NSColor(red: 0.14, green: 0.15, blue: 0.17, alpha: 1.0)
        
        let textView = NSTextView(usingTextLayoutManager: false)
        scrollView.documentView = textView
        
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = NSSize(width: 0.0, height: 0.0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainerInset = NSSize(width: 6, height: 8)
        textView.textContainer?.lineFragmentPadding = 4
        
        let font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        let textColor = NSColor(red: 0.88, green: 0.89, blue: 0.92, alpha: 1.0)
        textView.font = font
        textView.backgroundColor = NSColor(red: 0.14, green: 0.15, blue: 0.17, alpha: 1.0)
        textView.insertionPointColor = NSColor.white
        textView.textColor = textColor
        
        let gutter = LineNumberGutter(textView: textView)
        scrollView.verticalRulerView = gutter
        scrollView.hasVerticalRuler = true
        scrollView.rulersVisible = true
        
        textView.string = text
        if let ts = textView.textStorage {
            coordinator.highlighter.highlight(textStorage: ts)
        }
        
        scrollView.frame = NSRect(x: 0, y: 0, width: 400, height: 500)
        scrollView.layoutSubtreeIfNeeded()
        
        print("DEBUG: sv.frame = \(scrollView.frame)")
        print("DEBUG: sv.contentView.frame = \(scrollView.contentView.frame), bounds = \(scrollView.contentView.bounds)")
        print("DEBUG: tv.frame = \(textView.frame), bounds = \(textView.bounds)")
        print("DEBUG: tv.string = \(textView.string)")
        print("DEBUG: gutter.frame = \(gutter.frame)")
        print("DEBUG: gutter.ruleThickness = \(gutter.ruleThickness)")
        
        // Render to bitmap
        guard let rep = scrollView.bitmapImageRepForCachingDisplay(in: scrollView.bounds) else {
            XCTFail("Failed rep")
            return
        }
        scrollView.cacheDisplay(in: scrollView.bounds, to: rep)
        
        // Count non-background pixels in the text view area (x > 45)
        var textPixelCount = 0
        let bg = NSColor(red: 0.14, green: 0.15, blue: 0.17, alpha: 1.0)
        for y in 0..<Int(scrollView.bounds.height) {
            for x in 45..<Int(scrollView.bounds.width) {
                if let c = rep.colorAt(x: x, y: y) {
                    let diff = abs(c.redComponent - bg.redComponent) + abs(c.greenComponent - bg.greenComponent) + abs(c.blueComponent - bg.blueComponent)
                    if diff > 0.1 {
                        textPixelCount += 1
                    }
                }
            }
        }
        print("DEBUG: textPixelCount (x > 45) = \(textPixelCount)")
        XCTAssertGreaterThan(textPixelCount, 0, "Text pixels should be visible on screen!")
    }
    
    func testBasketballFullModel() throws {
        try XCTSkipIf(ProcessInfo.processInfo.environment["RUN_FULL_BASKETBALL_TEST"] != "1", "Set RUN_FULL_BASKETBALL_TEST=1 to run full 60s basketball test")
        let scadPath = "/Users/herrtete/Documents/3D-Drucker/Basketballsparbüchse/Basketball.scad"
        guard let script = try? String(contentsOfFile: scadPath) else {
            print("Cannot read \(scadPath)")
            return
        }
        
        let parser = Parser(source: script)
        let prog = parser.parse()
        print("Parser errors: \(parser.errors)")
        XCTAssertEqual(parser.errors.count, 0)
        
        let evaluator = Evaluator()
        let mesh = evaluator.evaluate(program: prog)
        print("Evaluator errors: \(evaluator.errors)")
        print("Evaluator console: \(evaluator.consoleOutput)")
        print("Mesh polygons count: \(mesh.polygons.count)")
        print("Mesh bounds: min=\(mesh.bounds.min), max=\(mesh.bounds.max)")
        
        let outURL = URL(fileURLWithPath: "/tmp/Basketball_Scad2Stl_full.stl")
        try STLExporter.exportToFile(mesh: mesh, at: outURL, format: .binary, name: "Basketball_Full")
        print("Exported full STL to \(outURL.path), size: \(try Data(contentsOf: outURL).count) bytes")
    }
    func testTextExtrude() {
        let script = """
        linear_extrude(height = 5) {
            text("Hello", size = 10);
        }
        """
        let parser = Parser(source: script)
        let prog = parser.parse()
        let evaluator = Evaluator()
        let mesh = evaluator.evaluate(program: prog)
        XCTAssertEqual(evaluator.errors.count, 0)
        XCTAssertFalse(mesh.polygons.isEmpty)
        XCTAssertEqual(mesh.bounds.max.z, 5.0, accuracy: 0.01)
    }
    
    func testMultmatrix() {
        let script = """
        multmatrix([
            [1, 0, 0, 10],
            [0, 1, 0, 20],
            [0, 0, 1, 30],
            [0, 0, 0, 1]
        ]) {
            cube([2, 2, 2], center = true);
        }
        """
        let parser = Parser(source: script)
        let prog = parser.parse()
        let evaluator = Evaluator()
        let mesh = evaluator.evaluate(program: prog)
        XCTAssertEqual(evaluator.errors.count, 0)
        XCTAssertFalse(mesh.polygons.isEmpty)
        XCTAssertEqual(mesh.bounds.center.x, 10.0, accuracy: 0.01)
        XCTAssertEqual(mesh.bounds.center.y, 20.0, accuracy: 0.01)
        XCTAssertEqual(mesh.bounds.center.z, 30.0, accuracy: 0.01)
    }
    
    func testResize() {
        let script = """
        resize([30, 40, 50]) {
            cube(10, center = true);
        }
        """
        let parser = Parser(source: script)
        let prog = parser.parse()
        let evaluator = Evaluator()
        let mesh = evaluator.evaluate(program: prog)
        XCTAssertEqual(evaluator.errors.count, 0)
        XCTAssertFalse(mesh.polygons.isEmpty)
        XCTAssertEqual(mesh.bounds.size.x, 30.0, accuracy: 0.01)
        XCTAssertEqual(mesh.bounds.size.y, 40.0, accuracy: 0.01)
        XCTAssertEqual(mesh.bounds.size.z, 50.0, accuracy: 0.01)
    }
    
    func testOffsetAndLinearExtrude() {
        let script = """
        linear_extrude(height = 2) {
            offset(r = 2) {
                circle(r = 5, $fn = 16);
            }
        }
        """
        let parser = Parser(source: script)
        let prog = parser.parse()
        let evaluator = Evaluator()
        let mesh = evaluator.evaluate(program: prog)
        XCTAssertEqual(evaluator.errors.count, 0)
        XCTAssertFalse(mesh.polygons.isEmpty)
        XCTAssertGreaterThan(mesh.bounds.size.x, 10.0)
    }
    
    func testMinkowskiApproximation() {
        let script = """
        minkowski() {
            cube([10, 10, 2], center = true);
            sphere(r = 2, $fn = 12);
        }
        """
        let parser = Parser(source: script)
        let prog = parser.parse()
        let evaluator = Evaluator()
        let mesh = evaluator.evaluate(program: prog)
        XCTAssertEqual(evaluator.errors.count, 0)
        XCTAssertFalse(mesh.polygons.isEmpty)
        XCTAssertGreaterThan(mesh.bounds.size.x, 10.0)
        XCTAssertGreaterThan(mesh.bounds.size.z, 2.0)
    }
    
    func testProjection() {
        let script = """
        projection(cut = false) {
            sphere(r = 10, $fn = 16);
        }
        """
        let parser = Parser(source: script)
        let prog = parser.parse()
        let evaluator = Evaluator()
        let mesh = evaluator.evaluate(program: prog)
        XCTAssertEqual(evaluator.errors.count, 0)
        XCTAssertFalse(mesh.polygons.isEmpty)
    }
    
    func testSearchAndVersionFunctions() {
        let script = """
        v = version();
        vn = version_num();
        echo("version:", v, "num:", vn);
        idx = search("b", ["a", "b", "c"]);
        echo("search_result:", idx);
        """
        let parser = Parser(source: script)
        let prog = parser.parse()
        let evaluator = Evaluator()
        _ = evaluator.evaluate(program: prog)
        XCTAssertEqual(evaluator.errors.count, 0)
        let out = evaluator.consoleOutput.joined(separator: "\n")
        XCTAssertTrue(out.contains("2024"))
        XCTAssertTrue(out.contains("search_result: [1]"))
    }
    
    func testLinearExtrudeScale() {
        let script = """
        linear_extrude(height = 10, scale = 2.0) {
            square([4, 4], center = true);
        }
        """
        let parser = Parser(source: script)
        let prog = parser.parse()
        let evaluator = Evaluator()
        let mesh = evaluator.evaluate(program: prog)
        XCTAssertEqual(evaluator.errors.count, 0)
        XCTAssertFalse(mesh.polygons.isEmpty)
        XCTAssertEqual(mesh.bounds.size.z, 10.0, accuracy: 0.01)
        XCTAssertEqual(mesh.bounds.size.x, 8.0, accuracy: 0.1)
    }
}


