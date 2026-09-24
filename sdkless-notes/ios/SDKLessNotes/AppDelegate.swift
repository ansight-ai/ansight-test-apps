import UIKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        let window = UIWindow(frame: UIScreen.main.bounds)
        do {
            let documents = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            let store = try NotesStore(url: documents.appendingPathComponent("notes.sqlite"))
            window.rootViewController = UINavigationController(rootViewController: NotesListController(store: store))
        } catch {
            let controller = UIViewController()
            let label = UILabel(frame: window.bounds.insetBy(dx: 24, dy: 100))
            label.numberOfLines = 0
            label.text = "Could not open notes: \(error.localizedDescription)"
            controller.view.backgroundColor = .systemBackground
            controller.view.addSubview(label)
            window.rootViewController = controller
        }
        self.window = window
        window.makeKeyAndVisible()
        return true
    }
}

final class NotesListController: UITableViewController {
    private let store: NotesStore
    private var notes: [Note] = []
    private let countLabel = UILabel()
    private let animationSwitch = UISwitch()
    private let track = UIView()
    private let dot = UIView()

    init(store: NotesStore) { self.store = store; super.init(style: .insetGrouped) }
    required init?(coder: NSCoder) { fatalError("Use init(store:)") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Notes"
        tableView.accessibilityIdentifier = "notes-list"
        let add = UIBarButtonItem(title: "New note", style: .plain, target: self, action: #selector(newNote))
        add.accessibilityIdentifier = "new-note"
        navigationItem.rightBarButtonItem = add
        let samples = UIBarButtonItem(title: "Add samples", style: .plain, target: self, action: #selector(addSamples))
        samples.accessibilityIdentifier = "add-samples"
        navigationItem.leftBarButtonItem = samples
        countLabel.font = .preferredFont(forTextStyle: .subheadline)
        countLabel.accessibilityIdentifier = "note-count"
        let animationLabel = UILabel()
        animationLabel.text = "Animate"
        animationSwitch.accessibilityLabel = "Animate"
        animationSwitch.accessibilityIdentifier = "animation-toggle"
        animationSwitch.addTarget(self, action: #selector(updateAnimation), for: .valueChanged)
        let row = UIStackView(arrangedSubviews: [animationLabel, animationSwitch])
        row.distribution = .equalSpacing
        track.backgroundColor = .tertiarySystemFill
        track.layer.cornerRadius = 8
        track.heightAnchor.constraint(equalToConstant: 22).isActive = true
        dot.backgroundColor = .systemBlue
        dot.layer.cornerRadius = 7
        track.addSubview(dot)
        let stack = UIStackView(arrangedSubviews: [countLabel, row, track])
        stack.axis = .vertical
        stack.spacing = 10
        stack.isLayoutMarginsRelativeArrangement = true
        stack.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 10, leading: 20, bottom: 10, trailing: 20)
        stack.frame = CGRect(x: 0, y: 0, width: view.bounds.width, height: 120)
        tableView.tableHeaderView = stack
    }

    override func viewWillAppear(_ animated: Bool) { super.viewWillAppear(animated); reloadNotes() }
    override func viewDidAppear(_ animated: Bool) { super.viewDidAppear(animated); updateAnimation() }
    override func viewWillDisappear(_ animated: Bool) { super.viewWillDisappear(animated); dot.layer.removeAllAnimations() }
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if !animationSwitch.isOn { dot.frame = CGRect(x: 4, y: 4, width: 14, height: 14) }
    }

    private func reloadNotes() {
        do {
            notes = try store.all()
            countLabel.text = "\(notes.count) notes · Saved on this device"
            tableView.reloadData()
            if notes.isEmpty {
                let label = UILabel()
                label.text = "No notes yet. Tap New note."
                label.textAlignment = .center
                label.accessibilityIdentifier = "empty-notes"
                tableView.backgroundView = label
            } else { tableView.backgroundView = nil }
        } catch { showError(error) }
    }

    @objc private func newNote() { open(nil) }
    @objc private func addSamples() { do { try store.addSamples(); reloadNotes() } catch { showError(error) } }
    @objc private func updateAnimation() {
        dot.layer.removeAllAnimations()
        dot.frame = CGRect(x: 4, y: 4, width: 14, height: 14)
        guard animationSwitch.isOn, view.window != nil else { return }
        UIView.animate(withDuration: 1.2, delay: 0, options: [.repeat, .autoreverse, .curveLinear, .allowUserInteraction]) {
            self.dot.frame.origin.x = max(4, self.track.bounds.width - 18)
        }
    }

    private func open(_ note: Note?) {
        navigationController?.pushViewController(NoteEditorController(store: store, note: note), animated: true)
    }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { notes.count }
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let note = notes[indexPath.row]
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        cell.textLabel?.text = note.title
        cell.detailTextLabel?.text = note.body.replacingOccurrences(of: "\n", with: " ")
        cell.accessoryType = .disclosureIndicator
        cell.accessibilityIdentifier = "note.\(note.id)"
        return cell
    }
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) { open(notes[indexPath.row]) }
}

