import Foundation

public struct BuiltinFunctions {
    public static func isBuiltin(_ name: String) -> Bool {
        return functions[name] != nil
    }
    
    public static func call(_ name: String, args: [ScadValue]) -> ScadValue {
        guard let fn = functions[name] else { return .undef }
        return fn(args)
    }
    
    private static let functions: [String: ([ScadValue]) -> ScadValue] = [
        // MARK: - Trigonometry (in DEGREES)
        "sin": { args in
            guard let deg = args.first?.asNumber() else { return .undef }
            return .number(sin(deg * Double.pi / 180.0))
        },
        "cos": { args in
            guard let deg = args.first?.asNumber() else { return .undef }
            return .number(cos(deg * Double.pi / 180.0))
        },
        "tan": { args in
            guard let deg = args.first?.asNumber() else { return .undef }
            return .number(tan(deg * Double.pi / 180.0))
        },
        "asin": { args in
            guard let val = args.first?.asNumber() else { return .undef }
            return .number(asin(val) * 180.0 / Double.pi)
        },
        "acos": { args in
            guard let val = args.first?.asNumber() else { return .undef }
            return .number(acos(val) * 180.0 / Double.pi)
        },
        "atan": { args in
            guard let val = args.first?.asNumber() else { return .undef }
            return .number(atan(val) * 180.0 / Double.pi)
        },
        "atan2": { args in
            guard args.count >= 2, let y = args[0].asNumber(), let x = args[1].asNumber() else { return .undef }
            return .number(atan2(y, x) * 180.0 / Double.pi)
        },
        
        // MARK: - Math
        "abs": { args in
            guard let val = args.first?.asNumber() else { return .undef }
            return .number(abs(val))
        },
        "sign": { args in
            guard let val = args.first?.asNumber() else { return .undef }
            return .number(val < 0 ? -1 : (val > 0 ? 1 : 0))
        },
        "floor": { args in
            guard let val = args.first?.asNumber() else { return .undef }
            return .number(floor(val))
        },
        "ceil": { args in
            guard let val = args.first?.asNumber() else { return .undef }
            return .number(ceil(val))
        },
        "round": { args in
            guard let val = args.first?.asNumber() else { return .undef }
            return .number(round(val))
        },
        "sqrt": { args in
            guard let val = args.first?.asNumber() else { return .undef }
            return .number(sqrt(val))
        },
        "exp": { args in
            guard let val = args.first?.asNumber() else { return .undef }
            return .number(exp(val))
        },
        // OpenSCAD log is base 10!
        "log": { args in
            guard let val = args.first?.asNumber() else { return .undef }
            return .number(log10(val))
        },
        // OpenSCAD ln is natural log (base e)
        "ln": { args in
            guard let val = args.first?.asNumber() else { return .undef }
            return .number(Foundation.log(val))
        },
        "pow": { args in
            guard args.count >= 2, let b = args[0].asNumber(), let e = args[1].asNumber() else { return .undef }
            return .number(pow(b, e))
        },
        "min": { args in
            var nums: [Double] = []
            for arg in args {
                if let v = arg.asDoubleArray() {
                    nums.append(contentsOf: v)
                } else if let n = arg.asNumber() {
                    nums.append(n)
                }
            }
            guard let m = nums.min() else { return .undef }
            return .number(m)
        },
        "max": { args in
            var nums: [Double] = []
            for arg in args {
                if let v = arg.asDoubleArray() {
                    nums.append(contentsOf: v)
                } else if let n = arg.asNumber() {
                    nums.append(n)
                }
            }
            guard let m = nums.max() else { return .undef }
            return .number(m)
        },
        "norm": { args in
            guard let vec = args.first?.asDoubleArray() else { return .undef }
            let sumSq = vec.reduce(0.0) { $0 + $1 * $1 }
            return .number(sqrt(sumSq))
        },
        "cross": { args in
            guard args.count >= 2, let u = args[0].asDoubleArray(), let v = args[1].asDoubleArray(), u.count >= 3, v.count >= 3 else {
                return .undef
            }
            let x = u[1] * v[2] - u[2] * v[1]
            let y = u[2] * v[0] - u[0] * v[2]
            let z = u[0] * v[1] - u[1] * v[0]
            return .vector([.number(x), .number(y), .number(z)])
        },
        "rands": { args in
            guard args.count >= 3, let minVal = args[0].asNumber(), let maxVal = args[1].asNumber(), let countVal = args[2].asNumber() else {
                return .undef
            }
            let count = max(0, Int(countVal))
            var results: [ScadValue] = []
            for _ in 0..<count {
                let r = Double.random(in: minVal...maxVal)
                results.append(.number(r))
            }
            return .vector(results)
        },
        
        // MARK: - Strings and Lists
        "str": { args in
            let res = args.map { $0.asString() }.joined()
            return .string(res)
        },
        "chr": { args in
            guard let first = args.first else { return .undef }
            if let num = first.asNumber() {
                if let scalar = UnicodeScalar(UInt32(num)) {
                    return .string(String(Character(scalar)))
                }
                return .string("")
            }
            if let arr = first.asVector() {
                var s = ""
                for item in arr {
                    if let n = item.asNumber(), let scalar = UnicodeScalar(UInt32(n)) {
                        s.append(Character(scalar))
                    }
                }
                return .string(s)
            }
            return .undef
        },
        "ord": { args in
            guard let str = args.first?.asString(), let firstChar = str.first else { return .undef }
            return .number(Double(firstChar.unicodeScalars.first?.value ?? 0))
        },
        "len": { args in
            guard let first = args.first else { return .undef }
            switch first {
            case .string(let s): return .number(Double(s.count))
            case .vector(let v): return .number(Double(v.count))
            case .range:
                if let v = first.asVector() {
                    return .number(Double(v.count))
                }
                return .undef
            default: return .undef
            }
        },
        "concat": { args in
            var result: [ScadValue] = []
            for arg in args {
                if let vec = arg.asVector() {
                    result.append(contentsOf: vec)
                } else {
                    result.append(arg)
                }
            }
            return .vector(result)
        },
        "lookup": { args in
            guard args.count >= 2, let key = args[0].asNumber(), let table = args[1].asVector() else {
                return .undef
            }
            var pairs: [(Double, Double)] = []
            for entry in table {
                if let p = entry.asDoubleArray(), p.count >= 2 {
                    pairs.append((p[0], p[1]))
                }
            }
            guard !pairs.isEmpty else { return .undef }
            pairs.sort { $0.0 < $1.0 }
            
            if key <= pairs.first!.0 { return .number(pairs.first!.1) }
            if key >= pairs.last!.0 { return .number(pairs.last!.1) }
            
            for i in 0..<(pairs.count - 1) {
                let k0 = pairs[i].0
                let v0 = pairs[i].1
                let k1 = pairs[i+1].0
                let v1 = pairs[i+1].1
                if key >= k0 && key <= k1 {
                    let t = (key - k0) / (k1 - k0)
                    let interpolated = v0 + (v1 - v0) * t
                    return .number(interpolated)
                }
            }
            return .number(pairs.last!.1)
        },
        
        // MARK: - Type Checking
        "is_undef": { args in .bool(args.first == .undef) },
        "is_bool": { args in
            if case .bool = args.first { return .bool(true) }
            return .bool(false)
        },
        "is_num": { args in
            if case .number = args.first { return .bool(true) }
            return .bool(false)
        },
        "is_string": { args in
            if case .string = args.first { return .bool(true) }
            return .bool(false)
        },
        "is_list": { args in
            if case .vector = args.first { return .bool(true) }
            if case .range = args.first { return .bool(true) }
            return .bool(false)
        },
        "is_function": { args in
            if case .functionClosure = args.first { return .bool(true) }
            return .bool(false)
        },
        
        // MARK: - Query & Search
        "search": { args in
            guard args.count >= 2 else { return .undef }
            let matchVal = args[0]
            let table = args[1]
            let numReturns = (args.count > 2 ? args[2].asNumber() : 1) ?? 1
            let colNum = Int((args.count > 3 ? args[3].asNumber() : 0) ?? 0)
            
            if case .string(let target) = matchVal, case .string(let src) = table {
                var indices: [ScadValue] = []
                var searchStart = src.startIndex
                while searchStart < src.endIndex, let range = src.range(of: target, range: searchStart..<src.endIndex) {
                    let idx = src.distance(from: src.startIndex, to: range.lowerBound)
                    indices.append(.number(Double(idx)))
                    if numReturns > 0 && indices.count >= Int(numReturns) { break }
                    searchStart = src.index(after: range.lowerBound)
                }
                return .vector(indices)
            }
            
            if let list = table.asVector() {
                var indices: [ScadValue] = []
                for (i, elem) in list.enumerated() {
                    let compareVal: ScadValue
                    if let row = elem.asVector(), colNum < row.count {
                        compareVal = row[colNum]
                    } else {
                        compareVal = elem
                    }
                    if compareVal == matchVal {
                        indices.append(.number(Double(i)))
                        if numReturns > 0 && indices.count >= Int(numReturns) { break }
                    }
                }
                return .vector(indices)
            }
            return .vector([])
        },
        "version": { _ in
            return .vector([.number(2024), .number(1), .number(0)])
        },
        "version_num": { _ in
            return .number(20240100)
        },
        "parent_module": { _ in
            return .string("")
        }
    ]
}
