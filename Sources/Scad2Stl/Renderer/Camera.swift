import Foundation
import simd
import Euclid

public final class Camera: ObservableObject {
    @Published public var target: SIMD3<Float> = .zero
    @Published public var distance: Float = 60.0
    @Published public var yaw: Float = -45.0   // degrees
    @Published public var pitch: Float = 30.0  // degrees
    @Published public var fov: Float = 45.0    // degrees
    @Published public var isOrthographic: Bool = false
    @Published public var showWireframe: Bool = false
    @Published public var showGrid: Bool = true
    
    public init() {}
    
    public func reset() {
        target = .zero
        distance = 60.0
        yaw = -45.0
        pitch = 30.0
    }
    
    public func fit(bounds: Bounds) {
        guard !bounds.isEmpty,
              bounds.min.x.isFinite, bounds.max.x.isFinite,
              bounds.min.y.isFinite, bounds.max.y.isFinite,
              bounds.min.z.isFinite, bounds.max.z.isFinite else {
            reset()
            return
        }
        let center = (bounds.min + bounds.max) / 2.0
        target = SIMD3<Float>(Float(center.x), Float(center.y), Float(center.z))
        
        let size = bounds.max - bounds.min
        let maxDim = max(size.x, max(size.y, size.z))
        let radius = Float(max(maxDim, 10.0))
        distance = radius * 2.2
    }
    
    public func orbit(deltaYaw: Float, deltaPitch: Float) {
        yaw += deltaYaw
        pitch = min(89.0, max(-89.0, pitch + deltaPitch))
    }
    
    public func pan(deltaX: Float, deltaY: Float) {
        // Compute camera right and up vectors in world coordinates
        let yawRad = yaw * .pi / 180.0
        let pitchRad = pitch * .pi / 180.0
        
        let forward = SIMD3<Float>(
            cos(pitchRad) * sin(yawRad),
            cos(pitchRad) * cos(yawRad),
            sin(pitchRad)
        )
        let worldUp = SIMD3<Float>(0, 0, 1)
        var right = simd_cross(forward, worldUp)
        if simd_length_squared(right) < 1e-4 {
            right = SIMD3<Float>(1, 0, 0)
        } else {
            right = simd_normalize(right)
        }
        let up = simd_normalize(simd_cross(right, forward))
        
        let factor = distance * 0.002
        target += (-right * deltaX + up * deltaY) * factor
    }
    
    public func zoom(delta: Float) {
        let zoomFactor = exp(-delta * 0.003)
        distance = max(1.0, min(2000.0, distance * zoomFactor))
    }
    
    public func viewMatrix() -> simd_float4x4 {
        let yawRad = yaw * .pi / 180.0
        let pitchRad = pitch * .pi / 180.0
        
        // Eye position relative to target (Z is up in OpenSCAD CAD coordinates!)
        let offset = SIMD3<Float>(
            distance * cos(pitchRad) * sin(yawRad),
            distance * cos(pitchRad) * -cos(yawRad),
            distance * sin(pitchRad)
        )
        let eye = target + offset
        let up = SIMD3<Float>(0, 0, 1)
        
        return simd_float4x4.lookAt(eye: eye, target: target, up: up)
    }
    
    public func projectionMatrix(aspect: Float) -> simd_float4x4 {
        if isOrthographic {
            let halfH = distance * 0.4
            let halfW = halfH * aspect
            return simd_float4x4.ortho(left: -halfW, right: halfW, bottom: -halfH, top: halfH, near: 0.1, far: 5000.0)
        } else {
            return simd_float4x4.perspective(fovDegrees: fov, aspect: aspect, near: 0.1, far: 5000.0)
        }
    }
    
    public var cameraPosition: SIMD3<Float> {
        let yawRad = yaw * .pi / 180.0
        let pitchRad = pitch * .pi / 180.0
        let offset = SIMD3<Float>(
            distance * cos(pitchRad) * sin(yawRad),
            distance * cos(pitchRad) * -cos(yawRad),
            distance * sin(pitchRad)
        )
        return target + offset
    }
}

// MARK: - SIMD Matrix Helpers
public extension simd_float4x4 {
    static func lookAt(eye: SIMD3<Float>, target: SIMD3<Float>, up: SIMD3<Float>) -> simd_float4x4 {
        let zAxis = simd_normalize(eye - target)
        var xAxis = simd_cross(up, zAxis)
        if simd_length_squared(xAxis) < 1e-4 {
            xAxis = SIMD3<Float>(1, 0, 0)
        } else {
            xAxis = simd_normalize(xAxis)
        }
        let yAxis = simd_cross(zAxis, xAxis)
        
        return simd_float4x4(
            SIMD4<Float>(xAxis.x, yAxis.x, zAxis.x, 0),
            SIMD4<Float>(xAxis.y, yAxis.y, zAxis.y, 0),
            SIMD4<Float>(xAxis.z, yAxis.z, zAxis.z, 0),
            SIMD4<Float>(-simd_dot(xAxis, eye), -simd_dot(yAxis, eye), -simd_dot(zAxis, eye), 1)
        )
    }
    
    static func perspective(fovDegrees: Float, aspect: Float, near: Float, far: Float) -> simd_float4x4 {
        let fovRad = fovDegrees * .pi / 180.0
        let yScale = 1.0 / tan(fovRad * 0.5)
        let xScale = yScale / aspect
        let zRange = near - far
        let zScale = (far) / zRange
        let wzScale = (near * far) / zRange
        
        return simd_float4x4(
            SIMD4<Float>(xScale, 0, 0, 0),
            SIMD4<Float>(0, yScale, 0, 0),
            SIMD4<Float>(0, 0, zScale, -1),
            SIMD4<Float>(0, 0, wzScale, 0)
        )
    }
    
    static func ortho(left: Float, right: Float, bottom: Float, top: Float, near: Float, far: Float) -> simd_float4x4 {
        let r_l = right - left
        let t_b = top - bottom
        let f_n = far - near
        
        return simd_float4x4(
            SIMD4<Float>(2.0 / r_l, 0, 0, 0),
            SIMD4<Float>(0, 2.0 / t_b, 0, 0),
            SIMD4<Float>(0, 0, -1.0 / f_n, 0),
            SIMD4<Float>(-(right + left) / r_l, -(top + bottom) / t_b, -near / f_n, 1)
        )
    }
}
