import Foundation
import Euclid

public struct BuiltinModules {
    public static func isBuiltinModule(_ name: String) -> Bool {
        return moduleNames.contains(name)
    }
    
    private static let moduleNames: Set<String> = [
        "cube", "sphere", "cylinder", "polyhedron",
        "square", "circle", "polygon",
        "translate", "rotate", "scale", "mirror", "color",
        "union", "difference", "intersection", "hull",
        "linear_extrude", "rotate_extrude"
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
        
        if let num = sizeVal.asNumber() {
            sx = num
            sy = num
            sz = num
        } else if let arr = sizeVal.asDoubleArray(), arr.count >= 2 {
            sx = arr[0]
            sy = arr[1]
            sz = arr.count > 2 ? arr[2] : 1.0
        } else {
            sx = 1.0
            sy = 1.0
            sz = 1.0
        }
        
        let size = Euclid.Vector(sx, sy, sz)
        let centerOffset: Euclid.Vector
        if center {
            centerOffset = .zero
        } else {
            centerOffset = Euclid.Vector(sx / 2.0, sy / 2.0, sz / 2.0)
        }
        
        let mesh = Mesh.cube(center: centerOffset, size: size)
        return .mesh(mesh)
    }
    
    public static func createSphere(args: [String: ScadValue], env: Environment) -> CSGGeometry {
        var radius = 1.0
        if let r = (args["r"] ?? args["_pos0"])?.asNumber() {
            radius = r
        } else if let d = args["d"]?.asNumber() {
            radius = d / 2.0
        }
        
        let slices = calculateSlices(r: radius, args: args, env: env)
        let mesh = Mesh.sphere(radius: radius, slices: slices)
        return .mesh(mesh)
    }
    
    public static func createCylinder(args: [String: ScadValue], env: Environment) -> CSGGeometry {
        let height = (args["h"] ?? args["_pos0"])?.asNumber() ?? 1.0
        let center = (args["center"] ?? args["_pos3"])?.asBool() ?? false
        
        var r1 = 1.0
        var r2 = 1.0
        
        if let r = (args["r"] ?? args["_pos1"])?.asNumber() {
            r1 = r
            r2 = r
        } else if let d = args["d"]?.asNumber() {
            r1 = d / 2.0
            r2 = d / 2.0
        }
        
        if let r1Val = args["r1"]?.asNumber() {
            r1 = r1Val
        } else if let d1Val = args["d1"]?.asNumber() {
            r1 = d1Val / 2.0
        }
        
        if let r2Val = args["r2"]?.asNumber() {
            r2 = r2Val
        } else if let d2Val = args["d2"]?.asNumber() {
            r2 = d2Val / 2.0
        }
        
        // If positional arguments cylinder(h, r1, r2, center)
        if let pos1 = args["_pos1"]?.asNumber(), let pos2 = args["_pos2"]?.asNumber() {
            r1 = pos1
            r2 = pos2
        }
        
        let maxR = max(r1, r2)
        let slices = calculateSlices(r: maxR, args: args, env: env)
        
        // In Euclid, lathe profile around Y axis:
        // OpenSCAD cylinder is along Z axis.
        // Profile points in XY plane with X >= 0:
        // Lathe around Y will make cylinder with height along Y.
        // Then we rotate by 90 degrees around X to align with Z!
        let halfH = height / 2.0
        var points: [PathPoint] = []
        points.append(.point(0, -halfH))
        points.append(.point(-max(r1, 0.001), -halfH))
        points.append(.point(-max(r2, 0.001), halfH))
        points.append(.point(0, halfH))
        
        let profile = Path(points)
        var mesh = Mesh.lathe(profile, slices: slices)
        
        // Rotate from Y-axis to Z-axis: 90 deg around X axis
        mesh = mesh.rotated(by: Rotation.pitch(Angle.degrees(90)))
        
        // If center is false, in OpenSCAD Z is in [0, h]
        if !center {
            mesh = mesh.translated(by: Euclid.Vector(0, 0, halfH))
        }
        
        return .mesh(mesh)
    }
    
    public static func createPolyhedron(args: [String: ScadValue]) -> CSGGeometry {
        guard let pointsVal = (args["points"] ?? args["_pos0"])?.asVector(),
              let facesVal = (args["faces"] ?? args["triangles"] ?? args["_pos1"])?.asVector() else {
            return .empty
        }
        
        let vertices: [Euclid.Vector] = pointsVal.compactMap { pt in
            guard let coords = pt.asDoubleArray(), coords.count >= 3 else { return nil }
            return Euclid.Vector(coords[0], coords[1], coords[2])
        }
        
        var polygons: [Euclid.Polygon] = []
        for faceVal in facesVal {
            guard let idxList = faceVal.asDoubleArray() else { continue }
            let indices = idxList.map { Int($0) }
            guard indices.count >= 3 else { continue }
            // In OpenSCAD, face vertex order is clockwise when viewed from outside.
            // In Euclid, standard polygon order is anti-clockwise.
            // Reverse order if needed for outside normal:
            let polyVertices = indices.reversed().compactMap { idx -> Euclid.Vertex? in
                guard idx >= 0 && idx < vertices.count else { return nil }
                return Euclid.Vertex(vertices[idx])
            }
            if let poly = Polygon(polyVertices) {
                polygons.append(poly)
            }
        }
        
        return .mesh(Mesh(polygons))
    }
    
    // MARK: - 2D Primitives
    
    public static func createSquare(args: [String: ScadValue]) -> CSGGeometry {
        let sizeVal = args["size"] ?? args["_pos0"] ?? .number(1)
        let center = (args["center"] ?? args["_pos1"])?.asBool() ?? false
        
        let w: Double
        let h: Double
        if let n = sizeVal.asNumber() {
            w = n; h = n
        } else if let arr = sizeVal.asDoubleArray(), arr.count >= 2 {
            w = arr[0]; h = arr[1]
        } else {
            w = 1; h = 1
        }
        
        var path = Path.rectangle(width: w, height: h)
        if !center {
            path = path.translated(by: Euclid.Vector(w / 2.0, h / 2.0, 0))
        }
        return .path(path)
    }
    
    public static func createCircle(args: [String: ScadValue], env: Environment) -> CSGGeometry {
        var radius = 1.0
        if let r = (args["r"] ?? args["_pos0"])?.asNumber() {
            radius = r
        } else if let d = args["d"]?.asNumber() {
            radius = d / 2.0
        }
        let segments = calculateSlices(r: radius, args: args, env: env)
        let path = Path.circle(radius: radius, segments: segments)
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
    
    // MARK: - Extrusions
    
    public static func linearExtrude(args: [String: ScadValue], children: [CSGGeometry]) -> CSGGeometry {
        let height = (args["height"] ?? args["_pos0"])?.asNumber() ?? 10.0
        let center = (args["center"] ?? args["_pos1"])?.asBool() ?? false
        let twist = args["twist"]?.asNumber() ?? 0.0
        let slices = args["slices"]?.asNumber().map { Int($0) }
        
        var meshes: [Mesh] = []
        for child in children {
            if case .path(let p) = child {
                var m = Mesh.extrude(p, depth: height, twist: .degrees(twist), sections: slices)
                if !center {
                    m = m.translated(by: Euclid.Vector(0, 0, height / 2.0))
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
                // Euclid lathes around the Y axis. OpenSCAD rotates around the Z axis.
                // Pitch by 90 degrees around X brings the Y axis to the Z axis:
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
    
    // MARK: - Hull
    
    public static func createHull(children: [CSGGeometry]) -> CSGGeometry {
        return CSGGeometry.hull(children)
    }
}
