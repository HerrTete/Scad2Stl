import Foundation
import MetalKit
import simd
import Euclid

public struct CADUniforms {
    public var modelViewProjectionMatrix: simd_float4x4
    public var modelMatrix: simd_float4x4
    public var viewMatrix: simd_float4x4
    public var cameraPosition: SIMD3<Float>
    public var _padding1: Float = 0
    public var defaultColor: SIMD4<Float>
    public var wireColor: SIMD4<Float>
    public var showWireframe: Int32
    public var _padding2: SIMD3<Int32> = .zero
}

public struct CADVertex {
    public var position: SIMD3<Float>
    public var normal: SIMD3<Float>
    public var color: SIMD4<Float>
}

public struct LineVertex {
    public var position: SIMD3<Float>
    public var color: SIMD4<Float>
}

public final class MetalRenderer: NSObject, MTKViewDelegate {
    public let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private var pipelineState: MTLRenderPipelineState?
    private var linePipelineState: MTLRenderPipelineState?
    private var depthState: MTLDepthStencilState?
    
    // Mesh buffers
    private var vertexBuffer: MTLBuffer?
    private var vertexCount: Int = 0
    
    // Grid buffers
    private var gridVertexBuffer: MTLBuffer?
    private var gridVertexCount: Int = 0
    
    public var camera: Camera
    public var defaultObjectColor = SIMD4<Float>(0.92, 0.72, 0.22, 1.0) // Classic OpenSCAD gold/yellow
    public var backgroundColor = MTLClearColor(red: 0.18, green: 0.19, blue: 0.21, alpha: 1.0)
    
    public init?(device: MTLDevice, camera: Camera) {
        self.device = device
        self.camera = camera
        guard let queue = device.makeCommandQueue() else { return nil }
        self.commandQueue = queue
        super.init()
        
        setupPipeline()
        setupDepthState()
        buildGrid(size: 100, step: 10)
    }
    
    private func setupPipeline() {
        do {
            let library = try device.makeLibrary(source: MetalShaders.source, options: nil)
            
            // 1. Solid Mesh Pipeline
            let vertexDescriptor = MTLVertexDescriptor()
            // Position
            vertexDescriptor.attributes[0].format = .float3
            vertexDescriptor.attributes[0].offset = 0
            vertexDescriptor.attributes[0].bufferIndex = 0
            // Normal
            vertexDescriptor.attributes[1].format = .float3
            vertexDescriptor.attributes[1].offset = MemoryLayout<SIMD3<Float>>.stride
            vertexDescriptor.attributes[1].bufferIndex = 0
            // Color
            vertexDescriptor.attributes[2].format = .float4
            vertexDescriptor.attributes[2].offset = MemoryLayout<SIMD3<Float>>.stride * 2
            vertexDescriptor.attributes[2].bufferIndex = 0
            vertexDescriptor.layouts[0].stride = MemoryLayout<CADVertex>.stride
            
            let pipelineDesc = MTLRenderPipelineDescriptor()
            pipelineDesc.vertexFunction = library.makeFunction(name: "cadVertexShader")
            pipelineDesc.fragmentFunction = library.makeFunction(name: "cadFragmentShader")
            pipelineDesc.vertexDescriptor = vertexDescriptor
            pipelineDesc.colorAttachments[0].pixelFormat = .bgra8Unorm
            pipelineDesc.depthAttachmentPixelFormat = .depth32Float
            pipelineDesc.rasterSampleCount = 4
            
            self.pipelineState = try device.makeRenderPipelineState(descriptor: pipelineDesc)
            
            // 2. Line / Grid Pipeline
            let lineVertexDesc = MTLVertexDescriptor()
            lineVertexDesc.attributes[0].format = .float3
            lineVertexDesc.attributes[0].offset = 0
            lineVertexDesc.attributes[0].bufferIndex = 0
            lineVertexDesc.attributes[1].format = .float4
            lineVertexDesc.attributes[1].offset = MemoryLayout<SIMD3<Float>>.stride
            lineVertexDesc.attributes[1].bufferIndex = 0
            lineVertexDesc.layouts[0].stride = MemoryLayout<LineVertex>.stride
            
            let linePipelineDesc = MTLRenderPipelineDescriptor()
            linePipelineDesc.vertexFunction = library.makeFunction(name: "lineVertexShader")
            linePipelineDesc.fragmentFunction = library.makeFunction(name: "lineFragmentShader")
            linePipelineDesc.vertexDescriptor = lineVertexDesc
            linePipelineDesc.colorAttachments[0].pixelFormat = .bgra8Unorm
            linePipelineDesc.depthAttachmentPixelFormat = .depth32Float
            linePipelineDesc.rasterSampleCount = 4
            
            self.linePipelineState = try device.makeRenderPipelineState(descriptor: linePipelineDesc)
        } catch {
            print("Failed to initialize Metal pipeline: \(error)")
        }
    }
    
