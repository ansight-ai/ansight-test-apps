import XCTest
import UIKit
import ObjectiveC.runtime
@testable import PencilHarness

@MainActor
final class PencilIsolationTests: XCTestCase {
    private var runId = UUID().uuidString
    private var container: UIView!
    private var canvas: UIView!
    private var sibling: UIView!
    private var window: UIWindow!

    override func setUp() async throws {
        // The host app includes Ansight and records these tests as well as the HID task.
        for _ in 0..<100 {
            if PencilTestBridge.isCaptured { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertTrue(PencilTestBridge.isCaptured, "The test host must be SDK-connected and captured.")
        window = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows).first { $0.isKeyWindow })
        container = UIView(frame: window.bounds)
        canvas = UIView(frame: CGRect(x: 0, y: 0, width: window.bounds.width / 2, height: window.bounds.height))
        canvas.accessibilityIdentifier = "isolation-canvas"
        sibling = UIView(frame: CGRect(x: window.bounds.width / 2, y: 0, width: window.bounds.width / 2, height: window.bounds.height))
        container.addSubview(canvas); container.addSubview(sibling); window.addSubview(container)
        runId = UUID().uuidString
    }
    override func tearDown() async throws {
        _ = call("finish")
        container.removeFromSuperview()
    }
    private func sample(_ phase: String = "down", timestamp: Double? = nil) -> [String: Any] {
        var result: [String: Any] = ["phase": phase, "x": 0.25, "y": 0.5, "pressure": phase == "down" ? 0.83 : 0, "altitudeRadians": 0.4]
        if let timestamp { result["eventTimestamp"] = timestamp }
        return result
    }
    private func call(_ action: String, _ args: [String: Any] = [:], id: String? = nil) -> [String: Any] {
        var input = args; input["action"] = action; input["runId"] = id ?? runId
        let json = String(data: try! JSONSerialization.data(withJSONObject: input), encoding: .utf8)!
        return try! JSONSerialization.jsonObject(with: Data(PencilTestBridge.execute(json).utf8)) as! [String: Any]
    }
    private func prepare(hover: String? = nil) -> [String: Any] {
        var args: [String: Any] = ["target": "isolation-canvas", "samples": [sample(), sample("up")]]
        if let hover { args["hoverRecognizer"] = hover }
        return call("prepare", args)
    }
    private func touch(_ timestamp: Double, view: UIView? = nil, type: UITouch.TouchType = .pencil, phase: UITouch.Phase = .began) -> ProbeTouch {
        ProbeTouch(time: timestamp, target: view ?? canvas, window: window, type: type, phase: phase,
                   point: CGPoint(x: window.bounds.width * 0.25, y: window.bounds.height * 0.5))
    }
    private func recognizer(_ view: UIView, name: String) -> UIHoverGestureRecognizer {
        let value = UIHoverGestureRecognizer(target: nil, action: nil)
        value.name = name; value.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.pencil.rawValue)]
        view.addGestureRecognizer(value)
        return value
    }

    func testRejectsMissingAmbiguousAndOutOfSurfaceTargets() {
        XCTAssertEqual(call("prepare", ["samples": [sample(), sample("up")]])["errorCode"] as? String, "pen_target_unavailable")
        sibling.accessibilityIdentifier = "isolation-canvas"
        XCTAssertEqual(prepare()["errorCode"] as? String, "pen_target_unavailable")
        sibling.accessibilityIdentifier = nil
        var outside = sample(); outside["x"] = 0.75
        XCTAssertEqual(call("prepare", ["target": "isolation-canvas", "samples": [outside, sample("up")]])["errorCode"] as? String, "pen_target_unavailable")
    }

    func testExactTimestampAndObjectScopePreventCrossContactContamination() {
        XCTAssertEqual(prepare()["success"] as? Bool, true)
        let timestamp = ProcessInfo.processInfo.systemUptime
        XCTAssertEqual(call("arm", ["sample": sample(timestamp: timestamp)])["success"] as? Bool, true)
        let intended = touch(timestamp)
        XCTAssertEqual(intended.force, 0.83, accuracy: 0.001)
        XCTAssertEqual(touch(timestamp + 0.00001).force, 0)
        XCTAssertEqual(touch(timestamp + 0.00000001).force, 0)
        XCTAssertEqual(touch(timestamp + 0.0000000002).force, 0.83, accuracy: 0.001)
        XCTAssertEqual(touch(timestamp, view: sibling).force, 0)
        XCTAssertEqual(touch(timestamp, type: .direct).force, 0)
        XCTAssertEqual(touch(timestamp, phase: .moved).force, 0)
        // A coalesced copy of the same identified HID sample can still read its properties.
        XCTAssertEqual(touch(timestamp).force, 0.83, accuracy: 0.001)
        _ = call("finish")
        XCTAssertEqual(intended.force, 0)
    }

    func testWrongRunAndStaleTimestampsCannotArmOverrides() {
        XCTAssertEqual(prepare()["success"] as? Bool, true)
        let now = ProcessInfo.processInfo.systemUptime
        XCTAssertEqual(call("arm", ["sample": sample(timestamp: now)], id: UUID().uuidString)["success"] as? Bool, false)
        XCTAssertEqual(touch(now).force, 0)
        XCTAssertEqual(call("arm", ["sample": sample(timestamp: now - 10)])["errorCode"] as? String, "pen_timestamp_invalid")
        XCTAssertEqual(touch(now - 10).force, 0)
    }

    func testDetachingOrMovingTargetEndsRunBeforeInjection() {
        XCTAssertEqual(prepare()["success"] as? Bool, true)
        canvas.frame.origin.y += 1
        XCTAssertEqual(call("arm", ["sample": sample(timestamp: ProcessInfo.processInfo.systemUptime)])["errorCode"] as? String, "pen_target_unavailable")
        canvas.frame.origin.y -= 1
        XCTAssertEqual(prepare()["success"] as? Bool, true)
        canvas.removeFromSuperview()
        XCTAssertEqual(call("arm", ["sample": sample(timestamp: ProcessInfo.processInfo.systemUptime)])["errorCode"] as? String, "pen_target_unavailable")
    }

    func testHoverOnlyOwnsExplicitRecognizerAndNeverAncestorsOrSiblings() {
        let selected = recognizer(canvas, name: "selected")
        let other = recognizer(canvas, name: "other")
        let ancestor = recognizer(container, name: "selected")
        let outside = recognizer(sibling, name: "selected")
        XCTAssertEqual(prepare(hover: "selected")["success"] as? Bool, true)
        XCTAssertEqual(call("hover", ["sample": sample("hoverEnter")])["success"] as? Bool, true)
        XCTAssertEqual(selected.state, .began)
        XCTAssertEqual(other.state, .possible); XCTAssertEqual(ancestor.state, .possible); XCTAssertEqual(outside.state, .possible)
        _ = call("finish")
        XCTAssertFalse([UIGestureRecognizer.State.began, .changed].contains(selected.state))
        XCTAssertEqual(other.state, .possible); XCTAssertEqual(ancestor.state, .possible); XCTAssertEqual(outside.state, .possible)
    }

    func testBusyAmbiguousOrRemovedHoverRecognizerIsNeverTakenOver() {
        let selected = recognizer(canvas, name: "selected")
        selected.state = .began
        XCTAssertEqual(prepare(hover: "selected")["errorCode"] as? String, "pen_hover_unavailable")
        XCTAssertEqual(selected.state, .began)
        canvas.removeGestureRecognizer(selected)
        let first = recognizer(canvas, name: "duplicate")
        let second = recognizer(canvas, name: "duplicate")
        XCTAssertEqual(prepare(hover: "duplicate")["errorCode"] as? String, "pen_hover_unavailable")
        canvas.removeGestureRecognizer(second)
        XCTAssertEqual(prepare(hover: "duplicate")["success"] as? Bool, true)
        canvas.removeGestureRecognizer(first)
        XCTAssertEqual(call("hover", ["sample": sample("hoverEnter")])["errorCode"] as? String, "pen_hover_unavailable")
        XCTAssertEqual(first.state, .possible)
    }

    func testHoverExitValuesSurviveUntilAppCallbackAndThenPassThrough() async throws {
        let observer = HoverObserver()
        let selected = UIHoverGestureRecognizer(target: observer, action: #selector(HoverObserver.receive(_:)))
        selected.name = "selected"; selected.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.pencil.rawValue)]
        canvas.addGestureRecognizer(selected)
        XCTAssertEqual(prepare(hover: "selected")["success"] as? Bool, true)
        XCTAssertEqual(call("hover", ["sample": sample("hoverEnter")])["success"] as? Bool, true)
        try await Task.sleep(for: .milliseconds(40))
        var exit = sample("hoverExit"); exit["distance"] = 0.7
        XCTAssertEqual(call("hover", ["sample": exit])["success"] as? Bool, true)
        try await Task.sleep(for: .milliseconds(40))
        let observed = try XCTUnwrap(observer.endedPoint)
        XCTAssertEqual(observed.x, window.bounds.width * 0.25, accuracy: 0.001)
        XCTAssertEqual(observed.y, window.bounds.height * 0.5, accuracy: 0.001)
        XCTAssertEqual(observer.endedDistance, 0.7, accuracy: 0.001)
        XCTAssertEqual(selected.state, .possible)
        XCTAssertEqual(selected.zOffset, 0)
    }

    func testAConflictingGetterPreventsAnyHookInstallation() throws {
        let method = try XCTUnwrap(class_getInstanceMethod(UITouch.self, #selector(getter: UITouch.force)))
        let altitude = try XCTUnwrap(class_getInstanceMethod(UITouch.self, #selector(getter: UITouch.altitudeAngle)))
        let saved = method_getImplementation(method)
        let savedAltitude = method_getImplementation(altitude)
        let replacement: @convention(block) (UITouch) -> CGFloat = { _ in 0.47 }
        let other = imp_implementationWithBlock(replacement)
        method_setImplementation(method, other)
        defer { method_setImplementation(method, saved); imp_removeBlock(other) }
        XCTAssertEqual(prepare()["errorCode"] as? String, "pen_hook_conflict")
        XCTAssertTrue(method_getImplementation(method) == other)
        XCTAssertTrue(method_getImplementation(altitude) == savedAltitude)
    }

    func testHookChangedDuringPlaybackStopsOverridesAndPreservesOtherLibrary() throws {
        XCTAssertEqual(prepare()["success"] as? Bool, true)
        let method = try XCTUnwrap(class_getInstanceMethod(UITouch.self, #selector(getter: UITouch.force)))
        let saved = method_getImplementation(method)
        let replacement: @convention(block) (UITouch) -> CGFloat = { _ in 0.47 }
        let other = imp_implementationWithBlock(replacement)
        method_setImplementation(method, other)
        defer { method_setImplementation(method, saved); imp_removeBlock(other) }
        XCTAssertEqual(call("arm", ["sample": sample(timestamp: ProcessInfo.processInfo.systemUptime)])["errorCode"] as? String, "pen_hook_conflict")
        XCTAssertTrue(method_getImplementation(method) == other)
    }

    func testHookConflictFailsWithoutReplacingOtherImplementation() throws {
        let method = try XCTUnwrap(class_getInstanceMethod(UITouch.self, #selector(getter: UITouch.force)))
        let saved = method_getImplementation(method)
        let replacement: @convention(block) (UITouch) -> CGFloat = { _ in 0.47 }
        let other = imp_implementationWithBlock(replacement)
        method_setImplementation(method, other)
        defer { method_setImplementation(method, saved); imp_removeBlock(other) }
        XCTAssertEqual(prepare()["errorCode"] as? String, "pen_hook_conflict")
        XCTAssertTrue(method_getImplementation(method) == other)
        XCTAssertEqual(touch(1).force, 0.47, accuracy: 0.001)
    }
}

@MainActor
private final class ProbeTouch: UITouch {
    let time: Double
    weak var target: UIView?
    weak var owner: UIWindow?
    let tool: UITouch.TouchType
    let transition: UITouch.Phase
    let point: CGPoint
    init(time: Double, target: UIView, window: UIWindow, type: UITouch.TouchType, phase: UITouch.Phase, point: CGPoint) {
        self.time = time; self.target = target; self.owner = window; tool = type; transition = phase; self.point = point
        super.init()
    }
    override var timestamp: TimeInterval { time }
    override var window: UIWindow? { owner }
    override var view: UIView? { target }
    override var type: UITouch.TouchType { tool }
    override var phase: UITouch.Phase { transition }
    override func location(in view: UIView?) -> CGPoint { view?.convert(point, from: owner) ?? point }
}

@MainActor
private final class HoverObserver: NSObject {
    var endedPoint: CGPoint?
    var endedDistance: CGFloat = 0
    @objc func receive(_ recognizer: UIHoverGestureRecognizer) {
        if recognizer.state == .ended {
            endedPoint = recognizer.location(in: recognizer.view?.window)
            endedDistance = recognizer.zOffset
        }
    }
}
