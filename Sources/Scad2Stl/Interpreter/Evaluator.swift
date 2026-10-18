import Foundation
import Euclid

public struct EvalError: Error, CustomStringConvertible, Sendable {
    public let message: String
    public let location: SourceLocation?
    
    public init(_ message: String, location: SourceLocation? = nil) {
        self.message = message
        self.location = location
    }
    
    public var description: String {
        if let loc = location {
            return "Line \(loc.line), Column \(loc.column): \(message)"
        }
        return message
    }
}

public final class Evaluator {
    public var consoleOutput: [String] = []
    public var errors: [EvalError] = []
    public var basePath: URL? = nil
    private var includedFiles: Set<String> = []
    
    public init(basePath: URL? = nil) {
        self.basePath = basePath
    }
    
    public func evaluate(program: Program, environment: Environment? = nil) -> Mesh {
        consoleOutput.removeAll()
        errors.removeAll()
        
        let rootEnv = environment ?? Environment()
        
        // Step 1: Pre-scan top-level assignments and definitions
        rootEnv.preScanAssignments(in: program.statements) { expr, env in
            self.evalExpression(expr, env: env)
        }
        
        // Step 2: Check for root modifiers (!)
        var activeStatements = program.statements
        let showOnlyStatements = program.statements.filter { stmt in
            if case .moduleCall(_, _, _, let modifier, _) = stmt, modifier == .showOnly {
                return true
            }
            return false
        }
        if !showOnlyStatements.isEmpty {
            activeStatements = showOnlyStatements
        }
        
        // Step 3: Evaluate top-level statements
        var geometries: [CSGGeometry] = []
        for stmt in activeStatements {
            let geom = evalStatement(stmt, env: rootEnv, passedChildren: [])
            if !geom.isEmpty {
                geometries.append(geom)
            }
        }
        
        // OpenSCAD implicitly unions all top-level objects
        let finalGeometry = CSGGeometry.union(geometries)
        return finalGeometry.toMesh()
    }
    
    // MARK: - Statements
    
    private func evalStatement(_ stmt: Statement, env: Environment, passedChildren: [CSGGeometry]) -> CSGGeometry {
        switch stmt {
        case .assignment, .functionDef, .moduleDef:
            // Already handled in pre-scan
            return .empty
            
        case .echoStatement(let args, _):
            let parts = args.map { arg -> String in
                let val = evalExpression(arg.value, env: env)
                if let name = arg.name {
                    return "\(name) = \(val.asString())"
                }
                return val.asString()
            }
            let output = "ECHO: " + parts.joined(separator: " ")
            consoleOutput.append(output)
            print(output)
            return .empty
            
        case .assertStatement(let cond, let msg, let loc):
            let condVal = evalExpression(cond, env: env)
            if !condVal.isTruthy {
                let msgStr = msg.map { evalExpression($0, env: env).asString() } ?? "Assertion failed"
                let err = EvalError(msgStr, location: loc)
                errors.append(err)
                consoleOutput.append("ERROR: \(err)")
            }
            return .empty
            
        case .includeDirective(let path, let loc):
            handleInclude(path: path, env: env, location: loc, isUse: false)
            return .empty
            
        case .useDirective(let path, let loc):
            handleInclude(path: path, env: env, location: loc, isUse: true)
            return .empty
            
        case .ifStatement(let cond, let thenBranch, let elseBranch, _):
            let condVal = evalExpression(cond, env: env)
            let branchEnv = env.createChild()
            if condVal.isTruthy {
                branchEnv.preScanAssignments(in: thenBranch) { expr, e in
                    self.evalExpression(expr, env: e)
                }
                var results: [CSGGeometry] = []
                for s in thenBranch {
                    let g = evalStatement(s, env: branchEnv, passedChildren: passedChildren)
                    if !g.isEmpty { results.append(g) }
                }
                return CSGGeometry.union(results)
            } else if let elseBranch = elseBranch {
                branchEnv.preScanAssignments(in: elseBranch) { expr, e in
                    self.evalExpression(expr, env: e)
                }
                var results: [CSGGeometry] = []
                for s in elseBranch {
                    let g = evalStatement(s, env: branchEnv, passedChildren: passedChildren)
                    if !g.isEmpty { results.append(g) }
                }
                return CSGGeometry.union(results)
            }
            return .empty
            
        case .forLoop(let variables, let body, _):
            return evalForLoop(bindings: variables, body: body, env: env, isIntersection: false, passedChildren: passedChildren)
            
        case .intersectionFor(let variables, let body, _):
            return evalForLoop(bindings: variables, body: body, env: env, isIntersection: true, passedChildren: passedChildren)
            
        case .moduleCall(let name, let args, let children, let modifier, let loc):
            // Check modifier
            if modifier == .disable {
                return .empty // * modifier: disabled
            }
            
            return evalModuleCall(name: name, args: args, children: children, modifier: modifier, env: env, passedChildren: passedChildren, location: loc)
        }
    }
    