final class NoteEditorController: UIViewController {
    private let store: NotesStore
    private let note: Note?
    private let titleField = UITextField()
    private let bodyField = UITextView()

    init(store: NotesStore, note: Note?) { self.store = store; self.note = note; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError("Use init(store:note:)") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        title = note == nil ? "New note" : "Edit note"
        let save = UIBarButtonItem(title: "Save note", style: .done, target: self, action: #selector(save))
        save.accessibilityIdentifier = "save-note"
        navigationItem.rightBarButtonItem = save
        titleField.borderStyle = .roundedRect
        titleField.placeholder = "Title"
        titleField.accessibilityLabel = "Title"
        titleField.accessibilityIdentifier = "note-title"
        titleField.text = note?.title
        titleField.font = .preferredFont(forTextStyle: .body)
        titleField.heightAnchor.constraint(equalToConstant: 46).isActive = true
        bodyField.text = note?.body ?? ""
        bodyField.font = .preferredFont(forTextStyle: .body)
        bodyField.backgroundColor = .secondarySystemBackground
        bodyField.layer.cornerRadius = 8
        bodyField.accessibilityLabel = "Note body"
        bodyField.accessibilityIdentifier = "note-body"
        let bodyLabel = UILabel()
        bodyLabel.text = "Note body"
        let stack = UIStackView(arrangedSubviews: [titleField, bodyLabel, bodyField])
        stack.axis = .vertical
        stack.spacing = 12
        if note != nil {
            let delete = UIButton(type: .system)
            delete.setTitle("Delete note", for: .normal)
            delete.tintColor = .systemRed
            delete.accessibilityIdentifier = "delete-note"
            delete.addTarget(self, action: #selector(confirmDelete), for: .touchUpInside)
            delete.heightAnchor.constraint(equalToConstant: 44).isActive = true
            stack.addArrangedSubview(delete)
        }
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            stack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -20),
            stack.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor, constant: -12)
        ])
    }

    @objc private func save() {
        do {
            try store.save(id: note?.id, title: titleField.text ?? "", body: bodyField.text)
            NSLog("Notes Harness: saved note")
            navigationController?.popViewController(animated: true)
        } catch { showError(error) }
    }

    @objc private func confirmDelete() {
        let alert = UIAlertController(title: "Delete note?", message: "This removes the note from this device.", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Delete", style: .destructive) { _ in
            do {
                try self.store.delete(id: self.note!.id)
                NSLog("Notes Harness: deleted note")
                self.navigationController?.popViewController(animated: true)
            } catch { self.showError(error) }
        })
        present(alert, animated: true)
    }
}

private extension UIViewController {
    func showError(_ error: Error) {
        let alert = UIAlertController(title: "Could not save notes", message: error.localizedDescription, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}
