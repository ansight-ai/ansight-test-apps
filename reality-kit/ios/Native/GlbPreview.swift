import Foundation
import RealityKit
import UIKit

// This reader intentionally supports the single-mesh GLB layout written by ObjToGlb.
// Reading the saved bytes makes the preview an export check, not an in-memory surrogate.
@available(iOS 18.0, *)
private enum CapturedGlb {
    struct Model {
        let positions: [SIMD3<Float>]
        let uvs: [SIMD2<Float>]
        let indices: [UInt32]
        let image: CGImage?
    }

    enum Failure: LocalizedError {
        case invalid(String)
        var errorDescription: String? {
            if case let .invalid(message) = self { return message }
            return nil
        }
    }

    static func read(_ url: URL) throws -> Model {
        let data = try Data(contentsOf: url)
        func word(_ offset: Int) throws -> UInt32 {
            guard offset >= 0, offset <= data.count - 4 else { throw Failure.invalid("Truncated GLB") }
            return data.withUnsafeBytes { UInt32(littleEndian: $0.loadUnaligned(fromByteOffset: offset, as: UInt32.self)) }
        }
        guard data.count >= 28, try word(0) == 0x46546C67,
              try word(4) == 2, try word(8) == data.count,
              try word(16) == 0x4E4F534A else {
            throw Failure.invalid("Invalid GLB header")
        }
        let jsonLength = Int(try word(12))
        let binaryHeader = 20 + jsonLength
        guard binaryHeader <= data.count - 8,
              try word(binaryHeader + 4) == 0x004E4942 else {
            throw Failure.invalid("Missing GLB binary chunk")
        }
        let binaryLength = Int(try word(binaryHeader))
        let binaryStart = binaryHeader + 8
        guard binaryLength <= data.count - binaryStart else {
            throw Failure.invalid("Truncated GLB binary chunk")
        }
        guard let root = try JSONSerialization.jsonObject(with: data.subdata(in: 20..<binaryHeader)) as? [String: Any],
              let meshes = root["meshes"] as? [[String: Any]],
              let primitives = meshes.first?["primitives"] as? [[String: Any]],
              let primitive = primitives.first,
              let attributes = primitive["attributes"] as? [String: Int],
              let accessors = root["accessors"] as? [[String: Any]],
              let views = root["bufferViews"] as? [[String: Any]],
              let positionIndex = attributes["POSITION"],
              let uvIndex = attributes["TEXCOORD_0"],
              let indexIndex = primitive["indices"] as? Int else {
            throw Failure.invalid("Unsupported GLB mesh layout")
        }
        func bytes(_ accessorIndex: Int, componentType: Int, components: Int) throws -> (Int, Int) {
            guard accessors.indices.contains(accessorIndex) else { throw Failure.invalid("Invalid accessor") }
            let accessor = accessors[accessorIndex]
            guard accessor["componentType"] as? Int == componentType,
                  let count = accessor["count"] as? Int, count > 0,
                  let viewIndex = accessor["bufferView"] as? Int,
                  views.indices.contains(viewIndex) else { throw Failure.invalid("Unsupported accessor") }
            let view = views[viewIndex]
            let viewOffset = view["byteOffset"] as? Int ?? 0
            let accessorOffset = accessor["byteOffset"] as? Int ?? 0
            let byteCount = count * components * 4
            let viewLength = view["byteLength"] as? Int ?? 0
            guard count <= 1_000_000, byteCount <= viewLength - accessorOffset,
                  viewOffset >= 0, accessorOffset >= 0,
                  viewOffset + accessorOffset + byteCount <= binaryLength else {
                throw Failure.invalid("GLB accessor exceeds binary chunk")
            }
            return (binaryStart + viewOffset + accessorOffset, count)
        }
        let (positionStart, positionCount) = try bytes(positionIndex, componentType: 5126, components: 3)
        let (uvStart, uvCount) = try bytes(uvIndex, componentType: 5126, components: 2)
        let (indexStart, indexCount) = try bytes(indexIndex, componentType: 5125, components: 1)
        guard positionCount == uvCount, indexCount.isMultiple(of: 3) else {
            throw Failure.invalid("GLB attribute counts do not match")
        }
        func float(_ offset: Int) throws -> Float { Float(bitPattern: try word(offset)) }
        var positions: [SIMD3<Float>] = []
        var uvs: [SIMD2<Float>] = []
        var indices: [UInt32] = []
        positions.reserveCapacity(positionCount)
        uvs.reserveCapacity(uvCount)
        indices.reserveCapacity(indexCount)
        for i in 0..<positionCount {
            let offset = positionStart + i * 12
            positions.append(try SIMD3(float(offset), float(offset + 4), float(offset + 8)))
            let uvOffset = uvStart + i * 8
            uvs.append(try SIMD2(float(uvOffset), 1 - float(uvOffset + 4)))
        }
        for i in 0..<indexCount {
            let index = try word(indexStart + i * 4)
            guard index < positionCount else { throw Failure.invalid("GLB index is out of range") }
            indices.append(index)
        }
        var image: CGImage?
        if let images = root["images"] as? [[String: Any]],
           let imageView = images.first?["bufferView"] as? Int,
           views.indices.contains(imageView) {
            let view = views[imageView]
            let offset = view["byteOffset"] as? Int ?? 0
            let length = view["byteLength"] as? Int ?? 0
            guard offset >= 0, length > 0, offset + length <= binaryLength else {
                throw Failure.invalid("Invalid GLB texture")
            }
            image = UIImage(data: data.subdata(in: (binaryStart + offset)..<(binaryStart + offset + length)))?.cgImage
            guard image != nil else { throw Failure.invalid("Could not decode GLB texture") }
        }
        return Model(positions: positions, uvs: uvs, indices: indices, image: image)
    }
}