    private func evalForLoop(bindings: [ForBinding], body: [Statement], env: Environment, isIntersection: Bool, passedChildren: [CSGGeometry]) -> CSGGeometry {
        guard let first = bindings.first else {
            var results: [CSGGeometry] = []
            for stmt in body {
                let g = evalStatement(stmt, env: env, passedChildren: passedChildren)
                if !g.isEmpty { results.append(g) }
            }
            return isIntersection ? CSGGeometry.intersection(results) : CSGGeometry.union(results)
        }
        
        let rangeVal = evalExpression(first.range, env: env)
        guard let values = rangeVal.asVector() else { return .empty }
        
        var iterationResults: [CSGGeometry] = []
        let remainingBindings = Array(bindings.dropFirst())
        
        for val in values {
            let loopEnv = env.createChild()
            loopEnv.set(first.name, val)
            loopEnv.preScanAssignments(in: body) { expr, e in
                self.evalExpression(expr, env: e)
            }
            
            let g = evalForLoop(bindings: remainingBindings, body: body, env: loopEnv, isIntersection: isIntersection, passedChildren: passedChildren)
            if !g.isEmpty {
                iterationResults.append(g)
            }
        }
        
        return isIntersection ? CSGGeometry.intersection(iterationResults) : CSGGeometry.union(iterationResults)
    }
    
