package dev.sdkless.notes;

import android.content.ContentValues;
import android.content.Context;
import android.database.Cursor;
import android.database.sqlite.SQLiteDatabase;
import android.database.sqlite.SQLiteOpenHelper;
import java.io.File;
import java.time.Instant;
import java.util.ArrayList;
import java.util.List;

final class NotesDatabase extends SQLiteOpenHelper {
    static final class Note {
        final long id;
        final String title;
        final String body;
        Note(long id, String title, String body) { this.id = id; this.title = title; this.body = body; }
    }

    NotesDatabase(Context context) { this(context, "notes.sqlite"); }
    NotesDatabase(Context context, String filename) {
        super(context, new File(context.getFilesDir(), filename).getAbsolutePath(), null, 1);
        setWriteAheadLoggingEnabled(false);
    }

    @Override public void onConfigure(SQLiteDatabase database) {
        super.onConfigure(database);
        try (Cursor mode = database.rawQuery("PRAGMA journal_mode=DELETE", null)) { mode.moveToFirst(); }
    }

    @Override public void onCreate(SQLiteDatabase database) {
        database.execSQL("CREATE TABLE notes (id INTEGER PRIMARY KEY AUTOINCREMENT, title TEXT NOT NULL, body TEXT NOT NULL, created_at TEXT NOT NULL, updated_at TEXT NOT NULL)");
    }

    @Override public void onUpgrade(SQLiteDatabase database, int oldVersion, int newVersion) {
        throw new IllegalStateException("Unsupported notes schema upgrade");
    }

    List<Note> all() {
        List<Note> result = new ArrayList<>();
        try (Cursor rows = getReadableDatabase().rawQuery("SELECT id, title, body FROM notes ORDER BY updated_at DESC, id DESC", null)) {
            while (rows.moveToNext()) result.add(new Note(rows.getLong(0), rows.getString(1), rows.getString(2)));
        }
        return result;
    }

    void save(Long id, String title, String body) {
        title = title.trim();
        if (title.isEmpty()) throw new IllegalArgumentException("Enter a title before saving.");
        ContentValues values = new ContentValues();
        values.put("title", title);
        values.put("body", body);
        String now = Instant.now().toString();
        values.put("updated_at", now);
        if (id == null) {
            values.put("created_at", now);
            getWritableDatabase().insertOrThrow("notes", null, values);
        } else {
            getWritableDatabase().update("notes", values, "id=?", new String[] { id.toString() });
        }
    }

    void delete(long id) { getWritableDatabase().delete("notes", "id=?", new String[] { Long.toString(id) }); }

    void addSamples() {
        SQLiteDatabase database = getWritableDatabase();
        database.beginTransaction();
        try {
            for (int index = 1; index <= 50; index++)
                save(null, "Sample note " + index, "A local SQLite note for scrolling and persistence checks.\nSample " + index + " — café ☕");
            database.setTransactionSuccessful();
        } finally { database.endTransaction(); }
    }
}
