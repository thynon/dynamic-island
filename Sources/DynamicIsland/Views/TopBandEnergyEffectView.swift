import AppKit
import Metal
import MetalKit
import QuartzCore
import SwiftUI

struct TopBandEnergyEffectView: NSViewRepresentable {
    func makeNSView(context: Context) -> TopBandEnergyEffectNSView {
        TopBandEnergyEffectNSView()
    }

    func updateNSView(_ nsView: TopBandEnergyEffectNSView, context: Context) {
        nsView.start()
    }
}

final class TopBandEnergyEffectNSView: NSView {
    private let trackHostView = NSView()
    private let baseGradientLayer = CAGradientLayer()
    private var metalView: MTKView?
    private var renderer: TopBandEnergyRenderer?
    private var renderTimer: Timer?
    private var didStart = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configure()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override var isOpaque: Bool {
        false
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard didStart else { return }
        if window == nil {
            stopRenderTimer()
        } else {
            startRenderTimer()
        }
    }

    override func layout() {
        super.layout()

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        trackHostView.frame = bounds
        baseGradientLayer.frame = trackHostView.bounds
        metalView?.frame = trackHostView.bounds
        renderer?.setCSSSize(trackHostView.bounds.size)
        CATransaction.commit()
    }

    func start() {
        if !didStart {
            didStart = true
            renderer?.start()
        }
        startRenderTimer()
    }

    private func configure() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.masksToBounds = false

        trackHostView.wantsLayer = true
        trackHostView.layer?.backgroundColor = NSColor.clear.cgColor
        trackHostView.layer?.masksToBounds = true
        addSubview(trackHostView)

        baseGradientLayer.startPoint = CGPoint(x: 0, y: 0.5)
        baseGradientLayer.endPoint = CGPoint(x: 1, y: 0.5)
        baseGradientLayer.colors = [
            NSColor(white: 1, alpha: 0.035).cgColor,
            NSColor(red: 0.36, green: 0.33, blue: 0.50, alpha: 0.12).cgColor,
            NSColor(red: 0.62, green: 0.40, blue: 0.94, alpha: 0.32).cgColor
        ]
        baseGradientLayer.locations = [0, 0.55, 1]
        trackHostView.layer?.addSublayer(baseGradientLayer)

        guard let device = MTLCreateSystemDefaultDevice() else { return }

        let metalView = MTKView(frame: .zero, device: device)
        metalView.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        metalView.colorPixelFormat = .bgra8Unorm
        metalView.framebufferOnly = true
        metalView.preferredFramesPerSecond = 12
        metalView.isPaused = true
        metalView.enableSetNeedsDisplay = false
        metalView.autoresizingMask = [.width, .height]
        metalView.wantsLayer = true
        metalView.layer?.isOpaque = false
        metalView.layer?.backgroundColor = NSColor.clear.cgColor
        metalView.layer?.masksToBounds = true
        (metalView.layer as? CAMetalLayer)?.isOpaque = false

        guard let renderer = TopBandEnergyRenderer(device: device) else { return }
        metalView.delegate = renderer
        trackHostView.addSubview(metalView)
        self.renderer = renderer
        self.metalView = metalView
    }

    private func startRenderTimer() {
        guard renderTimer == nil, window != nil else { return }
        metalView?.draw()
        let timer = Timer(timeInterval: 1.0 / 12.0, target: self, selector: #selector(renderFrame(_:)), userInfo: nil, repeats: true)
        RunLoop.main.add(timer, forMode: .common)
        renderTimer = timer
    }

    @objc private func renderFrame(_ timer: Timer) {
        metalView?.draw()
    }

    private func stopRenderTimer() {
        renderTimer?.invalidate()
        renderTimer = nil
    }
}

private final class TopBandEnergyRenderer: NSObject, MTKViewDelegate {
    private static let maxBursts = 8
    private static let uniformCount = 80

    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let pipelineState: MTLRenderPipelineState
    private let vertexBuffer: MTLBuffer
    private let energyTailOriginX = 1.0 as Float

    private var cssSize = SIMD2<Float>(1, 1)
    private var uniforms = [Float](repeating: 0, count: TopBandEnergyRenderer.uniformCount)

    private var burstTime = [Float](repeating: -1000, count: TopBandEnergyRenderer.maxBursts)
    private var burstCenter = [SIMD2<Float>](repeating: .zero, count: TopBandEnergyRenderer.maxBursts)
    private var burstGain = [Float](repeating: 0, count: TopBandEnergyRenderer.maxBursts)
    private var writeIndex = 0