    private func setupDepthState() {
        let depthDesc = MTLDepthStencilDescriptor()
        depthDesc.depthCompareFunction = .lessEqual
        depthDesc.isDepthWriteEnabled = true
        self.depthState = device.makeDepthStencilState(descriptor: depthDesc)
    }
    
    public func updateMesh(_ mesh: Mesh) {
        // Smooth normals for curved surfaces while keeping sharp creases (> 45 deg) crisp
        let smoothedMesh = mesh.polygons.count < 60000 ? mesh.smoothingNormals(forAnglesGreaterThan: .degrees(45)) : mesh
        let triangles = smoothedMesh.triangulate().polygons
        var vertices: [CADVertex] = []
        vertices.reserveCapacity(triangles.count * 3)
        
        for tri in triangles {
            let pts = tri.vertices
            guard pts.count >= 3 else { continue }
            let planeNormal = tri.plane.normal
            
            var polyColor = SIMD4<Float>(0, 0, 0, 0)
            if let color = tri.material as? Euclid.Color {
                polyColor = SIMD4<Float>(Float(color.red), Float(color.green), Float(color.blue), Float(color.alpha))
            }
            
            for i in 0..<3 {
                let p = pts[i].position
                let vNorm = pts[i].normal
                let normal = (vNorm != .zero) ? vNorm : planeNormal
                let normSIMD = SIMD3<Float>(Float(normal.x), Float(normal.y), Float(normal.z))
                let posSIMD = SIMD3<Float>(Float(p.x), Float(p.y), Float(p.z))
                vertices.append(CADVertex(position: posSIMD, normal: normSIMD, color: polyColor))
            }
        }
        
        self.vertexCount = vertices.count
        if !vertices.isEmpty {
            self.vertexBuffer = device.makeBuffer(
                bytes: vertices,
                length: MemoryLayout<CADVertex>.stride * vertices.count,
                options: .storageModeShared
            )
        } else {
            self.vertexBuffer = nil
        }
    }
    
