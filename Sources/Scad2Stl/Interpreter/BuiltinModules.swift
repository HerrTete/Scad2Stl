import Foundation
import Euclid
import AppKit
import CoreText
import CoreGraphics

private typealias Polygon = Euclid.Polygon

public struct BuiltinModules {
    public static func isBuiltinModule(_ name: String) -> Bool {
        return moduleNames.contains(name)
    }
    
    private static let moduleNames: Set<String> = [
        "cube", "sphere", "cylinder", "polyhedron",
        "square", "circle", "polygon", "text",
        "translate", "rotate", "scale", "mirror", "color",
        "multmatrix", "resize", "offset", "projection",
        "union", "difference", "intersection", "hull", "minkowski", "render",
        "linear_extrude", "rotate_extrude", "surface", "import"
    ]
    
    // MARK: - Color Parser
    public static func parseColor(_ val: ScadValue) -> Euclid.Color {
        if case .string(let str) = val {
            return colorFromString(str)
        }
        if let vec = val.asDoubleArray() {
            let r = vec.count > 0 ? vec[0] : 1.0
            let g = vec.count > 1 ? vec[1] : 1.0
            let b = vec.count > 2 ? vec[2] : 1.0
            let a = vec.count > 3 ? vec[3] : 1.0
            return Euclid.Color(red: r, green: g, blue: b, alpha: a)
        }
        return Euclid.Color(red: 0.9, green: 0.7, blue: 0.2, alpha: 1.0)
    }
    
    public static func colorFromString(_ name: String) -> Euclid.Color {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if trimmed.hasPrefix("#") {
            let hex = String(trimmed.dropFirst())
            if hex.count == 6 {
                if let rgb = UInt32(hex, radix: 16) {
                    let r = Double((rgb >> 16) & 0xFF) / 255.0
                    let g = Double((rgb >> 8) & 0xFF) / 255.0
                    let b = Double(rgb & 0xFF) / 255.0
                    return Euclid.Color(red: r, green: g, blue: b, alpha: 1.0)
                }
            } else if hex.count == 8 {
                if let rgba = UInt64(hex, radix: 16) {
                    let r = Double((rgba >> 24) & 0xFF) / 255.0
                    let g = Double((rgba >> 16) & 0xFF) / 255.0
                    let b = Double((rgba >> 8) & 0xFF) / 255.0
                    let a = Double(rgba & 0xFF) / 255.0
                    return Euclid.Color(red: r, green: g, blue: b, alpha: a)
                }
            }
        }
        
        switch trimmed {
        case "red": return Euclid.Color(red: 1, green: 0, blue: 0)
        case "green": return Euclid.Color(red: 0, green: 0.8, blue: 0)
        case "blue": return Euclid.Color(red: 0, green: 0.4, blue: 1)
        case "yellow": return Euclid.Color(red: 1, green: 0.9, blue: 0)
        case "cyan": return Euclid.Color(red: 0, green: 0.9, blue: 0.9)
        case "magenta": return Euclid.Color(red: 0.9, green: 0, blue: 0.9)
        case "orange": return Euclid.Color(red: 1, green: 0.5, blue: 0)
        case "purple": return Euclid.Color(red: 0.5, green: 0, blue: 0.5)
        case "pink": return Euclid.Color(red: 1, green: 0.75, blue: 0.8)
        case "white": return Euclid.Color(red: 1, green: 1, blue: 1)
        case "black": return Euclid.Color(red: 0.1, green: 0.1, blue: 0.1)
        case "gray", "grey": return Euclid.Color(red: 0.5, green: 0.5, blue: 0.5)
        case "gold": return Euclid.Color(red: 1, green: 0.84, blue: 0)
        case "silver": return Euclid.Color(red: 0.75, green: 0.75, blue: 0.75)
        case "brown": return Euclid.Color(red: 0.6, green: 0.3, blue: 0.1)
        case "lime": return Euclid.Color(red: 0.2, green: 1, blue: 0.2)
        default: return Euclid.Color(red: 0.9, green: 0.7, blue: 0.2)
        }
    }
    
