import Foundation
import Euclid

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