    private func evalModuleCall(
        name: String,
        args: [CallArg],
        children: [Statement],
        modifier: GeometryModifier?,
        env: Environment,
        passedChildren: [CSGGeometry],
        location: SourceLocation
    ) -> CSGGeometry {
        // Special case: children()
        if name == "children" {
            let indexArg = args.first.map { evalExpression($0.value, env: env) }
            if let idxVal = indexArg?.asNumber() {
                let idx = Int(idxVal)
                if idx >= 0 && idx < passedChildren.count {
                    return passedChildren[idx]
                }
                return .empty
            }
            return CSGGeometry.union(passedChildren)
        }
        
        // Evaluate arguments
        var evaluatedArgs: [String: ScadValue] = [:]
        for (i, arg) in args.enumerated() {
            let val = evalExpression(arg.value, env: env)
            if let argName = arg.name {
                evaluatedArgs[argName] = val
            } else {
                evaluatedArgs["_pos\(i)"] = val
            }
        }
        
        // Check for special $ argument overrides
        let callEnv: Environment
        let specialArgs = evaluatedArgs.filter { $0.key.hasPrefix("$") }
        if !specialArgs.isEmpty {
            callEnv = env.createChild()
            for (k, v) in specialArgs {
                callEnv.set(k, v)
            }
        } else {
            callEnv = env
        }
        
        // Evaluate children of this module call
        var evaluatedChildren: [CSGGeometry] = []
        for childStmt in children {
            let childGeom = evalStatement(childStmt, env: callEnv, passedChildren: passedChildren)
            if !childGeom.isEmpty {
                evaluatedChildren.append(childGeom)
            }
        }
        
        var result: CSGGeometry = .empty
        
        // 1. Built-in Primitives
        switch name {
        case "cube":
            result = BuiltinModules.createCube(args: evaluatedArgs)
        case "sphere":
            result = BuiltinModules.createSphere(args: evaluatedArgs, env: callEnv)
        case "cylinder":
            result = BuiltinModules.createCylinder(args: evaluatedArgs, env: callEnv)
        case "polyhedron":
            result = BuiltinModules.createPolyhedron(args: evaluatedArgs)
        case "square":
            result = BuiltinModules.createSquare(args: evaluatedArgs)
        case "circle":
            result = BuiltinModules.createCircle(args: evaluatedArgs, env: callEnv)
        case "polygon":
            result = BuiltinModules.createPolygon(args: evaluatedArgs)
            
        // 2. Built-in CSG Booleans & Hull
        case "union":
            result = CSGGeometry.union(evaluatedChildren)
        case "difference":
            guard let first = evaluatedChildren.first else { return .empty }
            result = CSGGeometry.difference(first: first, subtracting: Array(evaluatedChildren.dropFirst()))
        case "intersection":
            result = CSGGeometry.intersection(evaluatedChildren)
        case "hull":
            result = BuiltinModules.createHull(children: evaluatedChildren)
            
        // 3. Transformations
        case "translate":
            let v = (evaluatedArgs["v"] ?? evaluatedArgs["_pos0"])?.asVector3() ?? .zero
            let childUnion = CSGGeometry.union(evaluatedChildren)
            result = childUnion.translated(by: v)
            
        case "rotate":
            let aArg = evaluatedArgs["a"] ?? evaluatedArgs["_pos0"]
            let vArg = evaluatedArgs["v"] ?? evaluatedArgs["_pos1"]
            let childUnion = CSGGeometry.union(evaluatedChildren)
            
            if let axis = vArg?.asVector3(), let deg = aArg?.asNumber() {
                // rotate around arbitrary axis
                let rot = Rotation(axis: axis, angle: .degrees(deg)) ?? .identity
                result = childUnion.rotated(by: rot)
            } else if let angles = aArg?.asDoubleArray(), angles.count >= 2 {
                // Euler angles [ax, ay, az] in degrees
                let ax = angles[0]
                let ay = angles[1]
                let az = angles.count > 2 ? angles[2] : 0.0
                // OpenSCAD rotation order: X then Y then Z
                let rot = Rotation.pitch(.degrees(ax)) * Rotation.yaw(.degrees(ay)) * Rotation.roll(.degrees(az))
                result = childUnion.rotated(by: rot)
            } else if let deg = aArg?.asNumber() {
                // 2D rotation around Z
                let rot = Rotation.roll(.degrees(deg))
                result = childUnion.rotated(by: rot)
            } else {
                result = childUnion
            }
            
        case "scale":
            let v = (evaluatedArgs["v"] ?? evaluatedArgs["_pos0"])?.asVector3() ?? Euclid.Vector(1, 1, 1)
            let childUnion = CSGGeometry.union(evaluatedChildren)
            result = childUnion.scaled(by: v)
            
        case "mirror":
            // In OpenSCAD, mirror([x, y, z]) mirrors across plane with normal [x,y,z]
            let n = (evaluatedArgs["v"] ?? evaluatedArgs["_pos0"])?.asVector3() ?? Euclid.Vector(1, 0, 0)
            let scaleVec = Euclid.Vector(
                abs(n.x) > 0.5 ? -1.0 : 1.0,
                abs(n.y) > 0.5 ? -1.0 : 1.0,
                abs(n.z) > 0.5 ? -1.0 : 1.0
            )
            let childUnion = CSGGeometry.union(evaluatedChildren)
            result = childUnion.scaled(by: scaleVec)
            
        case "color":
            let cArg = evaluatedArgs["c"] ?? evaluatedArgs["_pos0"] ?? .string("yellow")
            let color = BuiltinModules.parseColor(cArg)
            let childUnion = CSGGeometry.union(evaluatedChildren)
            result = childUnion.withColor(color)
            
        case "linear_extrude":
            result = BuiltinModules.linearExtrude(args: evaluatedArgs, children: evaluatedChildren)
        case "rotate_extrude":
            result = BuiltinModules.rotateExtrude(args: evaluatedArgs, children: evaluatedChildren, env: callEnv)
            
        // 5. Advanced Primitives, Transforms & CSG
        case "text":
            result = BuiltinModules.createText(args: evaluatedArgs)
        case "minkowski":
            result = BuiltinModules.createMinkowski(children: evaluatedChildren)
        case "multmatrix":
            result = BuiltinModules.multmatrix(args: evaluatedArgs, children: evaluatedChildren)
        case "resize":
            result = BuiltinModules.resize(args: evaluatedArgs, children: evaluatedChildren)
        case "offset":
            result = BuiltinModules.offset(args: evaluatedArgs, children: evaluatedChildren)
        case "projection":
            result = BuiltinModules.projection(args: evaluatedArgs, children: evaluatedChildren)
        case "surface":
            result = BuiltinModules.createSurface(args: evaluatedArgs, basePath: basePath)
        case "import":
            result = BuiltinModules.importFile(args: evaluatedArgs, basePath: basePath)
        case "render":
            result = BuiltinModules.render(args: evaluatedArgs, children: evaluatedChildren)
            
        default:
            // 5. User-Defined Module
            if let userModule = env.getModule(name) {
                let moduleEnv = env.createChild()
                moduleEnv.set("$children", .number(Double(evaluatedChildren.count)))
                
                // Bind parameters
                for (i, param) in userModule.params.enumerated() {
                    if let passedVal = evaluatedArgs[param.name] {
                        moduleEnv.set(param.name, passedVal)
                    } else if let passedPos = evaluatedArgs["_pos\(i)"] {
                        moduleEnv.set(param.name, passedPos)
                    } else if let defaultExpr = param.defaultValue {
                        let defaultVal = evalExpression(defaultExpr, env: moduleEnv)
                        moduleEnv.set(param.name, defaultVal)
                    } else {
                        moduleEnv.set(param.name, .undef)
                    }
                }
                
                moduleEnv.preScanAssignments(in: userModule.body) { expr, e in
                    self.evalExpression(expr, env: e)
                }
                
                var moduleResults: [CSGGeometry] = []
                for stmt in userModule.body {
                    let g = evalStatement(stmt, env: moduleEnv, passedChildren: evaluatedChildren)
                    if !g.isEmpty {
                        moduleResults.append(g)
                    }
                }
                result = CSGGeometry.union(moduleResults)
            } else {
                errors.append(EvalError("Unknown module '\(name)'", location: location))
                result = .empty
            }
        }
        
        // Handle debug highlight (#) or background (%) modifier
        if modifier == .highlight {
            result = result.withColor(Euclid.Color(red: 1.0, green: 0.2, blue: 0.2, alpha: 0.7))
        } else if modifier == .background {
            result = result.withColor(Euclid.Color(red: 0.7, green: 0.7, blue: 0.7, alpha: 0.4))
        }
        
        return result
    }
    
