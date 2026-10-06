import ARKit
import CoreImage
import Foundation
import RealityKit
import UIKit

@available(iOS 18.0, *)
@MainActor
final class SceneMeshCaptureController: UIViewController, ARSessionDelegate {
    private struct ColorFrame {
        let camera: ARCamera
        let width: Int
        let height: Int
        let rgba: [UInt8]
    }

    private struct ColorAtlas {
        let image: CGImage
        let png: Data
        let uvs: [SIMD2<Float>]
    }

    private let arView = ARView(frame: .zero, cameraMode: .ar, automaticallyConfigureSession: false)
    private let panel = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterialDark))
    private let statusLabel = UILabel()
    private let finishButton = UIButton(type: .system)
    private let meshButton = UIButton(type: .system)
    private let closeButton = UIButton(type: .system)
    private let progressIndicator = UIActivityIndicatorView(style: .medium)
    private var anchors: [UUID: ARMeshAnchor] = [:]
    private var depthFrames: [DepthSpaceCapture.Frame] = []
    private var lastDepthFrameTime = Date.distantPast
    private var colorFrames: [ColorFrame] = []
    private var lastColorFrameTime = Date.distantPast
    private var colorFramePending = false
    private var statusTimer: Timer?
    private var finishing = false
    private var meshVisible = true
    private let glbURL: URL
    private let highDetail: Bool

    init(highDetail: Bool) {
        self.highDetail = highDetail
        let root = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("BoulderScans", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        glbURL = root.appendingPathComponent("space.glb")
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
    }

    required init?(coder: NSCoder) { nil }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        arView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(arView)
        NSLayoutConstraint.activate([
            arView.topAnchor.constraint(equalTo: view.topAnchor),
            arView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            arView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            arView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        statusLabel.textColor = .white
        statusLabel.font = .preferredFont(forTextStyle: .body)
        statusLabel.numberOfLines = 3
        statusLabel.text = "Move slowly around the whole space. LiDAR mesh coverage will grow as you move."
        arView.debugOptions.insert(.showSceneUnderstanding)
        finishButton.configuration = .filled()
        finishButton.setTitle("Finish space scan", for: .normal)
        finishButton.isEnabled = false
        finishButton.addTarget(self, action: #selector(finishTapped), for: .touchUpInside)
        meshButton.setTitle("Hide live mesh", for: .normal)
        meshButton.addTarget(self, action: #selector(toggleMeshTapped), for: .touchUpInside)
        closeButton.setTitle("Close", for: .normal)
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)

        progressIndicator.color = .white
        progressIndicator.hidesWhenStopped = true
        let buttons = UIStackView(arrangedSubviews: [finishButton, meshButton, closeButton])
        buttons.axis = .horizontal
        buttons.spacing = 12
        buttons.distribution = .fillEqually
        let controls = UIStackView(arrangedSubviews: [statusLabel, progressIndicator, buttons])
        controls.axis = .vertical
        controls.spacing = 12
        controls.translatesAutoresizingMaskIntoConstraints = false
        panel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(panel)
        panel.contentView.addSubview(controls)
        NSLayoutConstraint.activate([
            panel.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            panel.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            panel.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            controls.topAnchor.constraint(equalTo: panel.contentView.topAnchor, constant: 12),
            controls.leadingAnchor.constraint(equalTo: panel.contentView.leadingAnchor, constant: 20),
            controls.trailingAnchor.constraint(equalTo: panel.contentView.trailingAnchor, constant: -20),
            controls.bottomAnchor.constraint(equalTo: panel.safeAreaLayoutGuide.bottomAnchor, constant: -12),
        ])
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) else {
            statusLabel.text = "LiDAR scene reconstruction is unavailable on this device."
            SpikeDiagnostics.record("LiDAR mesh unsupported")
            return
        }
        CaptureResult.status = "Scanning space with LiDAR (\(highDetail ? "high detail" : "balanced"))."
        CaptureResult.glbPath = ""
        CaptureResult.usdzPath = ""
        SpikeDiagnostics.record("LiDAR space scan started; quality=\(highDetail ? "high" : "balanced"); GLB=\(glbURL.path)")
        let configuration = ARWorldTrackingConfiguration()
        configuration.sceneReconstruction = .mesh
        configuration.environmentTexturing = .none
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.smoothedSceneDepth) {
            configuration.frameSemantics.insert(.smoothedSceneDepth)
            SpikeDiagnostics.record("Camera-aligned scene depth enabled")
        }
        arView.session.delegate = self
        arView.session.delegateQueue = .main
        arView.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
        statusTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshStatus() }
        }
    }

    nonisolated func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
        Task { @MainActor in self.save(anchors) }
    }

    nonisolated func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        Task { @MainActor in self.save(anchors) }
    }

    nonisolated func session(_ session: ARSession, didRemove anchors: [ARAnchor]) {
        Task { @MainActor in
            for anchor in anchors { self.anchors.removeValue(forKey: anchor.identifier) }
        }
    }

    nonisolated func session(_ session: ARSession, didFailWithError error: Error) {
        Task { @MainActor in
            self.statusLabel.text = "LiDAR scan failed: \(error.localizedDescription)"
            CaptureResult.status = self.statusLabel.text ?? "LiDAR scan failed."
            SpikeDiagnostics.record("LiDAR session error: \(error.localizedDescription)")
            self.finishButton.isEnabled = false
        }
    }

    private func save(_ newAnchors: [ARAnchor]) {
        guard !finishing else { return }
        for case let anchor as ARMeshAnchor in newAnchors {
            anchors[anchor.identifier] = anchor
        }
    }

    private func refreshStatus() {
        guard !finishing else { return }
        let faces = anchors.values.reduce(0) { $0 + $1.geometry.faces.count }
        if faces > 0 {
            captureDepthFrameIfNeeded()
            if depthFrames.isEmpty { captureColorFrameIfNeeded() }
        }
        finishButton.isEnabled = faces > 0
        statusLabel.text = "\(highDetail ? "High detail" : "Balanced") · \(anchors.count) patches · \(faces) triangles · \(depthFrames.count) color/depth views. Walk around the space to fill gaps."
        CaptureResult.status = statusLabel.text ?? "Scanning space."
    }

    private func captureDepthFrameIfNeeded() {
        guard depthFrames.count < (highDetail ? 32 : 24),
              Date().timeIntervalSince(lastDepthFrameTime) >= (highDetail ? 1.0 : 1.5),
              let frame = arView.session.currentFrame,
              let sample = DepthSpaceCapture.capture(frame) else { return }
        if let previous = depthFrames.last {
            let oldPosition = previous.cameraTransform.columns.3
            let newPosition = sample.cameraTransform.columns.3
            let movement = simd_length(SIMD3<Float>(newPosition.x - oldPosition.x,
                                                      newPosition.y - oldPosition.y,
                                                      newPosition.z - oldPosition.z))
            let oldForward = SIMD3<Float>(previous.cameraTransform.columns.2.x,
                                           previous.cameraTransform.columns.2.y,
                                           previous.cameraTransform.columns.2.z)
            let newForward = SIMD3<Float>(sample.cameraTransform.columns.2.x,
                                           sample.cameraTransform.columns.2.y,
                                           sample.cameraTransform.columns.2.z)
            let rotation = simd_dot(oldForward, newForward)
            guard movement >= 0.07 || rotation < 0.995 ||
                  Date().timeIntervalSince(lastDepthFrameTime) >= 5 else { return }
        }
        lastDepthFrameTime = Date()
        depthFrames.append(sample)
        SpikeDiagnostics.record("RGB-D view captured; count=\(depthFrames.count); size=\(sample.width)x\(sample.height)")
    }

    private func captureColorFrameIfNeeded() {
        guard !colorFramePending, colorFrames.count < 12,
              Date().timeIntervalSince(lastColorFrameTime) >= 4,
              let frame = arView.session.currentFrame else { return }
        colorFramePending = true
        lastColorFrameTime = Date()
        defer { colorFramePending = false }
        let input = CIImage(cvPixelBuffer: frame.capturedImage)
        guard let cgImage = CIContext().createCGImage(input, from: input.extent) else { return }
        let image = UIImage(cgImage: cgImage, scale: 1, orientation: .right)
        guard let sample = Self.makeColorFrame(image: image, camera: frame.camera) else { return }
        colorFrames.append(sample)
        SpikeDiagnostics.record("LiDAR color frame captured; count=\(colorFrames.count)")
    }

    private static func makeColorFrame(image: UIImage, camera: ARCamera) -> ColorFrame? {
        let width = 360
        let height = max(1, Int((image.size.height / image.size.width * CGFloat(width)).rounded()))
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let scaled = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format)
            .image { _ in image.draw(in: CGRect(x: 0, y: 0, width: width, height: height)) }
        guard let cgImage = scaled.cgImage else { return nil }
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        let rendered = rgba.withUnsafeMutableBytes { bytes in
            guard let context = CGContext(data: bytes.baseAddress, width: width, height: height,
                                          bitsPerComponent: 8, bytesPerRow: width * 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
                return false
            }
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        return rendered ? ColorFrame(camera: camera, width: width, height: height, rgba: rgba) : nil
    }

    @objc private func finishTapped() {
        guard !finishing else { return }
        finishing = true
        finishButton.isEnabled = false
        meshButton.isEnabled = false
        progressIndicator.startAnimating()
        statusTimer?.invalidate()
        arView.session.pause()
        statusLabel.text = "Freezing captured LiDAR mesh…"
        let triangles = Self.collectTriangles(from: Array(anchors.values))
        guard !triangles.isEmpty else {
            statusLabel.text = "No LiDAR mesh was captured. Move around the surface and try again."
            CaptureResult.status = statusLabel.text ?? "No LiDAR mesh captured."
            SpikeDiagnostics.record("LiDAR scan ended without triangles")
            progressIndicator.stopAnimating()
            return
        }
        SpikeDiagnostics.record("LiDAR scan finishing; patches=\(anchors.count); triangles=\(triangles.count / 3)")
        statusLabel.text = "Sampling camera colors…"
        CaptureResult.status = statusLabel.text ?? "Building GLB."
        Task {
            do {
                let previewPositions: [SIMD3<Float>]
                let previewColors: [SIMD4<Float>]
                if !depthFrames.isEmpty {
                    statusLabel.text = "Fusing camera-aligned depth surfaces…"
                    await Task.yield()
                    let samples = depthFrames
                    let visual = try await Task.detached(priority: .userInitiated) {
                        try DepthSpaceCapture.build(from: samples, highDetail: self.highDetail)
                    }.value
                    previewPositions = visual.positions
                    previewColors = visual.colors
                    SpikeDiagnostics.record("RGB-D surface built; views=\(depthFrames.count); triangles=\(previewPositions.count / 3)")
                } else {
                    let colors = Self.vertexColors(for: triangles, frames: colorFrames)
                    previewPositions = triangles
                    previewColors = colors
                    SpikeDiagnostics.record("RGB-D unavailable; fallback mesh colored; frames=\(colorFrames.count)")
                }
                statusLabel.text = "Building texture and RealityKit preview…"
                await Task.yield()
                let atlas = try Self.makeColorAtlas(colors: previewColors)
                let descriptor = Self.meshDescriptor(positions: previewPositions, uvs: atlas.uvs)
                let resource = try MeshResource.generate(from: [descriptor])
                let texture = try await TextureResource(image: atlas.image,
                    options: .init(semantic: .color, mipmapsMode: .none))
                let entity = ModelEntity(mesh: resource,
                                         materials: [UnlitMaterial(texture: texture)])
                showPreview(entity)
                statusLabel.text = "Writing visual GLB and structural mesh…"
                await Task.yield()
                let outputURL = glbURL
                let outputPositions = previewPositions
                let outputUVs = atlas.uvs
                let outputPNG = atlas.png
                let structureTriangles = depthFrames.isEmpty ? [] : triangles
                let structureURL = try await Task.detached(priority: .userInitiated) {
                    try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(),
                                                            withIntermediateDirectories: true)
                    try ObjToGlb.writeSceneTriangles(outputPositions, uvs: outputUVs,
                                                     texturePNG: outputPNG, destination: outputURL)
                    guard !structureTriangles.isEmpty else { return Optional<URL>.none }
                    let url = outputURL.deletingLastPathComponent()
                        .appendingPathComponent("space-structure.glb")
                    try ObjToGlb.writeUntexturedTriangles(structureTriangles, destination: url)
                    return url
                }.value
                if let structureURL {
                    SpikeDiagnostics.record("Structural LiDAR GLB complete; path=\(structureURL.path)")
                }
                CaptureResult.glbPath = glbURL.path
                statusLabel.text = "Visual space GLB ready. RealityKit preview loaded."
                CaptureResult.status = statusLabel.text ?? "Space GLB ready."
                SpikeDiagnostics.record("LiDAR GLB complete; path=\(glbURL.path)")
            } catch {
                statusLabel.text = "Space export failed: \(error.localizedDescription)"
                CaptureResult.status = statusLabel.text ?? "Space export failed."
                SpikeDiagnostics.record("LiDAR export error: \(error.localizedDescription)")
            }
            progressIndicator.stopAnimating()
        }
    }

    @objc private func toggleMeshTapped() {
        meshVisible.toggle()
        if meshVisible {
            arView.debugOptions.insert(.showSceneUnderstanding)
        } else {
            arView.debugOptions.remove(.showSceneUnderstanding)
        }
        meshButton.setTitle(meshVisible ? "Hide live mesh" : "Show live mesh", for: .normal)
    }

    private static func vertexColors(for positions: [SIMD3<Float>],
                                     frames: [ColorFrame]) -> [SIMD4<Float>] {
        let fallback = SIMD4<Float>(0.72, 0.75, 0.73, 1)
        guard !frames.isEmpty else { return Array(repeating: fallback, count: positions.count) }
        return positions.map { position in
            var bestDistance = Float.greatestFiniteMagnitude
            var color = fallback
            for frame in frames {
                let point = frame.camera.projectPoint(position, orientation: .portrait,
                    viewportSize: CGSize(width: frame.width, height: frame.height))
                guard point.x.isFinite, point.y.isFinite,
                      point.x >= 0, point.y >= 0,
                      point.x < CGFloat(frame.width), point.y < CGFloat(frame.height) else { continue }
                let cameraPosition = frame.camera.transform.columns.3
                let dx = position.x - cameraPosition.x
                let dy = position.y - cameraPosition.y
                let dz = position.z - cameraPosition.z
                let distance = dx * dx + dy * dy + dz * dz
                guard distance < bestDistance else { continue }
                let x = Int(point.x)
                let y = frame.height - 1 - Int(point.y)
                let offset = (y * frame.width + x) * 4
                color = SIMD4<Float>(Float(frame.rgba[offset]) / 255,
                                     Float(frame.rgba[offset + 1]) / 255,
                                     Float(frame.rgba[offset + 2]) / 255, 1)
                bestDistance = distance
            }
            return color
        }
    }

    private static func makeColorAtlas(colors: [SIMD4<Float>]) throws -> ColorAtlas {
        let faceCount = colors.count / 3
        var side = 2
        while (side / 2) * (side / 2) < faceCount { side *= 2 }
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        var uvs: [SIMD2<Float>] = []
        uvs.reserveCapacity(colors.count)
        func writePixel(_ color: SIMD4<Float>, x: Int, y: Int) {
            let offset = (y * side + x) * 4
            pixels[offset] = UInt8((min(max(color.x, 0), 1) * 255).rounded())
            pixels[offset + 1] = UInt8((min(max(color.y, 0), 1) * 255).rounded())
            pixels[offset + 2] = UInt8((min(max(color.z, 0), 1) * 255).rounded())
            pixels[offset + 3] = 255
        }
        for face in 0..<faceCount {
            let tileX = (face % (side / 2)) * 2
            let tileY = (face / (side / 2)) * 2
            let first = colors[face * 3]
            let second = colors[face * 3 + 1]
            let third = colors[face * 3 + 2]
            writePixel(first, x: tileX, y: tileY)
            writePixel(second, x: tileX + 1, y: tileY)
            writePixel(third, x: tileX, y: tileY + 1)
            writePixel((first + second + third) / 3, x: tileX + 1, y: tileY + 1)
            let inverse = 1 / Float(side)
            uvs.append(SIMD2((Float(tileX) + 0.5) * inverse,
                             (Float(tileY) + 0.5) * inverse))
            uvs.append(SIMD2((Float(tileX) + 1.5) * inverse,
                             (Float(tileY) + 0.5) * inverse))
            uvs.append(SIMD2((Float(tileX) + 0.5) * inverse,
                             (Float(tileY) + 1.5) * inverse))
        }
        let data = Data(pixels)
        guard let provider = CGDataProvider(data: data as CFData),
              let image = CGImage(width: side, height: side, bitsPerComponent: 8,
                                  bitsPerPixel: 32, bytesPerRow: side * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                                  provider: provider, decode: nil, shouldInterpolate: false,
                                  intent: .defaultIntent),
              let png = UIImage(cgImage: image).pngData() else {
            throw ObjToGlbError.unsupportedTexture("Could not create LiDAR color atlas")
        }
        return ColorAtlas(image: image, png: png, uvs: uvs)
    }

    private static func collectTriangles(from anchors: [ARMeshAnchor]) -> [SIMD3<Float>] {
        var triangles: [SIMD3<Float>] = []
        triangles.reserveCapacity(anchors.reduce(0) { $0 + $1.geometry.faces.count * 3 })
        for anchor in anchors {
            let geometry = anchor.geometry
            let vertices = geometry.vertices
            let faces = geometry.faces
            guard faces.indexCountPerPrimitive == 3 else { continue }
            let facePointer = faces.buffer.contents()
            let vertexPointer = vertices.buffer.contents()
            for face in 0..<faces.count {
                var triangle: [SIMD3<Float>] = []
                triangle.reserveCapacity(3)
                for corner in 0..<3 {
                    let indexOffset = (face * 3 + corner) * faces.bytesPerIndex
                    let index: Int
                    if faces.bytesPerIndex == 4 {
                        index = Int(facePointer.advanced(by: indexOffset).loadUnaligned(as: UInt32.self))
                    } else if faces.bytesPerIndex == 2 {
                        index = Int(facePointer.advanced(by: indexOffset).loadUnaligned(as: UInt16.self))
                    } else {
                        break
                    }
                    guard index < vertices.count else { break }
                    let local = vertexPointer.advanced(by: vertices.offset + index * vertices.stride)
                        .loadUnaligned(as: SIMD3<Float>.self)
                    let world = anchor.transform * SIMD4<Float>(local.x, local.y, local.z, 1)
                    triangle.append(SIMD3<Float>(world.x, world.y, world.z))
                }
                if triangle.count == 3 {
                    triangles.append(contentsOf: triangle)
                }
            }
        }
        return triangles
    }

    private static func meshDescriptor(positions: [SIMD3<Float>],
                                       uvs: [SIMD2<Float>]) -> MeshDescriptor {
        var descriptor = MeshDescriptor(name: "LiDAR space")
        descriptor.positions = MeshBuffers.Positions(positions)
        descriptor.textureCoordinates = MeshBuffers.TextureCoordinates(uvs.map { SIMD2($0.x, 1 - $0.y) })
        descriptor.primitives = .triangles(Array(0..<UInt32(positions.count)))
        return descriptor
    }

    private func showPreview(_ entity: Entity) {
        let preview = ARView(frame: .zero, cameraMode: .nonAR, automaticallyConfigureSession: false)
        preview.translatesAutoresizingMaskIntoConstraints = false
        view.insertSubview(preview, belowSubview: panel)
        NSLayoutConstraint.activate([
            preview.topAnchor.constraint(equalTo: view.topAnchor),
            preview.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            preview.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            preview.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        let bounds = entity.visualBounds(relativeTo: nil)
        let longest = max(bounds.extents.x, max(bounds.extents.y, bounds.extents.z))
        let scale: Float = longest > 0 ? min(1, 1.2 / longest) : 1
        entity.scale = SIMD3<Float>(repeating: scale)
        entity.position = SIMD3<Float>(-bounds.center.x * scale,
                                       -bounds.center.y * scale,
                                       -2 - bounds.center.z * scale)
        let anchor = AnchorEntity(world: .zero)
        anchor.addChild(PerspectiveCamera())
        anchor.addChild(entity)
        preview.scene.addAnchor(anchor)
        arView.session.delegate = nil
        arView.removeFromSuperview()
        finishButton.isHidden = true
        meshButton.isHidden = true
    }

    @objc private func closeTapped() {
        SpikeDiagnostics.record("LiDAR scan closed; patches=\(anchors.count)")
        statusTimer?.invalidate()
        arView.session.pause()
        arView.session.delegate = nil
        dismiss(animated: true)
    }
}

@_cdecl("SceneMesh_IsSupported")
public func sceneMeshIsSupported() -> Int32 {
    guard #available(iOS 18.0, *), Thread.isMainThread else { return 0 }
    return ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) ? 1 : 0
}

@_cdecl("SceneMesh_Present")
public func sceneMeshPresent(_ hostPointer: UnsafeMutableRawPointer?) -> Int32 {
    guard #available(iOS 18.0, *), Thread.isMainThread, let hostPointer else { return 0 }
    guard ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) else { return 0 }
    let host = Unmanaged<UIViewController>.fromOpaque(hostPointer).takeUnretainedValue()
    MainActor.assumeIsolated { host.present(SceneMeshCaptureController(highDetail: false), animated: true) }
    return 1
}

@_cdecl("SceneMesh_PresentWithQuality")
public func sceneMeshPresentWithQuality(_ hostPointer: UnsafeMutableRawPointer?,
                                        _ quality: Int32) -> Int32 {
    guard #available(iOS 18.0, *), Thread.isMainThread, let hostPointer else { return 0 }
    guard ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) else { return 0 }
    let host = Unmanaged<UIViewController>.fromOpaque(hostPointer).takeUnretainedValue()
    MainActor.assumeIsolated {
        host.present(SceneMeshCaptureController(highDetail: quality == 1), animated: true)
    }
    return 1
}
