import Foundation
import RealityKit
import SwiftUI
import UIKit

@MainActor
enum SpikeDiagnostics {
    static let fileURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("BoulderScans", isDirectory: true)
        .appendingPathComponent("diagnostics.log")

    static func record(_ message: String) {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            if !FileManager.default.fileExists(atPath: fileURL.path) {
                FileManager.default.createFile(atPath: fileURL.path, contents: nil)
            }
            let handle = try FileHandle(forWritingTo: fileURL)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: Data("\(Date().ISO8601Format()) \(message)\n".utf8))
            try handle.synchronize()
        } catch {
            NSLog("BoulderCapture diagnostics write failed: %@", error.localizedDescription)
        }
    }
}

@MainActor
enum CaptureResult {
    static var status = "Ready to scan."
    static var glbPath = ""
    static var usdzPath = ""
}

@available(iOS 18.0, *)
@MainActor
private final class BoulderCaptureController: UIViewController {
    private let captureSession = ObjectCaptureSession()
    private var reconstructionSession: PhotogrammetrySession?
    private var stateTimer: Timer?
    private var reconstructionStarted = false
    private var lastShotCount = 0
    private var lastShotDate = Date()
    private var lastManualRequestDate = Date.distantPast
    private var lastLoggedState = ""
    private var captureHosting: UIViewController?
    private var previewView: ARView?
    private let statusLabel = UILabel()
    private let actionButton = UIButton(type: .system)
    private let closeButton = UIButton(type: .system)
    private let controlsPanel = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterialDark))
    private let captureDirectory: URL
    private let imagesDirectory: URL
    private let usdzURL: URL
    private let objDirectory: URL
    private let glbURL: URL

    init() {
        let root = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("BoulderScans", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        captureDirectory = root
        imagesDirectory = root.appendingPathComponent("images", isDirectory: true)
        usdzURL = root.appendingPathComponent("boulder.usdz")
        objDirectory = root.appendingPathComponent("obj", isDirectory: true)
        glbURL = root.appendingPathComponent("boulder.glb")
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        installCaptureView()
        installControls()
        CaptureResult.status = "Point at the boulder and start area capture."
        SpikeDiagnostics.record("scan opened; starting ObjectCaptureSession; images=\(imagesDirectory.path)")
        captureSession.start(imagesDirectory: imagesDirectory, configuration: .init())
        stateTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshCaptureState() }
        }
    }

    deinit {
        stateTimer?.invalidate()
    }

    private func installCaptureView() {
        let hosting = UIHostingController(rootView: ObjectCaptureView(session: captureSession).hideObjectReticle())
        captureHosting = hosting
        addChild(hosting)
        view.addSubview(hosting.view)
        hosting.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hosting.view.topAnchor.constraint(equalTo: view.topAnchor),
            hosting.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hosting.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hosting.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        hosting.didMove(toParent: self)
    }

    private func installControls() {
        statusLabel.textColor = .white
        statusLabel.numberOfLines = 3
        statusLabel.font = .preferredFont(forTextStyle: .body)
        actionButton.configuration = .filled()
        actionButton.addTarget(self, action: #selector(actionTapped), for: .touchUpInside)
        closeButton.setTitle("Close", for: .normal)
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)

        let buttonRow = UIStackView(arrangedSubviews: [actionButton, closeButton])
        buttonRow.axis = .horizontal
        buttonRow.spacing = 16
        buttonRow.distribution = .fillEqually
        let controls = UIStackView(arrangedSubviews: [statusLabel, buttonRow])
        controls.axis = .vertical
        controls.spacing = 12
        controls.translatesAutoresizingMaskIntoConstraints = false
        controlsPanel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(controlsPanel)
        controlsPanel.contentView.addSubview(controls)
        NSLayoutConstraint.activate([
            controlsPanel.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            controlsPanel.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            controlsPanel.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            controls.topAnchor.constraint(equalTo: controlsPanel.contentView.topAnchor, constant: 14),
            controls.leadingAnchor.constraint(equalTo: controlsPanel.contentView.leadingAnchor, constant: 20),
            controls.trailingAnchor.constraint(equalTo: controlsPanel.contentView.trailingAnchor, constant: -20),
            controls.bottomAnchor.constraint(equalTo: controlsPanel.safeAreaLayoutGuide.bottomAnchor, constant: -12),
        ])
        refreshCaptureState()
    }

    private func refreshCaptureState() {
        guard !reconstructionStarted else { return }
        let stateDescription = String(describing: captureSession.state)
        if stateDescription != lastLoggedState {
            lastLoggedState = stateDescription
            SpikeDiagnostics.record("capture state=\(stateDescription); photos=\(captureSession.numberOfShotsTaken)")
        }
        switch captureSession.state {
        case .ready:
            actionButton.setTitle("Start area scan", for: .normal)
            actionButton.isEnabled = true
            statusLabel.text = "Area mode: scan the whole surface in overlapping rows."
        case .capturing:
            requestPhotoIfAutomaticCaptureStalled()
            actionButton.setTitle("Finish capture", for: .normal)
            actionButton.isEnabled = captureSession.numberOfShotsTaken > 0
            statusLabel.text = "Area scan · \(captureSession.numberOfShotsTaken) photos. Move slowly across the surface."
        case .completed:
            actionButton.setTitle("Build model", for: .normal)
            actionButton.isEnabled = true
            statusLabel.text = "Capture complete. Build the model on this device."
        case .failed(let error):
            actionButton.isEnabled = false
            setStatus("Capture failed: \(error.localizedDescription)")
        default:
            actionButton.setTitle("Preparing camera…", for: .normal)
            actionButton.isEnabled = false
        }
    }

    private func requestPhotoIfAutomaticCaptureStalled() {
        let shotCount = captureSession.numberOfShotsTaken
        if shotCount != lastShotCount {
            lastShotCount = shotCount
            lastShotDate = Date()
            return
        }
        let now = Date()
        guard now.timeIntervalSince(lastShotDate) >= 1.5,
              now.timeIntervalSince(lastManualRequestDate) >= 1.5,
              shotCount < captureSession.maximumNumberOfInputImages,
              captureSession.canRequestImageCapture else { return }
        captureSession.requestImageCapture()
        SpikeDiagnostics.record("manual photo requested; photos=\(shotCount)")
        lastManualRequestDate = now
    }

    @objc private func actionTapped() {
        switch captureSession.state {
        case .ready:
            lastShotDate = Date()
            SpikeDiagnostics.record("start area capture requested; state=ready")
            captureSession.startCapturing() // Skipping startDetecting selects Apple's area mode.
            SpikeDiagnostics.record("start area capture returned; state=\(captureSession.state)")
        case .capturing:
            SpikeDiagnostics.record("finish capture requested; photos=\(captureSession.numberOfShotsTaken)")
            captureSession.finish()
        case .completed:
            buildModel()
        default:
            break
        }
    }

    @objc private func closeTapped() {
        SpikeDiagnostics.record("scan closed; state=\(captureSession.state)")
        if !reconstructionStarted {
            captureSession.cancel()
        }
        reconstructionSession?.cancel()
        stateTimer?.invalidate()
        dismiss(animated: true)
    }

    private func buildModel() {
        SpikeDiagnostics.record("reconstruction started; photos=\(captureSession.numberOfShotsTaken)")
        reconstructionStarted = true
        captureHosting?.view.isHidden = true
        actionButton.isEnabled = false
        setStatus("Reconstructing reduced model on device…")
        Task {
            do {
                let session = try PhotogrammetrySession(input: imagesDirectory)
                reconstructionSession = session
                let requests: [PhotogrammetrySession.Request] = [
                    .modelFile(url: usdzURL, detail: .reduced),
                    .modelFile(url: objDirectory, detail: .reduced),
                ]
                try session.process(requests: requests)
                for try await output in session.outputs {
                    switch output {
                    case .requestProgress(_, let progress):
                        setStatus("Reconstructing: \(Int(progress * 100))%")
                    case .requestError(_, let error):
                        throw error
                    case .processingComplete:
                        try await finishModel()
                        return
                    case .processingCancelled:
                        setStatus("Reconstruction cancelled.")
                        return
                    default:
                        break
                    }
                }
                throw NSError(domain: "BoulderCapture", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: "Reconstruction ended without a model."])
            } catch {
                SpikeDiagnostics.record("reconstruction error: \(error.localizedDescription)")
                setStatus("Reconstruction failed: \(error.localizedDescription)")
            }
        }
    }

    private func finishModel() async throws {
        guard FileManager.default.fileExists(atPath: usdzURL.path) else {
            throw NSError(domain: "BoulderCapture", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "RealityKit produced no USDZ file."])
        }

        setStatus("Checking USDZ in RealityKit…")
        let entity = try await Entity(contentsOf: usdzURL)
        // This is the readback proof: RealityKit actually consumes the generated asset.
        showRealityKitPreview(entity: entity)
        CaptureResult.usdzPath = usdzURL.path

        setStatus("Converting OBJ and texture to GLB…")
        let objFolder = objDirectory
        let destination = glbURL
        try await Task.detached(priority: .userInitiated) {
            try ObjToGlb.convert(objDirectory: objFolder, destination: destination)
        }.value
        CaptureResult.glbPath = glbURL.path
        SpikeDiagnostics.record("model complete; USDZ loaded in RealityKit; GLB=\(glbURL.path)")
        setStatus("Ready: RealityKit USDZ preview loaded; GLB saved at \(glbURL.lastPathComponent).")
    }

    private func showRealityKitPreview(entity: Entity) {
        let preview = ARView(frame: .zero, cameraMode: .nonAR, automaticallyConfigureSession: false)
        previewView = preview
        preview.translatesAutoresizingMaskIntoConstraints = false
        view.insertSubview(preview, belowSubview: controlsPanel)
        NSLayoutConstraint.activate([
            preview.topAnchor.constraint(equalTo: view.topAnchor),
            preview.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            preview.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            preview.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        let bounds = entity.visualBounds(relativeTo: nil)
        let longest = max(bounds.extents.x, max(bounds.extents.y, bounds.extents.z))
        let scale: Float = longest > 0 ? min(1.0, 0.8 / longest) : 1.0
        entity.scale = SIMD3<Float>(repeating: scale)
        entity.position = SIMD3<Float>(-bounds.center.x * scale,
                                       -bounds.center.y * scale,
                                       -1.5 - bounds.center.z * scale)
        let anchor = AnchorEntity(world: .zero)
        let camera = PerspectiveCamera()
        anchor.addChild(camera)
        anchor.addChild(entity)
        preview.scene.addAnchor(anchor)
        captureHosting?.view.isHidden = true
        actionButton.isHidden = true
    }

    private func setStatus(_ value: String) {
        CaptureResult.status = value
        statusLabel.text = value
        if value.contains("failed") || value.contains("cancelled") {
            SpikeDiagnostics.record("status: \(value)")
        }
    }
}

@_cdecl("BoulderCapture_IsSupported")
public func boulderCaptureIsSupported() -> Int32 {
    guard #available(iOS 18.0, *), Thread.isMainThread else { return 0 }
    return MainActor.assumeIsolated {
        ObjectCaptureSession.isSupported && PhotogrammetrySession.isSupported ? 1 : 0
    }
}

@_cdecl("BoulderCapture_Present")
public func boulderCapturePresent(_ hostPointer: UnsafeMutableRawPointer?) -> Int32 {
    guard #available(iOS 18.0, *), Thread.isMainThread, let hostPointer else { return 0 }
    return MainActor.assumeIsolated {
        guard ObjectCaptureSession.isSupported && PhotogrammetrySession.isSupported else { return 0 }
        let host = Unmanaged<UIViewController>.fromOpaque(hostPointer).takeUnretainedValue()
        host.present(BoulderCaptureController(), animated: true)
        return 1
    }
}

@_cdecl("BoulderCapture_CopyStatus")
public func boulderCaptureCopyStatus() -> UnsafeMutablePointer<CChar>? {
    guard Thread.isMainThread else { return strdup("Call on the main thread.") }
    let value = MainActor.assumeIsolated { CaptureResult.status }
    return strdup(value)
}

@_cdecl("BoulderCapture_CopyGlbPath")
public func boulderCaptureCopyGlbPath() -> UnsafeMutablePointer<CChar>? {
    guard Thread.isMainThread else { return strdup("") }
    let value = MainActor.assumeIsolated { CaptureResult.glbPath }
    return strdup(value)
}

@_cdecl("BoulderCapture_CopyUsdzPath")
public func boulderCaptureCopyUsdzPath() -> UnsafeMutablePointer<CChar>? {
    guard Thread.isMainThread else { return strdup("") }
    let value = MainActor.assumeIsolated { CaptureResult.usdzPath }
    return strdup(value)
}

@_cdecl("BoulderCapture_CopyDiagnosticsPath")
public func boulderCaptureCopyDiagnosticsPath() -> UnsafeMutablePointer<CChar>? {
    guard Thread.isMainThread else { return strdup("") }
    let value = MainActor.assumeIsolated { SpikeDiagnostics.fileURL.path }
    return strdup(value)
}

@_cdecl("BoulderCapture_FreeString")
public func boulderCaptureFreeString(_ value: UnsafeMutablePointer<CChar>?) {
    free(value)
}