    // MARK: - Expressions
    
    public func evalExpression(_ expr: Expression, env: Environment) -> ScadValue {
        switch expr {
        case .number(let n):
            return .number(n)
        case .string(let s):
            return .string(s)
        case .bool(let b):
            return .bool(b)
        case .undef:
            return .undef
            
        case .variable(let name):
            return env.get(name)
            
        case .vector(let elements):
            let evaluated = elements.map { evalExpression($0, env: env) }
            return .vector(evaluated)
            
        case .range(let fromExpr, let stepExpr, let toExpr):
            guard let from = evalExpression(fromExpr, env: env).asNumber(),
                  let to = evalExpression(toExpr, env: env).asNumber() else {
                return .undef
            }
            let step = stepExpr.flatMap { evalExpression($0, env: env).asNumber() } ?? 1.0
            return .range(start: from, step: step, end: to)
            
        case .unary(let op, let sub):
            let val = evalExpression(sub, env: env)
            switch op {
            case .negate:
                if let num = val.asNumber() { return .number(-num) }
                if let vec = val.asVector() {
                    return .vector(vec.map { item in
                        if let n = item.asNumber() { return .number(-n) }
                        return .undef
                    })
                }
                return .undef
            case .not:
                return .bool(!val.isTruthy)
            case .plus:
                return val
            }
            
        case .binary(let leftExpr, let op, let rightExpr):
            return evalBinary(leftExpr: leftExpr, op: op, rightExpr: rightExpr, env: env)
            
        case .ternary(let condExpr, let thenExpr, let elseExpr):
            let condVal = evalExpression(condExpr, env: env)
            return condVal.isTruthy ? evalExpression(thenExpr, env: env) : evalExpression(elseExpr, env: env)
            
        case .subscriptAccess(let targetExpr, let indexExpr):
            let target = evalExpression(targetExpr, env: env)
            let indexVal = evalExpression(indexExpr, env: env)
            if let idx = indexVal.asNumber() {
                return target[Int(idx)]
            }
            return .undef
            
        case .memberAccess(let targetExpr, let member):
            let target = evalExpression(targetExpr, env: env)
            switch member {
            case "x": return target[0]
            case "y": return target[1]
            case "z": return target[2]
            default: return .undef
            }
            
        case .call(let name, let args):
            // Evaluate arguments
            var evaluatedArgs: [ScadValue] = []
            for arg in args {
                evaluatedArgs.append(evalExpression(arg.value, env: env))
            }
            
            // Check built-in functions
            if BuiltinFunctions.isBuiltin(name) {
                return BuiltinFunctions.call(name, args: evaluatedArgs)
            }
            
            // Check user-defined function
            if let fn = env.getFunction(name) {
                let fnEnv = env.createChild()
                for (i, param) in fn.params.enumerated() {
                    if i < evaluatedArgs.count {
                        fnEnv.set(param.name, evaluatedArgs[i])
                    } else if let defExpr = param.defaultValue {
                        fnEnv.set(param.name, evalExpression(defExpr, env: fnEnv))
                    } else {
                        fnEnv.set(param.name, .undef)
                    }
                }
                return evalExpression(fn.body, env: fnEnv)
            }
            
            return .undef
            
        case .functionLiteral(let params, let body):
            return .functionClosure(params: params, body: body)
            
        case .letExpr(let bindings, let body):
            let letEnv = env.createChild()
            for b in bindings {
                let val = evalExpression(b.value, env: letEnv)
                letEnv.set(b.name, val)
            }
            return evalExpression(body, env: letEnv)
            
        case .listComprehension(let elements):
            let result = evalListComprehension(elements: elements, env: env)
            return .vector(result)
            
        case .assertExpr(let cond, let msg, let body):
            let condVal = evalExpression(cond, env: env)
            if !condVal.isTruthy {
                let msgStr = msg.map { evalExpression($0, env: env).asString() } ?? "Assertion failed"
                errors.append(EvalError(msgStr))
            }
            return evalExpression(body, env: env)
            
        case .echoExpr(let args, let body):
            let parts = args.map { evalExpression($0.value, env: env).asString() }
            let output = "ECHO: " + parts.joined(separator: " ")
            consoleOutput.append(output)
            print(output)
            return evalExpression(body, env: env)
        }
    }
    