    private func buildGrid(size: Float = 100.0, step: Float = 10.0) {
        var lines: [LineVertex] = []
        let gridColor = SIMD4<Float>(0.35, 0.38, 0.42, 0.4)
        let mainAxisColor = SIMD4<Float>(0.5, 0.55, 0.6, 0.7)
        
        // Minor & major grid lines in XY plane
        var x = -size
        while x <= size + 1e-4 {
            let color = (abs(x) < 1e-4) ? mainAxisColor : gridColor
            lines.append(LineVertex(position: SIMD3<Float>(x, -size, 0), color: color))
            lines.append(LineVertex(position: SIMD3<Float>(x, size, 0), color: color))
            x += step
        }
        
        var y = -size
        while y <= size + 1e-4 {
            let color = (abs(y) < 1e-4) ? mainAxisColor : gridColor
            lines.append(LineVertex(position: SIMD3<Float>(-size, y, 0), color: color))
            lines.append(LineVertex(position: SIMD3<Float>(size, y, 0), color: color))
            y += step
        }
        
        // RGB Coordinate axes from origin
        let axisLen = size * 0.6
        // X = Red
        lines.append(LineVertex(position: .zero, color: SIMD4<Float>(0.9, 0.2, 0.2, 1.0)))
        lines.append(LineVertex(position: SIMD3<Float>(axisLen, 0, 0), color: SIMD4<Float>(0.9, 0.2, 0.2, 1.0)))
        // Y = Green
        lines.append(LineVertex(position: .zero, color: SIMD4<Float>(0.2, 0.85, 0.2, 1.0)))
        lines.append(LineVertex(position: SIMD3<Float>(0, axisLen, 0), color: SIMD4<Float>(0.2, 0.85, 0.2, 1.0)))
        // Z = Blue
        lines.append(LineVertex(position: .zero, color: SIMD4<Float>(0.2, 0.5, 0.95, 1.0)))
        lines.append(LineVertex(position: SIMD3<Float>(0, 0, axisLen), color: SIMD4<Float>(0.2, 0.5, 0.95, 1.0)))
        
        self.gridVertexCount = lines.count
        self.gridVertexBuffer = device.makeBuffer(
            bytes: lines,
            length: MemoryLayout<LineVertex>.stride * lines.count,
            options: .storageModeShared
        )
    }
    
    // MARK: - MTKViewDelegate
    
    public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        // Automatically handled on next draw
    }
    
    public func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable,
              let renderPassDesc = view.currentRenderPassDescriptor,
              let commandBuffer = commandQueue.makeCommandBuffer() else {
            return
        }
        
        renderPassDesc.colorAttachments[0].clearColor = backgroundColor
        renderPassDesc.colorAttachments[0].loadAction = .clear
        if view.sampleCount > 1 {
            renderPassDesc.colorAttachments[0].storeAction = .multisampleResolve
        } else {
            renderPassDesc.colorAttachments[0].storeAction = .store
        }
        
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDesc) else {
            return
        }
        
        if let depthState = depthState {
            encoder.setDepthStencilState(depthState)
        }
        
        let width = Float(view.drawableSize.width)
        let height = max(Float(view.drawableSize.height), 1.0)
        let aspect = width / height
        
        let vMat = camera.viewMatrix()
        let pMat = camera.projectionMatrix(aspect: aspect)
        let mvp = pMat * vMat
        
        var uniforms = CADUniforms(
            modelViewProjectionMatrix: mvp,
            modelMatrix: matrix_identity_float4x4,
            viewMatrix: vMat,
            cameraPosition: camera.cameraPosition,
            defaultColor: defaultObjectColor,
            wireColor: SIMD4<Float>(0.1, 0.1, 0.1, 0.8),
            showWireframe: camera.showWireframe ? 1 : 0
        )
        
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<CADUniforms>.stride, index: 1)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<CADUniforms>.stride, index: 1)
        
        // 1. Draw Grid & Axes
        if camera.showGrid, let linePipeline = linePipelineState, let gridBuf = gridVertexBuffer {
            encoder.setRenderPipelineState(linePipeline)
            encoder.setVertexBuffer(gridBuf, offset: 0, index: 0)
            encoder.drawPrimitives(type: .line, vertexStart: 0, vertexCount: gridVertexCount)
        }
        
        // 2. Draw Solid CAD Mesh
        if let solidPipeline = pipelineState, let vBuf = vertexBuffer, vertexCount > 0 {
            encoder.setRenderPipelineState(solidPipeline)
            encoder.setVertexBuffer(vBuf, offset: 0, index: 0)
            
            if camera.showWireframe {
                encoder.setTriangleFillMode(.lines)
            } else {
                encoder.setTriangleFillMode(.fill)
            }
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: vertexCount)
        }
        
        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}
