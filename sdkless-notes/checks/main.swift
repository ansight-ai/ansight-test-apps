import Foundation

let directory = FileManager.default.temporaryDirectory.appendingPathComponent("sdkless-notes-check-\(UUID().uuidString)")
defer { try? FileManager.default.removeItem(at: directory) }
let database = directory.appendingPathComponent("notes.sqlite")
var store: NotesStore? = try NotesStore(url: database)
try store!.save(id: nil, title: "O'Brien ☕", body: "Line one\nLine two — café")
let original = try store!.all().first!
precondition(original.title == "O'Brien ☕")
precondition(original.body == "Line one\nLine two — café")
store = nil
store = try NotesStore(url: database)
let reopened = try store!.all()
precondition(reopened.count == 1)
try store!.save(id: original.id, title: "Updated", body: "Still stored")
let updated = try store!.all()
precondition(updated.first!.body == "Still stored")
try store!.delete(id: original.id)
let deleted = try store!.all()
precondition(deleted.isEmpty)
do {
    try store!.save(id: nil, title: "   ", body: "Must not persist")
    fatalError("Blank titles must be rejected")
} catch { }
try store!.addSamples()
let seeded = try store!.all()
precondition(seeded.count == 50)
store = nil
store = try NotesStore(url: database)
let persistedSamples = try store!.all()
precondition(persistedSamples.count == 50)
print("PASS: insert, Unicode/quotes, reopen, update, delete, validation, and sample transaction")