    private func evalBinary(leftExpr: Expression, op: BinaryOp, rightExpr: Expression, env: Environment) -> ScadValue {
        // Short-circuit logical operators
        if op == .and {
            let leftVal = evalExpression(leftExpr, env: env)
            if !leftVal.isTruthy { return .bool(false) }
            let rightVal = evalExpression(rightExpr, env: env)
            return .bool(rightVal.isTruthy)
        }
        if op == .or {
            let leftVal = evalExpression(leftExpr, env: env)
            if leftVal.isTruthy { return .bool(true) }
            let rightVal = evalExpression(rightExpr, env: env)
            return .bool(rightVal.isTruthy)
        }
        
        let left = evalExpression(leftExpr, env: env)
        let right = evalExpression(rightExpr, env: env)
        
        switch op {
        case .add:
            // Numbers add
            if let a = left.asNumber(), let b = right.asNumber() {
                return .number(a + b)
            }
            // Vector + Vector elementwise
            if let v1 = left.asVector(), let v2 = right.asVector() {
                let count = min(v1.count, v2.count)
                var result: [ScadValue] = []
                for i in 0..<count {
                    if let n1 = v1[i].asNumber(), let n2 = v2[i].asNumber() {
                        result.append(.number(n1 + n2))
                    } else {
                        result.append(.undef)
                    }
                }
                return .vector(result)
            }
            // Strings concatenate
            if case .string(let s1) = left {
                return .string(s1 + right.asString())
            }
            return .undef
            
        case .subtract:
            if let a = left.asNumber(), let b = right.asNumber() {
                return .number(a - b)
            }
            if let v1 = left.asVector(), let v2 = right.asVector() {
                let count = min(v1.count, v2.count)
                var result: [ScadValue] = []
                for i in 0..<count {
                    if let n1 = v1[i].asNumber(), let n2 = v2[i].asNumber() {
                        result.append(.number(n1 - n2))
                    } else {
                        result.append(.undef)
                    }
                }
                return .vector(result)
            }
            return .undef
            
        case .multiply:
            if let a = left.asNumber(), let b = right.asNumber() {
                return .number(a * b)
            }
            // Scalar * Vector
            if let s = left.asNumber(), let v = right.asVector() {
                return .vector(v.map { item in
                    if let n = item.asNumber() { return .number(s * n) }
                    return .undef
                })
            }
            // Vector * Scalar
            if let v = left.asVector(), let s = right.asNumber() {
                return .vector(v.map { item in
                    if let n = item.asNumber() { return .number(n * s) }
                    return .undef
                })
            }
            // Vector * Vector (Dot Product!)
            if let v1 = left.asVector(), let v2 = right.asVector() {
                let count = min(v1.count, v2.count)
                var dotSum: Double = 0
                for i in 0..<count {
                    if let n1 = v1[i].asNumber(), let n2 = v2[i].asNumber() {
                        dotSum += n1 * n2
                    }
                }
                return .number(dotSum)
            }
            return .undef
            
        case .divide:
            if let a = left.asNumber(), let b = right.asNumber() {
                if b == 0 { return .number(Double.nan) }
                return .number(a / b)
            }
            // Vector / Scalar
            if let v = left.asVector(), let s = right.asNumber() {
                if s == 0 { return .undef }
                return .vector(v.map { item in
                    if let n = item.asNumber() { return .number(n / s) }
                    return .undef
                })
            }
            return .undef
            
        case .modulo:
            if let a = left.asNumber(), let b = right.asNumber() {
                return .number(a.truncatingRemainder(dividingBy: b))
            }
            return .undef
            
        case .power:
            if let a = left.asNumber(), let b = right.asNumber() {
                return .number(pow(a, b))
            }
            return .undef
            
        case .equal:
            return .bool(left == right)
        case .notEqual:
            return .bool(left != right)
            
        case .less:
            if let a = left.asNumber(), let b = right.asNumber() { return .bool(a < b) }
            if case .string(let s1) = left, case .string(let s2) = right { return .bool(s1 < s2) }
            return .bool(false)
        case .lessEqual:
            if let a = left.asNumber(), let b = right.asNumber() { return .bool(a <= b) }
            if case .string(let s1) = left, case .string(let s2) = right { return .bool(s1 <= s2) }
            return .bool(false)
        case .greater:
            if let a = left.asNumber(), let b = right.asNumber() { return .bool(a > b) }
            if case .string(let s1) = left, case .string(let s2) = right { return .bool(s1 > s2) }
            return .bool(false)
        case .greaterEqual:
            if let a = left.asNumber(), let b = right.asNumber() { return .bool(a >= b) }
            if case .string(let s1) = left, case .string(let s2) = right { return .bool(s1 >= s2) }
            return .bool(false)
            
        case .and, .or:
            return .undef
        }
    }
    