    private var isEnergized = false
    private var didFireInitialBurst = false
    private var envelope: Float = 0
    private var elapsed: Float = 0
    private var clock: Float = 0
    private var lastFrameTime: CFTimeInterval = 0
    private var lastBurstClock: Float = -.infinity
    private var nextAutoBurstGap: Float = 0.42
    private var seed: Float = Float.random(in: 0..<512)

    init?(device: MTLDevice) {
        self.device = device
        guard
            let commandQueue = device.makeCommandQueue(),
            let library = try? device.makeLibrary(source: Self.metalSource, options: nil),
            let vertexFunction = library.makeFunction(name: "energy_vertex"),
            let fragmentFunction = library.makeFunction(name: "energy_fragment")
        else {
            return nil
        }

        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertexFunction
        descriptor.fragmentFunction = fragmentFunction
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm

        guard
            let pipelineState = try? device.makeRenderPipelineState(descriptor: descriptor),
            let vertexBuffer = device.makeBuffer(
                bytes: [-1, -1, 1, -1, -1, 1, -1, 1, 1, -1, 1, 1] as [Float],
                length: MemoryLayout<Float>.stride * 12
            )
        else {
            return nil
        }

        self.commandQueue = commandQueue
        self.pipelineState = pipelineState
        self.vertexBuffer = vertexBuffer
        super.init()
        updateThemeUniforms()
    }

    func start() {
        guard !isEnergized else { return }
        isEnergized = true
        elapsed = 0
        didFireInitialBurst = false
        burstTime = [Float](repeating: -1000, count: Self.maxBursts)
        burstGain = [Float](repeating: 0, count: Self.maxBursts)
        writeIndex = 0
        lastBurstClock = -.infinity
    }

    func setCSSSize(_ size: CGSize) {
        cssSize = SIMD2(Float(max(size.width, 1)), Float(max(size.height, 1)))
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        // The owning AppKit view supplies point-space sizing during layout.
    }

    func draw(in view: MTKView) {
        guard
            let descriptor = view.currentRenderPassDescriptor,
            let drawable = view.currentDrawable,
            let commandBuffer = commandQueue.makeCommandBuffer(),
            let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor)
        else {
            return
        }

        tick()
        writeUniforms()

        uniforms.withUnsafeBytes { uniformBytes in
            encoder.setRenderPipelineState(pipelineState)
            encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
            encoder.setVertexBytes(uniformBytes.baseAddress!, length: uniformBytes.count, index: 1)
            encoder.setFragmentBytes(uniformBytes.baseAddress!, length: uniformBytes.count, index: 1)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
        }

        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    private func tick() {
        let now = CACurrentMediaTime()
        if lastFrameTime == 0 {
            lastFrameTime = now
        }

        let dt = Float(min(max(now - lastFrameTime, 0), 1.0 / 12.0))
        lastFrameTime = now
        clock += dt

        if !isEnergized {
            start()
        }

        envelope = min(envelope + dt / 0.7, 1)
        elapsed += dt

        fireInitialBurstIfNeeded()
        guard didFireInitialBurst else { return }

        if clock - lastBurstClock > nextAutoBurstGap {
            let ageNorm = min(elapsed / 1.8, 1)
            nextAutoBurstGap = 0.34 + 0.46 * Float.random(in: 0...1)
            let position = max(0.92, min(1, energyTailOriginX - 0.08 * Float.random(in: 0...1)))
            fireBurst(
                gain: (0.5 + 0.42 * ageNorm) * (0.82 + 0.26 * Float.random(in: 0...1)),
                position: position
            )
        }
    }

    private func fireInitialBurstIfNeeded() {
        guard isEnergized, !didFireInitialBurst else { return }
        let hasResolvedSize = cssSize.x > 8 && cssSize.y > 4
        guard hasResolvedSize else { return }

        didFireInitialBurst = true
        fireBurst(gain: 0.72, position: energyTailOriginX)
    }

    private func fireBurst(gain: Float, position: Float) {
        burstTime[writeIndex] = clock
        burstCenter[writeIndex] = SIMD2(
            min(max(position, 0), 1) * cssSize.x,
            cssSize.y * (0.34 + 0.32 * Float.random(in: 0...1))
        )
        burstGain[writeIndex] = min(max(gain, 0), 1)
        writeIndex = (writeIndex + 1) % Self.maxBursts
        lastBurstClock = clock
    }

