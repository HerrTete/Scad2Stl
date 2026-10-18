import Foundation
import Euclid

public enum ScadValue: Equatable, Sendable {
    case number(Double)
    case string(String)
    case bool(Bool)
    case vector([ScadValue])
    case range(start: Double, step: Double, end: Double)
    case undef
    case functionClosure(params: [ParamDef], body: Expression)
    
    // MARK: - Truthiness
    public var isTruthy: Bool {
        switch self {
        case .bool(let b): return b
        case .number(let n): return n != 0 && !n.isNaN
        case .string(let s): return !s.isEmpty
        case .vector(let v): return !v.isEmpty
        case .range: return true
        case .undef: return false
        case .functionClosure: return true
        }
    }
    
    // MARK: - Conversions
    public func asNumber() -> Double? {
        if case .number(let n) = self { return n }
        return nil
    }
    
    public func asBool() -> Bool? {
        if case .bool(let b) = self { return b }
        return nil
    }
    
    public func asString() -> String {
        switch self {
        case .number(let n):
            if n.rounded() == n && !n.isInfinite && !n.isNaN && abs(n) < 1e15 {
                return String(Int64(n))
            }
            return String(n)
        case .string(let s): return s
        case .bool(let b): return b ? "true" : "false"
        case .vector(let vec):
            let elements = vec.map { $0.asString() }.joined(separator: ", ")
            return "[\(elements)]"
        case .range(let start, let step, let end):
            if step == 1.0 {
                return "[\(start) : \(end)]"
            } else {
                return "[\(start) : \(step) : \(end)]"
            }
        case .undef: return "undef"
        case .functionClosure: return "function"
        }
    }
    
    public func asVector() -> [ScadValue]? {
        switch self {
        case .vector(let v): return v
        case .range(let start, let step, let end):
            var vals: [ScadValue] = []
            if step > 0 && start <= end {
                var cur = start
                while cur <= end + 1e-9 {
                    vals.append(.number(cur))
                    cur += step
                }
            } else if step < 0 && start >= end {
                var cur = start
                while cur >= end - 1e-9 {
                    vals.append(.number(cur))
                    cur += step
                }
            }
            return vals
        default: return nil
        }
    }
    
    public func asVector3() -> Euclid.Vector? {
        guard let vec = asVector(), vec.count >= 2 else { return nil }
        let x = vec[0].asNumber() ?? 0.0
        let y = vec[1].asNumber() ?? 0.0
        let z = vec.count > 2 ? (vec[2].asNumber() ?? 0.0) : 0.0
        return Euclid.Vector(x, y, z)
    }
    
    public func asDoubleArray() -> [Double]? {
        guard let vec = asVector() else { return nil }
        return vec.compactMap { $0.asNumber() }
    }
    
    // MARK: - Subscripting
    public subscript(index: Int) -> ScadValue {
        guard let vec = asVector() else { return .undef }
        if index >= 0 && index < vec.count {
            return vec[index]
        }
        return .undef
    }
}
