import UIKit

/// Receives Simulator's Device > Shake Gesture through UIKit's responder chain.
final class MotionViewController: UIViewController {
    private let countLabel = UILabel()
    private let statusLabel = UILabel()
    private var shakeCount = 0

    override var canBecomeFirstResponder: Bool { true }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 0.07, green: 0.11, blue: 0.17, alpha: 1)

        let title = makeLabel("Motion Harness", size: 28, weight: .bold)
        let instructions = makeLabel(
            "Choose Device > Shake Gesture in Simulator. The app should report the UIKit shake event below.",
            size: 16,
            weight: .regular
        )
        countLabel.accessibilityIdentifier = "motion-shake-count"
        statusLabel.accessibilityIdentifier = "motion-shake-status"

        let resetButton = UIButton(type: .system)
        resetButton.setTitle("RESET COUNTERS", for: .normal)
        resetButton.accessibilityIdentifier = "motion-reset"
        resetButton.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
        resetButton.addTarget(self, action: #selector(resetCounters), for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [title, instructions, countLabel, statusLabel, resetButton])
        stack.axis = .vertical
        stack.spacing = 18
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -24),
            stack.centerYAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerYAnchor)
        ])
        render()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        becomeFirstResponder()
    }

    override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        guard motion == .motionShake else {
            super.motionEnded(motion, with: event)
            return
        }
        shakeCount += 1
        render()
    }

    @objc private func resetCounters() {
        shakeCount = 0
        render()
        becomeFirstResponder()
    }

    private func render() {
        countLabel.text = "Shake count: \(shakeCount)"
        statusLabel.text = shakeCount > 0 ? "Shake detected" : "Shake waiting"
    }

    private func makeLabel(_ text: String, size: CGFloat, weight: UIFont.Weight) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = .systemFont(ofSize: size, weight: weight)
        label.textColor = .white
        label.numberOfLines = 0
        return label
    }
}