    private func updateThemeUniforms() {
        set4(8, SIMD4<Float>(0.46, 0.42, 0.56, 0.45))
        set4(12, SIMD4<Float>(0.66, 0.42, 0.98, 0.88))
        set4(16, SIMD4<Float>(0.74, 0.68, 1.0, 0.20))
        set4(20, SIMD4<Float>(1.0, 0.78, 0.92, 0.16))
        set3(24, SIMD3<Float>(0.91, 0.82, 1.0))
        set3(28, SIMD3<Float>(0.56, 0.46, 0.75))
        uniforms[32] = 0.0
        uniforms[33] = 0.92
        uniforms[34] = 0.72
        uniforms[35] = 0.18
        uniforms[36] = 1.0
        uniforms[37] = 1.18
    }

    private func writeUniforms() {
        uniforms[0] = cssSize.x
        uniforms[1] = cssSize.y
        uniforms[2] = clock
        uniforms[3] = seed
        uniforms[4] = max(energyTailOriginX, 0.02)
        uniforms[5] = envelope * envelope * (3 - 2 * envelope)

        for index in 0..<Self.maxBursts {
            uniforms[40 + index] = burstTime[index]
            uniforms[48 + index] = burstGain[index]
            uniforms[56 + index * 2] = burstCenter[index].x
            uniforms[56 + index * 2 + 1] = burstCenter[index].y
        }
    }

    private func set3(_ offset: Int, _ value: SIMD3<Float>) {
        uniforms[offset] = value.x
        uniforms[offset + 1] = value.y
        uniforms[offset + 2] = value.z
    }

    private func set4(_ offset: Int, _ value: SIMD4<Float>) {
        uniforms[offset] = value.x
        uniforms[offset + 1] = value.y
        uniforms[offset + 2] = value.z
        uniforms[offset + 3] = value.w
    }

    private static let metalSource = #"""
    #include <metal_stdlib>
    using namespace metal;

    struct VertexOut {
        float4 position [[position]];
        float2 uv;
    };

    float hash21(float2 p) {
        return fract(sin(dot(p, float2(127.1, 311.7))) * 43758.5453);
    }

    float4 read4(constant float *u, int offset) {
        return float4(u[offset], u[offset + 1], u[offset + 2], u[offset + 3]);
    }

    float3 read3(constant float *u, int offset) {
        return float3(u[offset], u[offset + 1], u[offset + 2]);
    }

    vertex VertexOut energy_vertex(
        uint vertexID [[vertex_id]],
        const device float2 *positions [[buffer(0)]],
        constant float *u [[buffer(1)]]
    ) {
        float2 p = positions[vertexID];
        VertexOut out;
        out.position = float4(p, 0.0, 1.0);
        out.uv = (p * 0.5 + 0.5) * float2(u[0], u[1]);
        return out;
    }