@available(iOS 18.0, *)
@MainActor
private final class GlbPreviewController: UIViewController {
    private let url: URL
    private let preview = ARView(frame: .zero, cameraMode: .nonAR, automaticallyConfigureSession: false)
    private let label = UILabel()
    private var model: ModelEntity?

    init(url: URL) {
        self.url = url
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
    }

    required init?(coder: NSCoder) { nil }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .darkGray
        preview.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(preview)
        NSLayoutConstraint.activate([
            preview.topAnchor.constraint(equalTo: view.topAnchor),
            preview.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            preview.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            preview.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        let close = UIButton(type: .system)
        close.setTitle("Close GLB", for: .normal)
        close.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        label.text = "Opening exported GLB…"
        label.textColor = .white
        label.numberOfLines = 3
        let panel = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterialDark))
        let controls = UIStackView(arrangedSubviews: [label, close])
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
        preview.addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(rotate(_:))))
        preview.addGestureRecognizer(UIPinchGestureRecognizer(target: self, action: #selector(zoom(_:))))
        Task {
            do {
                let source = url
                let glb = try await Task.detached(priority: .userInitiated) {
                    try CapturedGlb.read(source)
                }.value
                var descriptor = MeshDescriptor(name: "Exported GLB")
                descriptor.positions = MeshBuffers.Positions(glb.positions)
                descriptor.textureCoordinates = MeshBuffers.TextureCoordinates(glb.uvs)
                descriptor.primitives = .triangles(glb.indices)
                let mesh = try MeshResource.generate(from: [descriptor])
                let material: any Material
                if let image = glb.image {
                    let texture = try await TextureResource(image: image,
                        options: .init(semantic: .color, mipmapsMode: .none))
                    material = UnlitMaterial(texture: texture)
                } else {
                    material = UnlitMaterial(color: .lightGray)
                }
                let entity = ModelEntity(mesh: mesh, materials: [material])
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
                model = entity
                label.text = "Exported \(url.lastPathComponent) · \(glb.indices.count / 3) faces. Drag to rotate, pinch to zoom."
                SpikeDiagnostics.record("Saved GLB reopened in RealityKit; faces=\(glb.indices.count / 3)")
            } catch {
                label.text = "Could not open GLB: \(error.localizedDescription)"
                SpikeDiagnostics.record("GLB preview error: \(error.localizedDescription)")
            }
        }
    }

    @objc private func closeTapped() { dismiss(animated: true) }

    @objc private func rotate(_ gesture: UIPanGestureRecognizer) {
        guard let model else { return }
        let delta = gesture.translation(in: preview)
        model.orientation *= simd_quatf(angle: Float(delta.x) * 0.005, axis: SIMD3(0, 1, 0))
        gesture.setTranslation(.zero, in: preview)
    }

    @objc private func zoom(_ gesture: UIPinchGestureRecognizer) {
        guard let model else { return }
        model.position.z = min(-0.3, max(-12, model.position.z / Float(gesture.scale)))
        gesture.scale = 1
    }
}

@_cdecl("SceneMesh_PresentGlb")
public func sceneMeshPresentGlb(_ hostPointer: UnsafeMutableRawPointer?,
                                _ pathPointer: UnsafePointer<CChar>?) -> Int32 {
    guard #available(iOS 18.0, *), Thread.isMainThread,
          let hostPointer, let pathPointer else { return 0 }
    let url = URL(fileURLWithPath: String(cString: pathPointer))
    guard FileManager.default.fileExists(atPath: url.path) else { return 0 }
    let host = Unmanaged<UIViewController>.fromOpaque(hostPointer).takeUnretainedValue()
    MainActor.assumeIsolated { host.present(GlbPreviewController(url: url), animated: true) }
    return 1
}