    // MARK: - Fragment Calculation ($fn, $fa, $fs)
    public static func calculateSlices(r: Double, args: [String: ScadValue]? = nil, env: Environment) -> Int {
        if let fn = args?["$fn"]?.asNumber(), fn > 0 {
            return max(3, Int(fn))
        }
        let fn = env.get("$fn").asNumber() ?? 0
        if fn > 0 {
            return max(3, Int(fn))
        }
        let fa = max(0.01, args?["$fa"]?.asNumber() ?? env.get("$fa").asNumber() ?? 12.0)
        let fs = max(0.01, args?["$fs"]?.asNumber() ?? env.get("$fs").asNumber() ?? 2.0)
        let f1 = 360.0 / fa
        let f2 = (2.0 * Double.pi * max(r, 0.01)) / fs
        let count = ceil(max(min(f1, f2), 5.0))
        return max(5, Int(count))
    }
    
    // MARK: - 3D Primitives
    
    public static func createCube(args: [String: ScadValue]) -> CSGGeometry {
        let sizeVal = args["size"] ?? args["_pos0"] ?? .number(1)
        let center = (args["center"] ?? args["_pos1"])?.asBool() ?? false
        
        let sx: Double
        let sy: Double
        let sz: Double
        
        if let s = sizeVal.asNumber() {
            sx = s; sy = s; sz = s
        } else if let vec = sizeVal.asDoubleArray() {
            sx = vec.count > 0 ? vec[0] : 1
            sy = vec.count > 1 ? vec[1] : 1
            sz = vec.count > 2 ? vec[2] : 1
        } else {
            sx = 1; sy = 1; sz = 1
        }
        
        var mesh = Mesh.cube(size: Euclid.Vector(sx, sy, sz))
        if !center {
            mesh = mesh.translated(by: Euclid.Vector(sx / 2.0, sy / 2.0, sz / 2.0))
        }
        return .mesh(mesh)
    }
    
    public static func createSphere(args: [String: ScadValue], env: Environment) -> CSGGeometry {
        let rVal = (args["r"] ?? args["_pos0"])?.asNumber()
        let dVal = args["d"]?.asNumber()
        let r = rVal ?? (dVal != nil ? dVal! / 2.0 : 1.0)
        let slices = calculateSlices(r: r, args: args, env: env)
        
        let mesh = Mesh.sphere(radius: r, slices: slices, stacks: slices / 2)
        return .mesh(mesh)
    }
    
    public static func createCylinder(args: [String: ScadValue], env: Environment) -> CSGGeometry {
        let h = (args["h"] ?? args["_pos0"])?.asNumber() ?? 1.0
        let center = (args["center"] ?? args["_pos4"])?.asBool() ?? false
        
        let rVal = (args["r"] ?? args["_pos1"])?.asNumber()
        let dVal = args["d"]?.asNumber()
        let defaultR = rVal ?? (dVal != nil ? dVal! / 2.0 : 1.0)
        
        let r1Val = args["r1"]?.asNumber()
        let d1Val = args["d1"]?.asNumber()
        let r1 = r1Val ?? (d1Val != nil ? d1Val! / 2.0 : defaultR)
        
        let r2Val = args["r2"]?.asNumber()
        let d2Val = args["d2"]?.asNumber()
        let r2 = r2Val ?? (d2Val != nil ? d2Val! / 2.0 : defaultR)
        
        let maxR = max(r1, r2)
        let slices = calculateSlices(r: maxR, args: args, env: env)
        
        var mesh: Mesh
        if abs(r1 - r2) < 1e-5 {
            mesh = Mesh.cylinder(radius: r1, height: h, slices: slices)
        } else {
            mesh = Mesh.cone(radius: r1, height: h, slices: slices)
            if r2 > 0 {
                let p0 = Euclid.Vector(0, -h / 2.0, 0)
                let p1 = Euclid.Vector(r1, -h / 2.0, 0)
                let p2 = Euclid.Vector(r2, h / 2.0, 0)
                let p3 = Euclid.Vector(0, h / 2.0, 0)
                let profile = Path([
                    PathPoint.point(p0),
                    PathPoint.point(p1),
                    PathPoint.point(p2),
                    PathPoint.point(p3),
                    PathPoint.point(p0)
                ])
                mesh = Mesh.lathe(profile, slices: slices)
            }
        }
        
        mesh = mesh.rotated(by: Rotation.pitch(Angle.degrees(90)))
        if !center {
            mesh = mesh.translated(by: Euclid.Vector(0, 0, h / 2.0))
        }
        return .mesh(mesh)
    }
    
