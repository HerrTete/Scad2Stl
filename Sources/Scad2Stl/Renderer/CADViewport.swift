import SwiftUI
import MetalKit
import Euclid
import Combine

public final class CADInteractionView: NSView {
    public let mtkView: MTKView
    public var renderer: MetalRenderer?
    private var lastMouseLocation: NSPoint = .zero
    
    public init(renderer: MetalRenderer) {
        self.renderer = renderer
        self.mtkView = MTKView(frame: .zero, device: renderer.device)
        super.init(frame: .zero)
        
        mtkView.delegate = renderer
        mtkView.colorPixelFormat = .bgra8Unorm
        mtkView.depthStencilPixelFormat = .depth32Float
        mtkView.sampleCount = 4
        mtkView.isPaused = true
        mtkView.enableSetNeedsDisplay = true
        mtkView.autoresizingMask = [.width, .height]
        
        addSubview(mtkView)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func resizeSubviews(withOldSize oldSize: NSSize) {
        super.resizeSubviews(withOldSize: oldSize)
        mtkView.frame = bounds
    }
    
    public override var acceptsFirstResponder: Bool {
        return true
    }
    
    public func requestRedraw() {
        mtkView.needsDisplay = true
        mtkView.setNeedsDisplay(mtkView.bounds)
    }
    
    // MARK: - Mouse Events (Orbit & Pan)
    
    public override func mouseDown(with event: NSEvent) {
        lastMouseLocation = convert(event.locationInWindow, from: nil)
    }
    
    public override func mouseDragged(with event: NSEvent) {
        let currentLocation = convert(event.locationInWindow, from: nil)
        let deltaX = Float(currentLocation.x - lastMouseLocation.x)
        let deltaY = Float(currentLocation.y - lastMouseLocation.y)
        lastMouseLocation = currentLocation
        
        guard let camera = renderer?.camera else { return }
        
        if event.modifierFlags.contains(.shift) {
            // Pan with Shift+Left Drag
            camera.pan(deltaX: deltaX, deltaY: deltaY)
        } else {
            // Orbit with Left Drag
            camera.orbit(deltaYaw: deltaX * 0.5, deltaPitch: deltaY * 0.5)
        }
        requestRedraw()
    }
    
    public override func rightMouseDown(with event: NSEvent) {
        lastMouseLocation = convert(event.locationInWindow, from: nil)
    }
    
    public override func rightMouseDragged(with event: NSEvent) {
        let currentLocation = convert(event.locationInWindow, from: nil)
        let deltaX = Float(currentLocation.x - lastMouseLocation.x)
        let deltaY = Float(currentLocation.y - lastMouseLocation.y)
        lastMouseLocation = currentLocation
        
        guard let camera = renderer?.camera else { return }
        // Pan with Right Drag
        camera.pan(deltaX: deltaX, deltaY: deltaY)
        requestRedraw()
    }
    
    public override func otherMouseDown(with event: NSEvent) {
        lastMouseLocation = convert(event.locationInWindow, from: nil)
    }
    
    public override func otherMouseDragged(with event: NSEvent) {
        // Middle Mouse Drag: Pan
        let currentLocation = convert(event.locationInWindow, from: nil)
        let deltaX = Float(currentLocation.x - lastMouseLocation.x)
        let deltaY = Float(currentLocation.y - lastMouseLocation.y)
        lastMouseLocation = currentLocation
        
        guard let camera = renderer?.camera else { return }
        camera.pan(deltaX: deltaX, deltaY: deltaY)
        requestRedraw()
    }
    
    // MARK: - Zooming
    
    public override func scrollWheel(with event: NSEvent) {
        guard let camera = renderer?.camera else { return }
        let delta = Float(event.scrollingDeltaY)
        camera.zoom(delta: delta)
        requestRedraw()
    }
    
    public override func magnify(with event: NSEvent) {
        guard let camera = renderer?.camera else { return }
        let factor = Float(event.magnification)
        camera.zoom(delta: factor * 40.0)
        requestRedraw()
    }
}

// MARK: - SwiftUI Representable
public struct CADViewportView: NSViewRepresentable {
    public let mesh: Mesh
    @ObservedObject public var camera: Camera
    
    public init(mesh: Mesh, camera: Camera) {
        self.mesh = mesh
        self.camera = camera
    }
    
    public func makeNSView(context: Context) -> CADInteractionView {
        guard let device = MTLCreateSystemDefaultDevice(),
              let renderer = MetalRenderer(device: device, camera: camera) else {
            fatalError("Metal is not supported on this Mac")
        }
        renderer.updateMesh(mesh)
        let view = CADInteractionView(renderer: renderer)
        context.coordinator.interactionView = view
        context.coordinator.renderer = renderer
        context.coordinator.cachedMesh = mesh
        context.coordinator.attach(camera: camera, view: view)
        return view
    }
    
    public func updateNSView(_ nsView: CADInteractionView, context: Context) {
        if let renderer = context.coordinator.renderer {
            context.coordinator.attach(camera: camera, view: nsView)
            renderer.camera = camera
            if context.coordinator.cachedMesh != mesh {
                renderer.updateMesh(mesh)
                context.coordinator.cachedMesh = mesh
            }
            nsView.requestRedraw()
        }
    }
    
    public func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    public final class Coordinator {
        public var interactionView: CADInteractionView?
        public var renderer: MetalRenderer?
        public var cachedMesh: Mesh?
        private var cameraCancellable: AnyCancellable?
        private weak var observedCamera: Camera?
        
        public func attach(camera: Camera, view: CADInteractionView) {
            guard camera !== observedCamera else { return }
            observedCamera = camera
            cameraCancellable = camera.objectWillChange
                .receive(on: RunLoop.main)
                .sink { [weak view] _ in
                    view?.requestRedraw()
                }
        }
    }
}