    fragment float4 energy_fragment(VertexOut in [[stage_in]], constant float *u [[buffer(1)]]) {
        constexpr int MAX_BURSTS = 8;
        constexpr float CELL_PITCH = 4.0;
        constexpr float CELL_SIZE = 3.0;
        constexpr float CELL_R = 0.9;
        constexpr float SPEED_LO = 20.0;
        constexpr float SPEED_HI = 36.0;
        constexpr float RANGE_LO = 10.0;
        constexpr float RANGE_HI = 55.0;
        constexpr float DENSITY_LO = 0.30;
        constexpr float DENSITY_HI = 0.85;
        constexpr float JITTER = 0.10;
        constexpr float HEAD_GAIN = 1.25;
        constexpr float HEAD_DECAY = 5.0;
        constexpr float BODY_GAIN = 0.65;
        constexpr float BODY_LO = 3.3;
        constexpr float BODY_HI = 0.77;
        constexpr float AMP_LO = 0.55;
        constexpr float MAX_AGE = 5.0;
        constexpr float RAMP_POW = 1.4;
        constexpr float BREATH_DIP = 0.28;
        constexpr float BREATH_BASE = 2.4;
        constexpr float BREATH_VARY = 1.4;

        float2 resolution = float2(u[0], u[1]);
        float u_time = u[2];
        float u_seed = u[3];
        float u_pos = u[4];
        float u_fade = u[5];
        float4 u_charge0 = read4(u, 8);
        float4 u_charge1 = read4(u, 12);
        float4 u_tintA = read4(u, 16);
        float4 u_tintB = read4(u, 20);
        float3 u_fg = read3(u, 24);
        float3 u_fg2 = read3(u, 28);
        float u_bedFill = u[32];
        float u_chargeMax = u[33];
        float u_chargeRamp = u[34];
        float u_inkFloor = u[35];
        float u_inkCeil = u[36];
        float u_energyGain = u[37];

        float2 v_uv = in.uv;
        float pitch = resolution.y / max(round(resolution.y / CELL_PITCH), 1.0);
        float cellScale = pitch / CELL_PITCH;
        float2 cell = floor(v_uv / pitch);
        float2 cellCenter = (cell + 0.5) * pitch;

        float cellHalf = CELL_SIZE * 0.5 * cellScale;
        float cellR = CELL_R * cellScale;
        float2 q = abs(v_uv - cellCenter) - float2(cellHalf - cellR);
        float distC = length(max(q, float2(0.0))) + min(max(q.x, q.y), 0.0) - cellR;
        float aa = min(fwidth(v_uv.x), 1.5);
        float cellMask = 1.0 - smoothstep(-aa, aa, distC);
        if (cellMask <= 0.0 && u_bedFill <= 0.0) {
            return float4(0.0);
        }

        float jitter = (hash21(cell + 41.7 + u_seed) - 0.5) * 2.0 * JITTER;
        float vary = 0.35 + 0.65 * hash21(cell + 13.7 + u_seed);

        float energy = 0.0;
        float charged = 0.0;
        for (int i = 0; i < MAX_BURSTS; i++) {
            float age = u_time - u[40 + i];
            if (age < 0.0 || age > MAX_AGE) {
                continue;
            }
            float k = clamp(u[48 + i], 0.0, 1.0);
            float2 burstCenter = float2(u[56 + i * 2], u[56 + i * 2 + 1]);
            float2 originCell = floor(burstCenter / pitch);
            float manh = abs(cell.x - originCell.x) + abs(cell.y - originCell.y);

            float range = mix(RANGE_LO, RANGE_HI, k);
            float falloff = exp(-manh / (range * 0.85));
            float reach = exp(-max(manh - range, 0.0) * 0.12);
            float speed = mix(SPEED_LO, SPEED_HI, k);
            float t = age - manh / speed - jitter;
            charged = max(charged, smoothstep(0.0, 0.15, t) * reach);
            if (t < 0.0) {
                continue;
            }

            float rank = hash21(cell + 7.3 + u_seed + u[40 + i]);
            if (rank > mix(DENSITY_LO, DENSITY_HI, k)) {
                continue;
            }

            float head = HEAD_GAIN * exp(-t * HEAD_DECAY);
            float body = BODY_GAIN * exp(-t * mix(BODY_LO, BODY_HI, k));
            energy += (head + body) * mix(AMP_LO, 1.0, k) * falloff * reach * vary;
        }

        float lumA = hash21(cell + 8.8 + u_seed);
        float lumB = hash21(cell + 88.8 + u_seed);
        float lumDrift = 0.5 + 0.5 * sin(u_time * 0.35 + lumA * 6.2832);
        float lum = pow(mix(lumA, lumB, lumDrift), 1.9);
        float stream = 0.9 + 0.16 * sin(u_time * 1.3 + cell.x * 0.45 + lumB * 2.0);
        float e = clamp(energy, 0.0, 1.0) * u_fade * mix(0.16, 1.0, lum) * stream * u_energyGain;

        float g = clamp(v_uv.x / max(u_pos * resolution.x, 1.0), 0.0, 1.0);
        float3 chargeColor = mix(u_charge0.rgb, u_charge1.rgb, g);
        float bedMask = mix(u_bedFill, 1.0, cellMask);
        float chargeA = u_chargeMax * pow(g, u_chargeRamp) * charged * u_fade
            * bedMask * mix(u_charge0.a, u_charge1.a, g);

        float lv = step(0.04, e) + step(0.2, e) + step(0.4, e) + step(0.6, e) + step(0.8, e);
        float alpha = lv <= 0.0 ? 0.0 : mix(u_inkFloor, u_inkCeil, (lv - 1.0) / 4.0);

        if (lv >= 5.0) {
            float period = BREATH_BASE + BREATH_VARY * hash21(cell + 3.1 + u_seed);
            float phase = hash21(cell + 5.5 + u_seed) * 6.2832;
            alpha *= 1.0 - BREATH_DIP * 0.5 * (1.0 + sin(u_time * 6.2832 / period + phase));
        }

        float3 ink = mix(u_fg2, u_fg, pow(lv / 5.0, RAMP_POW));
        float hueSel = hash21(cell + 27.9 + u_seed);
        ink = mix(ink, u_tintA.rgb, u_tintA.a * smoothstep(0.62, 0.95, hueSel));
        ink = mix(ink, u_tintB.rgb, u_tintB.a * (1.0 - smoothstep(0.05, 0.38, hueSel)));
        float eA = alpha * cellMask;
        float3 col = ink * eA + chargeColor * chargeA * (1.0 - eA);
        float a = eA + chargeA * (1.0 - eA);
        if (a <= 0.0) {
            return float4(0.0);
        }
        return float4(col, a);
    }
    """#
}
