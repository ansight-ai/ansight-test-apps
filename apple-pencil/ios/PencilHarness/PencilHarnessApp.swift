import SwiftUI
import UIKit
import Ansight
import AnsightPencil
import AnsightPencilRuntime

@main
struct PencilHarnessApp: App {
    var body: some Scene {
        WindowGroup {
            CanvasHost().ignoresSafeArea().task {
                do {
                    let options = try AnsightOptions.createBuilder(AnsightOptions(
                        enableFramesPerSecond: false,
                        sessionJpegCapture: AnsightSessionJpegCaptureOptions(intervalMilliseconds: 100, quality: 85, maxWidth: 1200),
                        touchCapture: AnsightTouchCaptureOptions(),
                        toolGuard: .readOnly,
                        hostAutoProbe: AnsightHostAutoProbeOptions(clientName: "Pencil HID verification"),
                        hostConnection: AnsightHostConnectionOptions(discoveryPort: 49332)
                    )).withSimulatorPenInput().build()
                    try AnsightRuntime.shared.initializeAndActivateAnsightSdk(options: options)
                    _ = await AnsightRuntime.shared.connect(.auto(clientName: "Pencil HID verification"))
                } catch { print("PENCIL SDK: \(error)") }
            }
        }
    }
}
struct CanvasHost: UIViewRepresentable {
    func makeUIView(context: Context) -> PencilCanvas { PencilCanvas() }
    func updateUIView(_ view: PencilCanvas, context: Context) {}
}
final class PencilCanvas: UIView {
    private var strokes: [(UIBezierPath, CGFloat)] = []
    private var lastPoint: CGPoint?
    private var pencilCount = 0
    private var fingerCount = 0
    private var hoverCount = 0
    private var status = "Waiting for HID input"
    private let titleLabel = UILabel()
    private let statusLabel = UILabel()
    private var observations: [[String: Any]] = []

    init() {
        super.init(frame: .zero)
        backgroundColor = UIColor(red: 0.04, green: 0.07, blue: 0.12, alpha: 1)
        accessibilityIdentifier = "pencil-canvas"
        isMultipleTouchEnabled = true
        titleLabel.text = "PENCIL / HID LAB"
        titleLabel.textColor = .white
        titleLabel.font = .monospacedSystemFont(ofSize: 26, weight: .bold)
        statusLabel.textColor = .systemMint
        statusLabel.font = .monospacedSystemFont(ofSize: 16, weight: .medium)
        statusLabel.numberOfLines = 0
        statusLabel.accessibilityIdentifier = "pencil-received-status"
        addSubview(titleLabel); addSubview(statusLabel)
        let hover = UIHoverGestureRecognizer(target: self, action: #selector(hovered(_:)))
        hover.name = "pencil-hover"
        hover.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.pencil.rawValue)]
        addGestureRecognizer(hover)
        updateStatus()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layoutSubviews() {
        titleLabel.frame = CGRect(x: 40, y: 60, width: bounds.width - 80, height: 40)
        statusLabel.frame = CGRect(x: 40, y: 110, width: bounds.width - 80, height: 110)
    }
    override func draw(_ rect: CGRect) {
        UIColor.white.withAlphaComponent(0.07).setStroke()
        let grid = UIBezierPath()
        for x in stride(from: CGFloat(40), to: bounds.width, by: 40) {
            grid.move(to: CGPoint(x: x, y: 260)); grid.addLine(to: CGPoint(x: x, y: bounds.height - 40))
        }
        for y in stride(from: CGFloat(260), to: bounds.height - 40, by: 40) {
            grid.move(to: CGPoint(x: 40, y: y)); grid.addLine(to: CGPoint(x: bounds.width - 40, y: y))
        }
        grid.stroke()
        UIColor.systemMint.setStroke()
        for (path, width) in strokes { path.lineWidth = width; path.lineCapStyle = .round; path.stroke() }
    }
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) { receive(touches, event: event, phase: "down") }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) { receive(touches, event: event, phase: "move") }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) { receive(touches, event: event, phase: "up"); lastPoint = nil }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { receive(touches, event: event, phase: "cancel"); lastPoint = nil }
    private func receive(_ touches: Set<UITouch>, event: UIEvent?, phase: String) {
        for touch in touches {
            for sample in event?.coalescedTouches(for: touch) ?? [touch] {
                let point = sample.location(in: self)
                let pencil = sample.type == .pencil
                if pencil { pencilCount += 1 } else { fingerCount += 1 }
                let pressure = sample.maximumPossibleForce > 0 ? sample.force / sample.maximumPossibleForce : 0
                status = String(format: "%@  pressure %.3f  altitude %.3f\nazimuth %.3f  roll %.3f", pencil ? "PENCIL" : "FINGER", pressure, sample.altitudeAngle, sample.azimuthAngle(in: self), sample.rollAngle)
                observations.append(["timestamp": sample.timestamp, "phase": phase, "tool": pencil ? "stylus" : "finger", "x": point.x, "y": point.y, "pressure": pressure, "altitude": sample.altitudeAngle, "azimuth": sample.azimuthAngle(in: self), "roll": sample.rollAngle])
                let path = UIBezierPath(); path.move(to: lastPoint ?? point)
                path.addLine(to: CGPoint(x: point.x + (lastPoint == nil ? 0.1 : 0), y: point.y))
                strokes.append((path, 2 + pressure * 12)); lastPoint = point
            }
        }
        updateStatus(); setNeedsDisplay(); persist()
    }
    @objc private func hovered(_ recognizer: UIHoverGestureRecognizer) {
        hoverCount += 1
        let point = recognizer.location(in: self)
        observations.append(["state": recognizer.state.rawValue, "phase": "hover", "tool": "stylus", "x": point.x, "y": point.y, "distance": recognizer.zOffset, "roll": recognizer.rollAngle])
        updateStatus(); persist()
    }
    private func updateStatus() {
        statusLabel.text = "Pencil samples: \(pencilCount)  Finger samples: \(fingerCount)  Hover: \(hoverCount)\n\(status)"
    }
    private func persist() {
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("pencil-observations.json")
        if let data = try? JSONSerialization.data(withJSONObject: observations, options: [.prettyPrinted, .sortedKeys]) { try? data.write(to: url, options: .atomic) }
    }
}

// Hosted XCTest uses the app's linked runtime, avoiding a second copy of static SDK objects.
enum PencilTestBridge {
    static var isCaptured: Bool { AnsightRuntime.shared.hostConnectionStatus().isConnected && AnsightRuntime.shared.snapshot().touchCaptureActive }
    static func execute(_ json: String) -> String { ANSPencilRuntime.execute(argumentsJson: json) }
}
