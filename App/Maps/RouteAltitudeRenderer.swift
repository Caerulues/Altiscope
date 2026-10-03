import MapKit
import MetalKit

/// Transparent, non-interactive XYZ geometry over a flat-elevation MKMapView.
/// MapKit retains its gestures, location marker, tiles and attribution.
final class RouteAltitudeRenderer: NSObject, MTKViewDelegate {
    struct Vertex {
        var position: SIMD4<Float>
        var color: SIMD4<Float>
        var other: SIMD4<Float>
    }
    struct Uniforms {
        var u: SIMD4<Float>
        var v: SIMD4<Float>
        var w: SIMD4<Float>
        var viewport: SIMD4<Float>
    }
    let view: MTKView
    private let queue: MTLCommandQueue
    private let fillPipeline: MTLRenderPipelineState
    private let linePipeline: MTLRenderPipelineState
    private let fillDepth: MTLDepthStencilState
    private let lineDepth: MTLDepthStencilState
    weak var map: MKMapView?
    var statusChanged: ((Bool, String) -> Void)?
    var projectionUpdated: (() -> Void)?
    var scene = RouteScene(points: [], altitudeReference: nil)
    private var fills: MTLBuffer?, lines: MTLBuffer?, dots: MTLBuffer?
    private var fillCount = 0, lineCount = 0, dotCount = 0
    private var triangleCenters: [SIMD3<Double>] = []
    private var sortedIndices: MTLBuffer?
    private var sortedDepth: SIMD4<Double>?
    #if DEBUG
    private var diagnosticStart: TimeInterval?
    private var diagnosticFrames = 0
    private var diagnosticCPU: TimeInterval = 0
    private var diagnosticMaxCPU: TimeInterval = 0
    #endif
    private var lastStatus = ""
    private(set) var ready = false
    private(set) var projection: RouteProjection?
    private var offset = SIMD2<Double>.zero
    var detailView = false
    var enabled = false {
        didSet {
            view.isHidden = !enabled; view.isPaused = !enabled
            if !enabled { projection = nil; report(false, "") }
        }
    }

