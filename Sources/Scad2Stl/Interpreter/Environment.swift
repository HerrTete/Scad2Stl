import Foundation

public final class Environment {
    public let parent: Environment?
    private var variables: [String: ScadValue] = [:]
    private var functions: [String: (params: [ParamDef], body: Expression)] = [:]
    private var modules: [String: (params: [ParamDef], body: [Statement])] = [:]
    
    public init(parent: Environment? = nil) {
        self.parent = parent
        if parent == nil {
            // Root environment defaults for OpenSCAD special variables
            variables["$fn"] = .number(0)
            variables["$fa"] = .number(12)
            variables["$fs"] = .number(2)
            variables["$t"] = .number(0)
            variables["$preview"] = .bool(true)
            variables["$children"] = .number(0)
            variables["PI"] = .number(Double.pi)
        }
    }
    
    public func createChild() -> Environment {
        return Environment(parent: self)
    }
    
    // MARK: - Variables
    
    public func set(_ name: String, _ value: ScadValue) {
        variables[name] = value
    }
    
    public func get(_ name: String) -> ScadValue {
        // If it starts with $, lookup dynamically up the parent chain
        if name.hasPrefix("$") {
            if let val = variables[name] {
                return val
            }
            return parent?.get(name) ?? .undef
        }
        
        // Regular lexical lookup
        if let val = variables[name] {
            return val
        }
        return parent?.get(name) ?? .undef
    }
    
    // Pre-scan statements in a scope block for "last-assignment-wins"
    public func preScanAssignments(in statements: [Statement], evaluator: (Expression, Environment) -> ScadValue) {
        for stmt in statements {
            switch stmt {
            case .assignment(let name, let valueExpr, _):
                let val = evaluator(valueExpr, self)
                set(name, val)
            case .moduleDef(let name, let params, let body, _):
                setModule(name, params: params, body: body)
            case .functionDef(let name, let params, let body, _):
                setFunction(name, params: params, body: body)
            default:
                break
            }
        }
    }
    
    // MARK: - Functions
    
    public func setFunction(_ name: String, params: [ParamDef], body: Expression) {
        functions[name] = (params, body)
    }
    
    public func getFunction(_ name: String) -> (params: [ParamDef], body: Expression)? {
        if let f = functions[name] {
            return f
        }
        return parent?.getFunction(name)
    }
    
    // MARK: - Modules
    
    public func setModule(_ name: String, params: [ParamDef], body: [Statement]) {
        modules[name] = (params, body)
    }
    
    public func getModule(_ name: String) -> (params: [ParamDef], body: [Statement])? {
        if let m = modules[name] {
            return m
        }
        return parent?.getModule(name)
    }
}