    private func evalListComprehension(elements: [ListCompElement], env: Environment) -> [ScadValue] {
        var results: [ScadValue] = []
        for elem in elements {
            switch elem {
            case .expression(let expr):
                results.append(evalExpression(expr, env: env))
            case .each(let expr):
                let val = evalExpression(expr, env: env)
                if let v = val.asVector() {
                    results.append(contentsOf: v)
                } else {
                    results.append(val)
                }
            case .forLoop(let variables, let subElements):
                let loopResults = evalListCompFor(variables: variables, elements: subElements, env: env)
                results.append(contentsOf: loopResults)
            case .ifCond(let cond, let thenElem, let elseElem):
                let c = evalExpression(cond, env: env)
                if c.isTruthy {
                    results.append(contentsOf: evalListComprehension(elements: thenElem, env: env))
                } else if let elseElem = elseElem {
                    results.append(contentsOf: evalListComprehension(elements: elseElem, env: env))
                }
            case .letBinding(let bindings, let subElements):
                let letEnv = env.createChild()
                for b in bindings {
                    letEnv.set(b.name, evalExpression(b.value, env: letEnv))
                }
                results.append(contentsOf: evalListComprehension(elements: subElements, env: letEnv))
            }
        }
        return results
    }
    
    private func evalListCompFor(variables: [ForBinding], elements: [ListCompElement], env: Environment) -> [ScadValue] {
        guard let first = variables.first else {
            return evalListComprehension(elements: elements, env: env)
        }
        let rangeVal = evalExpression(first.range, env: env)
        guard let values = rangeVal.asVector() else { return [] }
        
        var results: [ScadValue] = []
        let remaining = Array(variables.dropFirst())
        for val in values {
            let loopEnv = env.createChild()
            loopEnv.set(first.name, val)
            results.append(contentsOf: evalListCompFor(variables: remaining, elements: elements, env: loopEnv))
        }
        return results
    }
    
    // MARK: - Include & Use
    
    private func handleInclude(path: String, env: Environment, location: SourceLocation, isUse: Bool) {
        guard !includedFiles.contains(path) else { return }
        includedFiles.insert(path)
        
        let fileURL: URL
        if let base = basePath {
            fileURL = base.appendingPathComponent(path)
        } else {
            fileURL = URL(fileURLWithPath: path)
        }
        
        guard let source = try? String(contentsOf: fileURL, encoding: .utf8) else {
            consoleOutput.append("WARNING: Could not open file \(path)")
            return
        }
        
        let parser = Parser(source: source)
        let prog = parser.parse()
        
        let fileEnv = isUse ? env.createChild() : env
        fileEnv.preScanAssignments(in: prog.statements) { expr, e in
            self.evalExpression(expr, env: e)
        }
        
        if isUse {
            // Only export modules and functions to caller
            // In OpenSCAD, 'use' exposes modules and functions, but not variables or top-level geometry!
        }
    }
}