    init?(map: MKMapView) {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else { return nil }
        let view = MTKView(frame: .zero, device: device)
        view.isOpaque = false; view.backgroundColor = .clear
        view.clearColor = MTLClearColorMake(0, 0, 0, 0)
        view.colorPixelFormat = .bgra8Unorm; view.depthStencilPixelFormat = .depth32Float
        view.isUserInteractionEnabled = false; view.isAccessibilityElement = false
        view.preferredFramesPerSecond = 30; view.isPaused = true; view.isHidden = true
        do {
            let library = try device.makeLibrary(source: Self.shader, options: nil)
            func pipeline(_ vertex: String) throws -> MTLRenderPipelineState {
                let descriptor = MTLRenderPipelineDescriptor()
                descriptor.vertexFunction = library.makeFunction(name: vertex)
                descriptor.fragmentFunction = library.makeFunction(name: "routeFragment")
                descriptor.colorAttachments[0].pixelFormat = view.colorPixelFormat
                descriptor.depthAttachmentPixelFormat = view.depthStencilPixelFormat
                let blend = descriptor.colorAttachments[0]!
                blend.isBlendingEnabled = true
                blend.sourceRGBBlendFactor = .sourceAlpha; blend.destinationRGBBlendFactor = .oneMinusSourceAlpha
                blend.sourceAlphaBlendFactor = .one; blend.destinationAlphaBlendFactor = .oneMinusSourceAlpha
                return try device.makeRenderPipelineState(descriptor: descriptor)
            }
            fillPipeline = try pipeline("routeVertex")
            linePipeline = try pipeline("strokeVertex")
        } catch { return nil }
        let depth = MTLDepthStencilDescriptor(); depth.depthCompareFunction = .lessEqual
        depth.isDepthWriteEnabled = false
        guard let fillDepth = device.makeDepthStencilState(descriptor: depth) else { return nil }
        depth.isDepthWriteEnabled = true
        guard let lineDepth = device.makeDepthStencilState(descriptor: depth) else { return nil }
        self.view = view; self.queue = queue; self.map = map
        self.fillDepth = fillDepth; self.lineDepth = lineDepth
        super.init(); view.delegate = self
    }
    func update(points: [TrackPoint], altitudeReference: String?, heightScale: Double = RouteScene.heightScale) {
        scene = RouteScene(points: points, altitudeReference: altitudeReference, heightScale: heightScale)
        var fillVertices: [Vertex] = [], lineVertices: [Vertex] = []
        func vertex(_ position: SIMD3<Double>, color: SIMD4<Float>, other: SIMD3<Double>? = nil, side: Float = 0) -> Vertex {
            Vertex(position: SIMD4(Float(position.x),Float(position.y),Float(position.z),1), color: color,
                   other: SIMD4(Float(other?.x ?? 0),Float(other?.y ?? 0),Float(other?.z ?? 0),side))
        }
        func color(_ value: RouteScene.Vertex, alpha: Float) -> SIMD4<Float> {
            let hex = RouteAltitudeStyle.colorHex(value.position.z / scene.altitudeScale)
            return SIMD4(Float((hex >> 16) & 255)/255, Float((hex >> 8) & 255)/255, Float(hex & 255)/255, alpha)
        }
        for edge in scene.edges {
            let a = edge.a.position, b = edge.b.position
            let bottomA = SIMD3(a.x,a.y,0), bottomB = SIMD3(b.x,b.y,0)
            let alpha: Float = edge.estimated ? 0.12 : 0.23
            let ca = color(edge.a, alpha: alpha), cb = color(edge.b, alpha: alpha)
            fillVertices += [vertex(a,color:ca),vertex(bottomA,color:ca),vertex(b,color:cb),
                             vertex(b,color:cb),vertex(bottomA,color:ca),vertex(bottomB,color:cb)]
            // Dash in metric geometry, not by omitting every other input sample.
            let length = sqrt((b.x-a.x)*(b.x-a.x)+(b.y-a.y)*(b.y-a.y)+(b.z-a.z)*(b.z-a.z))
            let pieces = edge.estimated ? min(32, max(2, Int(ceil(length/20)))) : 1
            for index in 0..<pieces where !edge.estimated || index % 2 == 0 {
                let t0 = Double(index)/Double(pieces), t1 = Double(index+1)/Double(pieces)
                let p = a+(b-a)*t0, q = a+(b-a)*t1
                let start = color(edge.a, alpha: 1), end = color(edge.b, alpha: 1)
                lineVertices += [vertex(p,color:start,other:q,side:1),vertex(p,color:start,other:q,side:-1),vertex(q,color:end,other:p,side:-1),
                                 vertex(q,color:end,other:p,side:-1),vertex(p,color:start,other:q,side:-1),vertex(q,color:end,other:p,side:1)]
            }
        }
        let pointVertices = scene.vertices.map { vertex($0.position, color: color($0, alpha: 1)) }
        func buffer(_ vertices: [Vertex]) -> MTLBuffer? {
            guard !vertices.isEmpty else { return nil }
            return view.device?.makeBuffer(bytes: vertices, length: MemoryLayout<Vertex>.stride * vertices.count, options: .storageModeShared)
        }
        triangleCenters = stride(from:0,to:fillVertices.count,by:3).map { index in
            let center = (fillVertices[index].position+fillVertices[index+1].position+fillVertices[index+2].position)/3
            return SIMD3(Double(center.x),Double(center.y),Double(center.z))
        }
        sortedDepth = nil; sortedIndices = nil
        fills = buffer(fillVertices); lines = buffer(lineVertices); dots = buffer(pointVertices)
        fillCount = fillVertices.count; lineCount = lineVertices.count; dotCount = pointVertices.count
    }
    private func report(_ active: Bool, _ message: String) {
        ready = active
        guard message != lastStatus else { return }
        lastStatus = message; statusChanged?(active, message)
    }
    /// Recalibrate from public coordinate conversion each frame, including animated camera changes.
    private func calibrate() -> RouteProjection? {
        guard let map, map.bounds.width > 1, map.bounds.height > 1,
              abs(map.centerCoordinate.latitude) < 80, map.camera.pitch < 75 else { return nil }
        let origin = MKMapPoint(map.centerCoordinate)
        let units = scene.metersPerMapPoint
        guard units > 0 else { return nil }
        let span = max(100, min(map.visibleMapRect.width, map.visibleMapRect.height) * 0.13)
        let ground = [SIMD2(-span,-span), SIMD2(span,-span), SIMD2(span,span), SIMD2(-span,span)]
        let screen = ground.map { p -> SIMD2<Double> in
            let coordinate = MKMapPoint(x: origin.x+p.x, y: origin.y+p.y).coordinate
            let point = map.convert(coordinate, toPointTo: map)
            return SIMD2(Double(point.x), Double(point.y))
        }
        guard let projection = RouteProjection.calibrate(ground: ground.map { $0*units }, screen: screen,
                viewport: SIMD2(Double(map.bounds.width),Double(map.bounds.height)), cameraAltitude: map.camera.altitude) else { return nil }
        // A globe or a changed MapKit projection must never be approximated as a trustworthy plane.
        for delta in [SIMD2<Double>.zero, SIMD2(span*2,0), SIMD2(0,span*2), SIMD2(-span*2,-span)] {
            let actual = map.convert(MKMapPoint(x: origin.x+delta.x, y: origin.y+delta.y).coordinate, toPointTo: map)
            guard let expected = projection.screen(SIMD3(delta.x*units,delta.y*units,0)),
                  hypot(expected.x-Double(actual.x), expected.y-Double(actual.y)) < 1.5 else { return nil }
        }
        let anchor = MKMapPoint(CLLocationCoordinate2D(latitude: scene.anchor.latitude, longitude: scene.anchor.longitude))
        offset = SIMD2(RouteScene.wrappedDelta(anchor.x-origin.x)*units, (anchor.y-origin.y)*units)
        // Check all visible ground vertices too; calibration is local, not a global MapKit contract.
        for vertex in scene.vertices {
            let point = vertex.point.coordinate
            let actual = map.convert(CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude), toPointTo: map)
            if map.bounds.insetBy(dx: -40, dy: -40).contains(actual) {
                guard let expected = projection.screen(SIMD3(vertex.position.x+offset.x,vertex.position.y+offset.y,0)),
                      hypot(expected.x-Double(actual.x),expected.y-Double(actual.y)) < 2 else { return nil }
            }
        }
        return projection
    }
    func projected(_ vertex: RouteScene.Vertex) -> CGPoint? {
        guard ready, let p = projection?.screen(SIMD3(vertex.position.x+offset.x,vertex.position.y+offset.y,vertex.position.z)) else { return nil }
        return CGPoint(x: p.x, y: p.y)
    }
    func nearest(to point: CGPoint) -> TrackPoint? {
        var distance = 28.0, selected: TrackPoint?
        for vertex in scene.vertices {
            if let screen = projected(vertex) {
                let delta = hypot(screen.x-point.x,screen.y-point.y)
                if delta < distance { distance = delta; selected = vertex.point }
            }
        }
        return selected
    }
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
    func draw(in view: MTKView) {
        #if DEBUG
        let cpuStart = ProcessInfo.processInfo.systemUptime
        defer { recordDiagnosticFrame(start: cpuStart) }
        #endif
        guard enabled, let pass = view.currentRenderPassDescriptor, let drawable = view.currentDrawable,
              let command = queue.makeCommandBuffer(), let encoder = command.makeRenderCommandEncoder(descriptor: pass) else { return }
        defer { encoder.endEncoding(); command.present(drawable); command.commit() }
        guard scene.hasKnownReference else { projection = nil; report(false, "2D · 高度基准未知，未生成幕帘"); return }
        guard !scene.vertices.isEmpty else { projection = nil; report(false, "2D · 暂无有效高度"); return }
        guard (lineCount == 0 || lines != nil), (dotCount == 0 || dots != nil), (fillCount == 0 || fills != nil) else {
            projection = nil; report(false, "2D · 三维资源不足"); return
        }
        guard let projection = calibrate() else { self.projection = nil; report(false, "2D · 当前视角无法可靠对齐，请放大或降低倾角"); return }
        self.projection = projection
        DispatchQueue.main.async { [weak self] in self?.projectionUpdated?() }
        if let map, map.camera.pitch < 10 {
            report(true, "俯视全览 · 当前缩放限制倾角，放大后可查看立体高度")
        } else {
            let mode = detailView ? "3D 局部" : "3D"
            report(true, scene.altitudeScale == 1
                ? "\(mode) · 真实比例 ×1 · 点选轨迹查看海拔"
                : "\(mode) · 高度放大 ×\(Int(scene.altitudeScale)) · 海拔读数为真实值")
        }
        func shifted(_ row: SIMD4<Double>) -> SIMD4<Float> {
            SIMD4(Float(row.x),Float(row.y),Float(row.z),Float(row.w+row.x*offset.x+row.y*offset.y))
        }
        var uniforms = Uniforms(u:shifted(projection.u),v:shifted(projection.v),w:shifted(projection.w),
                                viewport:SIMD4(Float(projection.viewport.x),Float(projection.viewport.y),0,0))
        encoder.setVertexBytes(&uniforms,length:MemoryLayout<Uniforms>.stride,index:1)
        encoder.setCullMode(.none)
        // Opaque main line writes depth; translucent curtains test against it, without hiding it.
        if let lines {
            encoder.setRenderPipelineState(linePipeline); encoder.setDepthStencilState(lineDepth)
            encoder.setVertexBuffer(lines,offset:0,index:0); encoder.drawPrimitives(type:.triangle,vertexStart:0,vertexCount:lineCount)
        }
        if let dots {
            encoder.setRenderPipelineState(fillPipeline); encoder.setDepthStencilState(lineDepth)
            encoder.setVertexBuffer(dots,offset:0,index:0); encoder.drawPrimitives(type:.point,vertexStart:0,vertexCount:dotCount)
        }
        if let fills {
            // Back-to-front transparency follows camera depth, not the original sample order.
            if sortedDepth != projection.w {
                let row = projection.w
                func depth(_ index: Int) -> Double {
                    let p = triangleCenters[index]; return row.x*p.x+row.y*p.y+row.z*p.z
                }
                let order = triangleCenters.indices.sorted { depth($0) > depth($1) }
                let indices: [UInt32] = order.flatMap { [UInt32($0*3), UInt32($0*3+1), UInt32($0*3+2)] }
                sortedIndices = view.device?.makeBuffer(bytes:indices,length:MemoryLayout<UInt32>.stride*indices.count,options:.storageModeShared)
                sortedDepth = row
            }
            encoder.setRenderPipelineState(fillPipeline); encoder.setDepthStencilState(fillDepth)
            encoder.setVertexBuffer(fills,offset:0,index:0)
            if let sortedIndices {
                encoder.drawIndexedPrimitives(type:.triangle,indexCount:fillCount,indexType:.uint32,indexBuffer:sortedIndices,indexBufferOffset:0)
            }
        }
    }
    #if DEBUG
    /// Explicit QA launch only; aggregate performance numbers contain no track coordinates.
    private func recordDiagnosticFrame(start: TimeInterval) {
        guard enabled, ready, ProcessInfo.processInfo.arguments.contains("--demo-altitude"), diagnosticFrames < 180 else { return }
        let end = ProcessInfo.processInfo.systemUptime
        if diagnosticStart == nil { diagnosticStart = start }
        diagnosticFrames += 1; diagnosticCPU += end-start; diagnosticMaxCPU = max(diagnosticMaxCPU,end-start)
        guard diagnosticFrames == 180, let first = diagnosticStart else { return }
        let report: [String: Any] = ["synthetic":true,"frames":diagnosticFrames,"drawCallbacksPerSecond":Double(diagnosticFrames-1)/(end-first),
            "averageCPUFrameMs":diagnosticCPU/Double(diagnosticFrames)*1000,"maximumCPUFrameMs":diagnosticMaxCPU*1000,
            "routeVertices":scene.vertices.count,"curtainTriangles":fillCount/3,"targetFPS":view.preferredFramesPerSecond,
            "note":"Simulator draw callbacks and CPU submission only; not device GPU FPS or energy."]
        do {
            let data = try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys])
            try data.write(to:FileManager.default.temporaryDirectory.appendingPathComponent("altiscope-3d-metrics.json"),options:.atomic)
        } catch { NSLog("Altiscope synthetic render metrics could not be saved: %@",error.localizedDescription) }
    }
    #endif
    private static let shader = """
    #include <metal_stdlib>
    using namespace metal;
    struct Vertex { float4 position; float4 color; float4 other; };
    struct Uniforms { float4 u; float4 v; float4 w; float4 viewport; };
    struct Output { float4 position [[position]]; float4 color; float size [[point_size]]; };
    float4 project(float3 p, constant Uniforms &m) {
        float4 v = float4(p,1); float u = dot(m.u,v), y = dot(m.v,v), w = dot(m.w,v);
        return float4(2*u/m.viewport.x-w,w-2*y/m.viewport.y,(w-0.001)*1.000001,w);
    }
    vertex Output routeVertex(uint id [[vertex_id]], device const Vertex *vertices [[buffer(0)]], constant Uniforms &m [[buffer(1)]]) {
        Vertex v = vertices[id]; Output out;
        out.position = project(v.position.xyz,m); out.color=v.color; out.size=3;
        return out;
    }
    vertex Output strokeVertex(uint id [[vertex_id]], device const Vertex *vertices [[buffer(0)]], constant Uniforms &m [[buffer(1)]]) {
        Vertex v=vertices[id]; Output out; out.position=project(v.position.xyz,m);
        float4 other=project(v.other.xyz,m);
        float2 a=out.position.xy/max(0.001,out.position.w), b=other.xy/max(0.001,other.w);
        float2 d=(b-a)*m.viewport.xy;
        float2 normal=length(d)>0.00001 ? normalize(float2(-d.y,d.x)) : float2(0,1);
        out.position.xy+=normal*v.other.w*3.0/m.viewport.xy*out.position.w;
        out.color=v.color; out.size=3; return out;
    }
    fragment float4 routeFragment(Output in [[stage_in]]) { return in.color; }
    """
}