    public static func createPolyhedron(args: [String: ScadValue]) -> CSGGeometry {
        guard let pointsVal = (args["points"] ?? args["_pos0"])?.asVector() else { return .empty }
        let points: [Euclid.Vector] = pointsVal.compactMap { pt in
            guard let coords = pt.asDoubleArray(), coords.count >= 3 else { return nil }
            return Euclid.Vector(coords[0], coords[1], coords[2])
        }
        
        let facesVal = args["faces"] ?? args["triangles"] ?? args["_pos1"]
        guard let faceList = facesVal?.asVector() else { return .empty }
        
        var polygons: [Euclid.Polygon] = []
        for face in faceList {
            guard let indices = face.asDoubleArray(), indices.count >= 3 else { continue }
            let faceVertices: [Vertex] = indices.compactMap { idx in
                let i = Int(idx)
                guard i >= 0 && i < points.count else { return nil }
                return Vertex(points[i])
            }
            if faceVertices.count >= 3, let poly = Euclid.Polygon(faceVertices) {
                polygons.append(poly)
            }
        }
        return .mesh(Mesh(polygons))
    }
    
    // MARK: - 2D Primitives
    
    public static func createSquare(args: [String: ScadValue]) -> CSGGeometry {
        let sizeVal = args["size"] ?? args["_pos0"] ?? .number(1)
        let center = (args["center"] ?? args["_pos1"])?.asBool() ?? false
        
        let sx: Double
        let sy: Double
        if let s = sizeVal.asNumber() {
            sx = s; sy = s
        } else if let vec = sizeVal.asDoubleArray() {
            sx = vec.count > 0 ? vec[0] : 1
            sy = vec.count > 1 ? vec[1] : 1
        } else {
            sx = 1; sy = 1
        }
        
        let minX = center ? -sx / 2.0 : 0.0
        let maxX = center ? sx / 2.0 : sx
        let minY = center ? -sy / 2.0 : 0.0
        let maxY = center ? sy / 2.0 : sy
        
        let path = Path([
            PathPoint.point(Euclid.Vector(minX, minY, 0)),
            PathPoint.point(Euclid.Vector(maxX, minY, 0)),
            PathPoint.point(Euclid.Vector(maxX, maxY, 0)),
            PathPoint.point(Euclid.Vector(minX, maxY, 0)),
            PathPoint.point(Euclid.Vector(minX, minY, 0))
        ])
        return .path(path)
    }
    
    public static func createCircle(args: [String: ScadValue], env: Environment) -> CSGGeometry {
        let rVal = (args["r"] ?? args["_pos0"])?.asNumber()
        let dVal = args["d"]?.asNumber()
        let r = rVal ?? (dVal != nil ? dVal! / 2.0 : 1.0)
        let slices = calculateSlices(r: r, args: args, env: env)
        
        let path = Path.circle(radius: r, segments: slices)
        return .path(path)
    }
    
