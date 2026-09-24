package dev.sdkless.notes;

import android.app.Activity;
import android.app.Instrumentation;
import android.os.Bundle;
import java.io.File;

// Uses only the Android platform instrumentation API. No testing SDK dependencies.
public final class StoreInstrumentation extends Instrumentation {
    @Override public void onCreate(Bundle arguments) { super.onCreate(arguments); start(); }
    @Override public void onStart() {
        Bundle result = new Bundle();
        File file = new File(getTargetContext().getFilesDir(), "notes-check.sqlite");
        NotesDatabase store = null;
        try {
            android.database.sqlite.SQLiteDatabase.deleteDatabase(file);
            store = new NotesDatabase(getTargetContext(), file.getName());
            store.save(null, "O'Brien ☕", "Line one\nLine two — café");
            NotesDatabase.Note note = store.all().get(0);
            check(note.title.equals("O'Brien ☕") && note.body.equals("Line one\nLine two — café"), "Unicode and SQL parameters");
            store.close();
            store = new NotesDatabase(getTargetContext(), file.getName());
            check(store.all().size() == 1, "Persistence after reopen");
            store.save(note.id, "Updated", "Still stored");
            check(store.all().get(0).body.equals("Still stored"), "Update");
            store.delete(note.id);
            check(store.all().isEmpty(), "Delete");
            try { store.save(null, "   ", "Must not persist"); throw new AssertionError("Blank title accepted"); }
            catch (IllegalArgumentException expected) { }
            store.addSamples();
            check(store.all().size() == 50, "Sample transaction");
            result.putString("stream", "PASS: insert, Unicode/quotes, reopen, update, delete, validation, and sample transaction\n");
            finish(Activity.RESULT_OK, result);
        } catch (Throwable error) {
            result.putString("stream", "FAIL: " + android.util.Log.getStackTraceString(error));
            finish(Activity.RESULT_CANCELED, result);
        } finally {
            if (store != null) store.close();
            android.database.sqlite.SQLiteDatabase.deleteDatabase(file);
        }
    }
    private static void check(boolean condition, String message) { if (!condition) throw new AssertionError(message); }
}
