import Foundation
import Euclid

private typealias Polygon = Euclid.Polygon

public enum CSGGeometry: Sendable {
    case empty
    case mesh(Mesh)
    case path(Path)
    case collection([CSGGeometry])
    
    public var isEmpty: Bool {
        switch self {
        case .empty: return true
        case .mesh(let m): return m.polygons.isEmpty
        case .path(let p): return p.points.isEmpty
        case .collection(let items): return items.allSatisfy { $0.isEmpty }
        }
    }
    
    public func toMesh() -> Mesh {
        switch self {
        case .empty:
            return Mesh([])
        case .mesh(let m):
            return m
        case .path(let p):
            // If it's a 2D path, extrude with minimal thickness or triangulate
            if p.isClosed {
                return Mesh.extrude(p, depth: 0.01)
            }
            return Mesh([])
        case .collection(let items):
            let meshes = items.map { $0.toMesh() }.filter { !$0.polygons.isEmpty }
            guard !meshes.isEmpty else { return Mesh([]) }
            var combined = meshes[0]
            for m in meshes.dropFirst() {
                combined = combined.union(m)
            }
            return combined
        }
    }
    
    public func translated(by offset: Vector) -> CSGGeometry {
        switch self {
        case .empty:
            return .empty
        case .mesh(let m):
            return .mesh(m.translated(by: offset))
        case .path(let p):
            return .path(p.translated(by: offset))
        case .collection(let items):
            return .collection(items.map { $0.translated(by: offset) })
        }
    }
    
    public func rotated(by rotation: Rotation) -> CSGGeometry {
        switch self {
        case .empty:
            return .empty
        case .mesh(let m):
            return .mesh(m.rotated(by: rotation))
        case .path(let p):
            return .path(p.rotated(by: rotation))
        case .collection(let items):
            return .collection(items.map { $0.rotated(by: rotation) })
        }
    }
    
    public func scaled(by factor: Vector) -> CSGGeometry {
        switch self {
        case .empty:
            return .empty
        case .mesh(let m):
            return .mesh(m.scaled(by: factor))
        case .path(let p):
            return .path(p.scaled(by: factor))
        case .collection(let items):
            return .collection(items.map { $0.scaled(by: factor) })
        }
    }
    
    public func transformed(byMatrix m: [[Double]]) -> CSGGeometry {
        guard m.count >= 3 else { return self }
        let m00 = m[0].count > 0 ? m[0][0] : 1.0
        let m01 = m[0].count > 1 ? m[0][1] : 0.0
        let m02 = m[0].count > 2 ? m[0][2] : 0.0
        let m03 = m[0].count > 3 ? m[0][3] : 0.0
        
        let m10 = m[1].count > 0 ? m[1][0] : 0.0
        let m11 = m[1].count > 1 ? m[1][1] : 1.0
        let m12 = m[1].count > 2 ? m[1][2] : 0.0
        let m13 = m[1].count > 3 ? m[1][3] : 0.0
        
        let m20 = m[2].count > 0 ? m[2][0] : 0.0
        let m21 = m[2].count > 1 ? m[2][1] : 0.0
        let m22 = m[2].count > 2 ? m[2][2] : 1.0
        let m23 = m[2].count > 3 ? m[2][3] : 0.0
        
        let m30 = m.count > 3 && m[3].count > 0 ? m[3][0] : 0.0
        let m31 = m.count > 3 && m[3].count > 1 ? m[3][1] : 0.0
        let m32 = m.count > 3 && m[3].count > 2 ? m[3][2] : 0.0
        let m33 = m.count > 3 && m[3].count > 3 ? m[3][3] : 1.0
        
        func transformPoint(_ p: Vector) -> Vector {
            var x = m00 * p.x + m01 * p.y + m02 * p.z + m03
            var y = m10 * p.x + m11 * p.y + m12 * p.z + m13
            var z = m20 * p.x + m21 * p.y + m22 * p.z + m23
            let w = m30 * p.x + m31 * p.y + m32 * p.z + m33
            if abs(w) > 1e-6 && abs(w - 1.0) > 1e-6 {
                x /= w
                y /= w
                z /= w
            }
            return Vector(x, y, z)
        }
        
        switch self {
        case .empty:
            return .empty
        case .path(let p):
            let newPoints = p.points.map { pt -> PathPoint in
                var newPt = pt
                newPt.position = transformPoint(pt.position)
                return newPt
            }
            return .path(Path(newPoints))
        case .mesh(let m):
            let det = m00 * (m11 * m22 - m12 * m21) -
                      m01 * (m10 * m22 - m12 * m20) +
                      m02 * (m10 * m21 - m11 * m20)
            let isReflection = det < 0
            
            let newPolys = m.polygons.compactMap { poly -> Polygon? in
                var pts = poly.vertices.map { v in
                    Vertex(transformPoint(v.position), .zero, v.texcoord, v.color)
                }
                if isReflection {
                    pts.reverse()
                }
                return Polygon(pts, material: poly.material)
            }
            return .mesh(Mesh(newPolys).smoothingNormals(forAnglesGreaterThan: .degrees(45)))
        case .collection(let items):
            return .collection(items.map { $0.transformed(byMatrix: m) })
        }
    }
    