    public static func createPolygon(args: [String: ScadValue]) -> CSGGeometry {
        guard let ptsVal = (args["points"] ?? args["_pos0"])?.asVector() else { return .empty }
        let points: [Euclid.Vector] = ptsVal.compactMap { pt in
            guard let coords = pt.asDoubleArray(), coords.count >= 2 else { return nil }
            return Euclid.Vector(coords[0], coords[1], 0)
        }
        guard points.count >= 3 else { return .empty }
        var pathPoints = points.map { PathPoint.point($0) }
        pathPoints.append(pathPoints[0]) // close loop
        let path = Path(pathPoints)
        return .path(path)
    }
    
    // MARK: - Text (Native CoreText Engine)
    
    public static func createText(args: [String: ScadValue]) -> CSGGeometry {
        let text = (args["text"] ?? args["_pos0"])?.asString() ?? ""
        guard !text.isEmpty else { return .empty }
        let size = (args["size"] ?? args["_pos1"])?.asNumber() ?? 10.0
        let fontName = (args["font"] ?? args["_pos2"])?.asString() ?? "Helvetica"
        let halign = args["halign"]?.asString() ?? "left"
        let valign = args["valign"]?.asString() ?? "baseline"
        let spacing = args["spacing"]?.asNumber() ?? 1.0
        
        let ctFont = CTFontCreateWithName(fontName as CFString, CGFloat(size), nil)
        let attrString = NSAttributedString(string: text, attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): ctFont
        ])
        let line = CTLineCreateWithAttributedString(attrString as CFAttributedString)
        
        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        var leading: CGFloat = 0
        let lineWidth = CTLineGetTypographicBounds(line, &ascent, &descent, &leading)
        
        let offsetX: CGFloat
        switch halign.lowercased() {
        case "center": offsetX = -lineWidth / 2.0
        case "right": offsetX = -lineWidth
        default: offsetX = 0.0
        }
        
        let offsetY: CGFloat
        switch valign.lowercased() {
        case "top": offsetY = -ascent
        case "center": offsetY = -(ascent - descent) / 2.0
        case "bottom": offsetY = descent
        default: offsetY = 0.0
        }
        
        let runs = CTLineGetGlyphRuns(line) as? [CTRun] ?? []
        let compositePath = CGMutablePath()
        
        for run in runs {
            let attributes = CTRunGetAttributes(run) as NSDictionary
            let runFont: CTFont
            if let fontVal = attributes[kCTFontAttributeName as String], CFGetTypeID(fontVal as CFTypeRef) == CTFontGetTypeID() {
                runFont = (fontVal as! CTFont)
            } else {
                runFont = ctFont
            }
            let glyphCount = CTRunGetGlyphCount(run)
            var glyphs = [CGGlyph](repeating: 0, count: glyphCount)
            var positions = [CGPoint](repeating: .zero, count: glyphCount)
            CTRunGetGlyphs(run, CFRangeMake(0, glyphCount), &glyphs)
            CTRunGetPositions(run, CFRangeMake(0, glyphCount), &positions)
            
            for i in 0..<glyphCount {
                if let glyphPath = CTFontCreatePathForGlyph(runFont, glyphs[i], nil) {
                    let transform = CGAffineTransform(
                        translationX: positions[i].x * CGFloat(spacing) + offsetX,
                        y: positions[i].y + offsetY
                    )
                    compositePath.addPath(glyphPath, transform: transform)
                }
            }
        }
        
        let euclidPaths = convertCGPathToEuclidPaths(compositePath)
        guard !euclidPaths.isEmpty else { return .empty }
        if euclidPaths.count == 1 {
            return .path(euclidPaths[0])
        }
        return .path(Path(subpaths: euclidPaths))
    }
    
    private static func convertCGPathToEuclidPaths(_ cgPath: CGPath) -> [Euclid.Path] {
        var subpaths: [[Euclid.Vector]] = []
        var currentPoints: [Euclid.Vector] = []
        
        cgPath.applyWithBlock { elementPtr in
            let element = elementPtr.pointee
            switch element.type {
            case .moveToPoint:
                if currentPoints.count >= 3 {
                    subpaths.append(currentPoints)
                }
                currentPoints = [Euclid.Vector(Double(element.points[0].x), Double(element.points[0].y), 0)]
                
            case .addLineToPoint:
                currentPoints.append(Euclid.Vector(Double(element.points[0].x), Double(element.points[0].y), 0))
                
            case .addQuadCurveToPoint:
                if let p0 = currentPoints.last {
                    let p1 = Euclid.Vector(Double(element.points[0].x), Double(element.points[0].y), 0)
                    let p2 = Euclid.Vector(Double(element.points[1].x), Double(element.points[1].y), 0)
                    let steps = 6
                    for s in 1...steps {
                        let t = Double(s) / Double(steps)
                        let invT = 1.0 - t
                        let x = invT * invT * p0.x + 2 * invT * t * p1.x + t * t * p2.x
                        let y = invT * invT * p0.y + 2 * invT * t * p1.y + t * t * p2.y
                        currentPoints.append(Euclid.Vector(x, y, 0))
                    }
                }
                
            case .addCurveToPoint:
                if let p0 = currentPoints.last {
                    let p1 = Euclid.Vector(Double(element.points[0].x), Double(element.points[0].y), 0)
                    let p2 = Euclid.Vector(Double(element.points[1].x), Double(element.points[1].y), 0)
                    let p3 = Euclid.Vector(Double(element.points[2].x), Double(element.points[2].y), 0)
                    let steps = 8
                    for s in 1...steps {
                        let t = Double(s) / Double(steps)
                        let invT = 1.0 - t
                        let x = invT*invT*invT * p0.x + 3*invT*invT*t * p1.x + 3*invT*t*t * p2.x + t*t*t * p3.x
                        let y = invT*invT*invT * p0.y + 3*invT*invT*t * p1.y + 3*invT*t*t * p2.y + t*t*t * p3.y
                        currentPoints.append(Euclid.Vector(x, y, 0))
                    }
                }
                
            case .closeSubpath:
                if currentPoints.count >= 3 {
                    if let first = currentPoints.first, let last = currentPoints.last, first != last {
                        currentPoints.append(first)
                    }
                    subpaths.append(currentPoints)
                }
                currentPoints = []
                
            @unknown default:
                break
            }
        }
        
        if currentPoints.count >= 3 {
            subpaths.append(currentPoints)
        }
        
        return subpaths.map { pts in
            Path(pts.map { PathPoint.point($0) })
        }
    }
    
    // MARK: - Extrusions
    
    public static func linearExtrude(args: [String: ScadValue], children: [CSGGeometry]) -> CSGGeometry {
        let height = (args["height"] ?? args["_pos0"])?.asNumber() ?? 10.0
        let center = (args["center"] ?? args["_pos1"])?.asBool() ?? false
        let twist = args["twist"]?.asNumber() ?? 0.0
        let slices = args["slices"]?.asNumber().map { Int($0) }
        
        let scaleVal = args["scale"]
        let scaleX: Double
        let scaleY: Double
        if let s = scaleVal?.asNumber() {
            scaleX = s
            scaleY = s
        } else if let arr = scaleVal?.asDoubleArray(), arr.count >= 2 {
            scaleX = arr[0]
            scaleY = arr[1]
        } else {
            scaleX = 1.0
            scaleY = 1.0
        }
        
        var meshes: [Mesh] = []
        for child in children {
            if case .path(let p) = child {
                var m = Mesh.extrude(p, depth: height, twist: .degrees(twist), sections: slices)
                if !center {
                    m = m.translated(by: Euclid.Vector(0, 0, height / 2.0))
                }
                if abs(scaleX - 1.0) > 1e-4 || abs(scaleY - 1.0) > 1e-4 {
                    let baseZ = center ? -height / 2.0 : 0.0
                    let scaledPolys = m.polygons.compactMap { poly -> Polygon? in
                        let pts = poly.vertices.map { v -> Vertex in
                            let zFrac = max(0.0, min(1.0, (v.position.z - baseZ) / height))
                            let sx = 1.0 + (scaleX - 1.0) * zFrac
                            let sy = 1.0 + (scaleY - 1.0) * zFrac
                            let newPos = Euclid.Vector(v.position.x * sx, v.position.y * sy, v.position.z)
                            return Vertex(newPos, .zero, v.texcoord, v.color)
                        }
                        return Polygon(pts, material: poly.material)
                    }
                    m = Mesh(scaledPolys).smoothingNormals(forAnglesGreaterThan: .degrees(45))
                }
                meshes.append(m)
            } else if case .collection(let sub) = child {
                let subExt = linearExtrude(args: args, children: sub)
                meshes.append(subExt.toMesh())
            }
        }
        return .mesh(Mesh.union(meshes))
    }
    
    public static func rotateExtrude(args: [String: ScadValue], children: [CSGGeometry], env: Environment) -> CSGGeometry {
        _ = args["angle"]?.asNumber() ?? 360.0
        let slices = calculateSlices(r: 10, args: args, env: env)
        
        var meshes: [Mesh] = []
        for child in children {
            if case .path(let p) = child {
                var m = Mesh.lathe(p, slices: slices)
                m = m.rotated(by: Rotation.pitch(Angle.degrees(90)))
                meshes.append(m)
            } else if case .collection(let sub) = child {
                let subExt = rotateExtrude(args: args, children: sub, env: env)
                meshes.append(subExt.toMesh())
            }
        }
        return .mesh(Mesh.union(meshes))
    }
    
    // MARK: - Advanced CAD Modules: Multmatrix, Resize, Offset, Projection, Minkowski, Surface, Import, Render
    
    public static func multmatrix(args: [String: ScadValue], children: [CSGGeometry]) -> CSGGeometry {
        guard let mVal = (args["m"] ?? args["_pos0"])?.asVector() else {
            return CSGGeometry.union(children)
        }
        let matrix: [[Double]] = mVal.compactMap { $0.asDoubleArray() }
        let childUnion = CSGGeometry.union(children)
        return childUnion.transformed(byMatrix: matrix)
    }
    
    public static func resize(args: [String: ScadValue], children: [CSGGeometry]) -> CSGGeometry {
        let childUnion = CSGGeometry.union(children)
        let mesh = childUnion.toMesh()
        guard !mesh.polygons.isEmpty else { return childUnion }
        
        let bounds = mesh.bounds
        let size = bounds.max - bounds.min
        guard size.x > 1e-5, size.y > 1e-5, size.z > 1e-5 else { return childUnion }
        
        let newSizeVec = (args["newsize"] ?? args["_pos0"])?.asDoubleArray() ?? [0, 0, 0]
        let autoVal = (args["auto"] ?? args["_pos1"])
        let autoBools: [Bool]
        if let boolVal = autoVal?.asBool() {
            autoBools = [boolVal, boolVal, boolVal]
        } else if let arr = autoVal?.asVector() {
            autoBools = arr.map { $0.asBool() ?? false }
        } else {
            autoBools = [false, false, false]
        }
        
        let targetX = newSizeVec.count > 0 ? newSizeVec[0] : 0.0
        let targetY = newSizeVec.count > 1 ? newSizeVec[1] : 0.0
        let targetZ = newSizeVec.count > 2 ? newSizeVec[2] : 0.0
        
        var scaleRatios: [Double] = []
        if targetX > 0 && (autoBools.count <= 0 || !autoBools[0]) { scaleRatios.append(targetX / size.x) }
        if targetY > 0 && (autoBools.count <= 1 || !autoBools[1]) { scaleRatios.append(targetY / size.y) }
        if targetZ > 0 && (autoBools.count <= 2 || !autoBools[2]) { scaleRatios.append(targetZ / size.z) }
        let autoScale = scaleRatios.first ?? 1.0
        
        let sx = targetX > 0 ? targetX / size.x : ((autoBools.count > 0 && autoBools[0]) ? autoScale : 1.0)
        let sy = targetY > 0 ? targetY / size.y : ((autoBools.count > 1 && autoBools[1]) ? autoScale : 1.0)
        let sz = targetZ > 0 ? targetZ / size.z : ((autoBools.count > 2 && autoBools[2]) ? autoScale : 1.0)
        
        let scaled = childUnion.scaled(by: Euclid.Vector(sx, sy, sz))
        let scaledMesh = scaled.toMesh()
        let oldCenter = (bounds.min + bounds.max) / 2.0
        let newCenter = (scaledMesh.bounds.min + scaledMesh.bounds.max) / 2.0
        return scaled.translated(by: oldCenter - newCenter)
    }
    
    public static func offset(args: [String: ScadValue], children: [CSGGeometry]) -> CSGGeometry {
        let r = args["r"]?.asNumber()
        let delta = args["delta"]?.asNumber() ?? r ?? 0.0
        let childUnion = CSGGeometry.union(children)
        return childUnion.offset2D(delta: delta)
    }
    
    public static func projection(args: [String: ScadValue], children: [CSGGeometry]) -> CSGGeometry {
        let cut = (args["cut"] ?? args["_pos0"])?.asBool() ?? false
        let childUnion = CSGGeometry.union(children)
        return childUnion.projected(cut: cut)
    }
    
    public static func importFile(args: [String: ScadValue], basePath: URL?) -> CSGGeometry {
        guard let fileStr = (args["file"] ?? args["_pos0"])?.asString() else { return .empty }
        let fileURL: URL
        if fileStr.hasPrefix("/") {
            fileURL = URL(fileURLWithPath: fileStr)
        } else if let base = basePath {
            fileURL = base.appendingPathComponent(fileStr)
        } else {
            fileURL = URL(fileURLWithPath: fileStr)
        }
        
        if let mesh = try? Mesh(url: fileURL) {
            return .mesh(mesh)
        }
        if let data = try? Data(contentsOf: fileURL) {
            if let mesh = Mesh(stlData: data) {
                return .mesh(mesh)
            }
            if let str = String(data: data, encoding: .utf8), let mesh = Mesh(objString: str) {
                return .mesh(mesh)
            }
        }
        return .empty
    }
    
    public static func createSurface(args: [String: ScadValue], basePath: URL?) -> CSGGeometry {
        guard let fileStr = (args["file"] ?? args["_pos0"])?.asString() else { return .empty }
        let center = (args["center"] ?? args["_pos1"])?.asBool() ?? false
        let invert = args["invert"]?.asBool() ?? false
        
        let fileURL: URL
        if fileStr.hasPrefix("/") {
            fileURL = URL(fileURLWithPath: fileStr)
        } else if let base = basePath {
            fileURL = base.appendingPathComponent(fileStr)
        } else {
            fileURL = URL(fileURLWithPath: fileStr)
        }
        
        if let image = NSImage(contentsOf: fileURL),
           let tiff = image.tiffRepresentation,
           let rep = NSBitmapImageRep(data: tiff) {
            let width = min(rep.pixelsWide, 80)
            let height = min(rep.pixelsHigh, 80)
            guard width > 1, height > 1 else { return .empty }
            
            var heights: [[Double]] = Array(repeating: Array(repeating: 0.0, count: width), count: height)
            for y in 0..<height {
                for x in 0..<width {
                    if let color = rep.colorAt(x: x, y: y) {
                        var brightness = Double(color.brightnessComponent)
                        if invert { brightness = 1.0 - brightness }
                        heights[y][x] = brightness * 10.0 + 1.0
                    }
                }
            }
            return buildSurfaceMesh(heights: heights, center: center)
        } else if let content = try? String(contentsOf: fileURL, encoding: .utf8) {
            var heights: [[Double]] = []
            for line in content.components(separatedBy: .newlines) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
                let row = trimmed.components(separatedBy: .whitespaces).compactMap { Double($0) }
                if !row.isEmpty {
                    heights.append(row)
                }
            }
            guard heights.count > 1, (heights.first?.count ?? 0) > 1 else { return .empty }
            return buildSurfaceMesh(heights: heights, center: center)
        }
        return .empty
    }
    
    private static func buildSurfaceMesh(heights: [[Double]], center: Bool) -> CSGGeometry {
        let rows = heights.count
        let cols = heights[0].count
        let ox = center ? -Double(cols - 1) / 2.0 : 0.0
        let oy = center ? -Double(rows - 1) / 2.0 : 0.0
        
        var polygons: [Euclid.Polygon] = []
        for r in 0..<(rows - 1) {
            for c in 0..<(cols - 1) {
                let p00 = Euclid.Vector(ox + Double(c), oy + Double(r), heights[r][c])
                let p10 = Euclid.Vector(ox + Double(c + 1), oy + Double(r), heights[r][c + 1])
                let p11 = Euclid.Vector(ox + Double(c + 1), oy + Double(r + 1), heights[r + 1][c + 1])
                let p01 = Euclid.Vector(ox + Double(c), oy + Double(r + 1), heights[r + 1][c])
                
                // Top surface
                if let t1 = Polygon([Vertex(p00), Vertex(p10), Vertex(p11)]) {
                    polygons.append(t1)
                }
                if let t2 = Polygon([Vertex(p00), Vertex(p11), Vertex(p01)]) {
                    polygons.append(t2)
                }
                
                // Bottom surface (Z = 0)
                let b00 = Euclid.Vector(ox + Double(c), oy + Double(r), 0)
                let b10 = Euclid.Vector(ox + Double(c + 1), oy + Double(r), 0)
                let b11 = Euclid.Vector(ox + Double(c + 1), oy + Double(r + 1), 0)
                let b01 = Euclid.Vector(ox + Double(c), oy + Double(r + 1), 0)
                if let bt1 = Polygon([Vertex(b11), Vertex(b10), Vertex(b00)]) {
                    polygons.append(bt1)
                }
                if let bt2 = Polygon([Vertex(b01), Vertex(b11), Vertex(b00)]) {
                    polygons.append(bt2)
                }
            }
        }
        return .mesh(Mesh(polygons))
    }
    
    public static func createMinkowski(children: [CSGGeometry]) -> CSGGeometry {
        guard children.count >= 2 else { return children.first ?? .empty }
        let a = children[0].toMesh()
        let b = children[1].toMesh()
        guard !a.polygons.isEmpty, !b.polygons.isEmpty else { return children[0] }
        
        // Edge-sweep Minkowski sum approximation:
        var edges: [(Euclid.Vector, Euclid.Vector)] = []
        for poly in a.polygons {
            let pts = poly.vertices.map { $0.position }
            for i in 0..<pts.count {
                let p1 = pts[i]
                let p2 = pts[(i + 1) % pts.count]
                edges.append((p1, p2))
            }
        }
        
        let sampleEdges = edges.count > 80 ? Array(edges.prefix(80)) : edges
        var edgeHulls: [Mesh] = []
        edgeHulls.reserveCapacity(sampleEdges.count)
        
        for (p1, p2) in sampleEdges {
            let b1 = b.translated(by: p1)
            let b2 = b.translated(by: p2)
            let h = Mesh.convexHull(of: [b1, b2])
            edgeHulls.append(h)
        }
        
        return .mesh(Mesh.union(edgeHulls))
    }
    
    public static func render(args: [String: ScadValue], children: [CSGGeometry]) -> CSGGeometry {
        return CSGGeometry.union(children)
    }
    
    // MARK: - Hull
    
    public static func createHull(children: [CSGGeometry]) -> CSGGeometry {
        return CSGGeometry.hull(children)
    }
}