    public func offset2D(delta: Double) -> CSGGeometry {
        switch self {
        case .empty:
            return .empty
        case .path(let p):
            return .path(p.inset(by: -delta))
        case .mesh(let m):
            return .mesh(m)
        case .collection(let items):
            return .collection(items.map { $0.offset2D(delta: delta) })
        }
    }
    
    public func projected(cut: Bool) -> CSGGeometry {
        switch self {
        case .empty:
            return .empty
        case .path(let p):
            return .path(p)
        case .mesh(let m):
            if cut {
                let cutBox = Mesh.cube(size: Vector(10000, 10000, 0.04))
                let sliced = m.intersection(cutBox)
                let flatPolys = sliced.polygons.compactMap { poly -> Polygon? in
                    let pts = poly.vertices.map { v in
                        Vertex(Vector(v.position.x, v.position.y, 0), Vector(0, 0, 1))
                    }
                    return Polygon(pts, material: poly.material)
                }
                return .mesh(Mesh(flatPolys))
            } else {
                let flatPolys = m.polygons.compactMap { poly -> Polygon? in
                    let pts = poly.vertices.map { v in
                        Vertex(Vector(v.position.x, v.position.y, 0), Vector(0, 0, 1))
                    }
                    return Polygon(pts, material: poly.material)
                }
                return .mesh(Mesh(flatPolys))
            }
        case .collection(let items):
            return .collection(items.map { $0.projected(cut: cut) })
        }
    }
    
    public func withColor(_ color: Euclid.Color) -> CSGGeometry {
        switch self {
        case .empty:
            return .empty
        case .mesh(let m):
            let coloredPolys = m.polygons.map { poly in
                var newPoly = poly
                newPoly.material = color
                return newPoly
            }
            return .mesh(Mesh(coloredPolys))
        case .path(let p):
            return .path(p)
        case .collection(let items):
            return .collection(items.map { $0.withColor(color) })
        }
    }
    
    // MARK: - CSG Operations
    
    public static func union(_ geometries: [CSGGeometry]) -> CSGGeometry {
        let valid = geometries.filter { !$0.isEmpty }
        guard !valid.isEmpty else { return .empty }
        if valid.count == 1 { return valid[0] }
        
        let allPaths = valid.compactMap { (g: CSGGeometry) -> Path? in
            if case .path(let p) = g { return p }
            return nil
        }
        if allPaths.count == valid.count {
            if let p = Path.union(allPaths) {
                return .path(p)
            }
        }
        
        let meshes = valid.map { $0.toMesh() }.filter { !$0.polygons.isEmpty }
        guard !meshes.isEmpty else { return .empty }
        return .mesh(Mesh.union(meshes))
    }
    
    public static func difference(first: CSGGeometry, subtracting: [CSGGeometry]) -> CSGGeometry {
        if first.isEmpty { return .empty }
        let validSubs = subtracting.filter { !$0.isEmpty }
        if validSubs.isEmpty { return first }
        
        if case .path(let firstPath) = first {
            let subPaths = validSubs.compactMap { (g: CSGGeometry) -> Path? in
                if case .path(let p) = g { return p }
                return nil
            }
            if subPaths.count == validSubs.count {
                var pResult = firstPath
                for sp in subPaths {
                    if let diff = pResult.subtracting(sp) {
                        pResult = diff
                    }
                }
                return .path(pResult)
            }
        }
        
        var result = first.toMesh()
        for sub in validSubs {
            let subMesh = sub.toMesh()
            if !subMesh.polygons.isEmpty {
                result = result.subtracting(subMesh)
            }
        }
        return .mesh(result)
    }
    
    public static func intersection(_ geometries: [CSGGeometry]) -> CSGGeometry {
        let valid = geometries.filter { !$0.isEmpty }
        guard !valid.isEmpty else { return .empty }
        if valid.count == 1 { return valid[0] }
        
        var result = valid[0].toMesh()
        for g in valid.dropFirst() {
            let nextMesh = g.toMesh()
            result = result.intersection(nextMesh)
        }
        return .mesh(result)
    }
    
    public static func hull(_ geometries: [CSGGeometry]) -> CSGGeometry {
        let valid = geometries.filter { !$0.isEmpty }
        guard !valid.isEmpty else { return .empty }
        if valid.count == 1 { return valid[0] }
        
        let allPaths = valid.compactMap { (g: CSGGeometry) -> Path? in
            if case .path(let p) = g { return p }
            return nil
        }
        if allPaths.count == valid.count {
            if let p = Path.convexHull(of: allPaths) {
                return .path(p)
            }
        }
        
        let meshes = valid.map { $0.toMesh() }.filter { !$0.polygons.isEmpty }
        guard !meshes.isEmpty else { return .empty }
        let result = Mesh.convexHull(of: meshes)
        return .mesh(result)
    }
}
