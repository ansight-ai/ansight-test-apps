package dev.sdkless.notes;

import android.animation.ValueAnimator;
import android.app.Activity;
import android.app.AlertDialog;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import android.os.Bundle;
import android.text.InputType;
import android.util.Log;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.view.animation.LinearInterpolator;
import android.view.inputmethod.InputMethodManager;
import android.widget.BaseAdapter;
import android.widget.Button;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.widget.ListView;
import android.widget.Switch;
import android.widget.TextView;
import java.util.List;

public final class MainActivity extends Activity {
    private NotesDatabase store;
    private boolean editing;
    private boolean animate;
    private Long editedId;
    private EditText titleField;
    private EditText bodyField;
    private AnimationTrack animationTrack;

    @Override public void onCreate(Bundle state) {
        super.onCreate(state);
        store = new NotesDatabase(this);
        animate = state != null && state.getBoolean("animate");
        try {
            if (state != null && state.getBoolean("editing")) {
                Long id = state.containsKey("id") ? state.getLong("id") : null;
                showEditor(id, state.getString("title", ""), state.getString("body", ""));
            } else showNotes();
        } catch (RuntimeException error) { showError(error); }
    }

    private LinearLayout page(String title) {
        if (animationTrack != null) animationTrack.stop();
        LinearLayout page = new LinearLayout(this);
        page.setOrientation(LinearLayout.VERTICAL);
        page.setPadding(dp(20), dp(12), dp(20), dp(12));
        page.setBackgroundColor(Color.rgb(248, 249, 252));
        TextView heading = label(title, 25);
        if (android.os.Build.VERSION.SDK_INT >= 28) heading.setAccessibilityHeading(true);
        page.addView(heading, new LinearLayout.LayoutParams(-1, dp(48)));
        setContentView(page);
        return page;
    }

    private void showNotes() {
        List<NotesDatabase.Note> notes = store.all();
        editing = false;
        LinearLayout page = page("Notes Harness");
        LinearLayout actions = new LinearLayout(this);
        actions.addView(button("New note", R.id.new_note, () -> showEditor(null, "", "")), new LinearLayout.LayoutParams(0, dp(50), 1));
        actions.addView(button("Add samples", R.id.add_samples, () -> {
            try { store.addSamples(); showNotes(); } catch (RuntimeException error) { showError(error); }
        }), new LinearLayout.LayoutParams(0, dp(50), 1));
        page.addView(actions);
        TextView count = label(notes.size() + " notes · Saved on this device", 14);
        count.setId(R.id.note_count);
        page.addView(count, new LinearLayout.LayoutParams(-1, dp(38)));
        Switch toggle = new Switch(this);
        toggle.setText("Animate");
        toggle.setId(R.id.animation_toggle);
        toggle.setChecked(animate);
        page.addView(toggle, new LinearLayout.LayoutParams(-1, dp(44)));
        animationTrack = new AnimationTrack();
        page.addView(animationTrack, new LinearLayout.LayoutParams(-1, dp(24)));
        toggle.setOnCheckedChangeListener((view, checked) -> {
            animate = checked;
            if (checked) animationTrack.start(); else animationTrack.stop();
        });
        if (animate) animationTrack.start();
        if (notes.isEmpty()) {
            TextView empty = label("No notes yet. Tap New note.", 18);
            empty.setGravity(Gravity.CENTER);
            page.addView(empty, new LinearLayout.LayoutParams(-1, 0, 1));
        } else {
            ListView list = new ListView(this);
            list.setId(R.id.notes_list);
            list.setAdapter(new BaseAdapter() {
                @Override public int getCount() { return notes.size(); }
                @Override public Object getItem(int position) { return notes.get(position); }
                @Override public long getItemId(int position) { return notes.get(position).id; }
                @Override public boolean hasStableIds() { return true; }
                @Override public View getView(int position, View recycled, ViewGroup parent) {
                    NotesDatabase.Note note = notes.get(position);
                    LinearLayout row = new LinearLayout(MainActivity.this);
                    row.setOrientation(LinearLayout.VERTICAL);
                    row.setPadding(dp(4), dp(14), dp(4), dp(14));
                    TextView title = label(note.title, 18);
                    row.addView(title);
                    TextView preview = label(note.body.replace('\n', ' '), 14);
                    preview.setMaxLines(1);
                    row.addView(preview);
                    return row;
                }
            });
            list.setOnItemClickListener((parent, view, position, id) -> {
                NotesDatabase.Note note = notes.get(position);
                showEditor(note.id, note.title, note.body);
            });
            page.addView(list, new LinearLayout.LayoutParams(-1, 0, 1));
        }
    }

    private void showEditor(Long id, String title, String body) {
        editing = true;
        editedId = id;
        LinearLayout page = page(id == null ? "New note" : "Edit note");
        LinearLayout actions = new LinearLayout(this);
        actions.addView(button("Back to notes", R.id.back_to_notes, this::closeEditor), new LinearLayout.LayoutParams(0, dp(50), 1));
        actions.addView(button("Save note", R.id.save_note, () -> {
            try {
                store.save(editedId, titleField.getText().toString(), bodyField.getText().toString());
                Log.i("NotesHarness", "Saved note");
                closeEditor();
            } catch (RuntimeException error) { showError(error); }
        }), new LinearLayout.LayoutParams(0, dp(50), 1));
        page.addView(actions);
        titleField = new EditText(this);
        titleField.setId(R.id.note_title);
        titleField.setHint("Title");
        titleField.setContentDescription("Title");
        titleField.setSingleLine(true);
        titleField.setText(title);
        page.addView(titleField, new LinearLayout.LayoutParams(-1, dp(60)));
        page.addView(label("Note body", 16));
        bodyField = new EditText(this);
        bodyField.setId(R.id.note_body);
        bodyField.setContentDescription("Note body");
        bodyField.setInputType(InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_FLAG_MULTI_LINE | InputType.TYPE_TEXT_FLAG_CAP_SENTENCES);
        bodyField.setGravity(Gravity.TOP | Gravity.START);
        bodyField.setText(body);
        page.addView(bodyField, new LinearLayout.LayoutParams(-1, 0, 1));
        if (id != null) page.addView(button("Delete note", R.id.delete_note, () ->
            new AlertDialog.Builder(this).setTitle("Delete note?").setMessage("This removes the note from this device.")
                .setNegativeButton("Cancel", null).setPositiveButton("Delete", (dialog, which) -> {
                    try { store.delete(editedId); Log.i("NotesHarness", "Deleted note"); closeEditor(); }
                    catch (RuntimeException error) { showError(error); }
                }).show()), new LinearLayout.LayoutParams(-1, dp(50)));
    }

    private void closeEditor() {
        View focused = getCurrentFocus();
        if (focused != null) ((InputMethodManager)getSystemService(INPUT_METHOD_SERVICE)).hideSoftInputFromWindow(focused.getWindowToken(), 0);
        showNotes();
    }

    @Override public void onBackPressed() { if (editing) closeEditor(); else super.onBackPressed(); }
    @Override protected void onResume() { super.onResume(); if (!editing && animate && animationTrack != null) animationTrack.start(); }
    @Override protected void onPause() { if (animationTrack != null) animationTrack.stop(); super.onPause(); }
    @Override protected void onDestroy() { store.close(); super.onDestroy(); }
    @Override protected void onSaveInstanceState(Bundle state) {
        super.onSaveInstanceState(state);
        state.putBoolean("editing", editing);
        state.putBoolean("animate", animate);
        if (editing) {
            if (editedId != null) state.putLong("id", editedId);
            state.putString("title", titleField.getText().toString());
            state.putString("body", bodyField.getText().toString());
        }
    }

    private TextView label(String text, int size) {
        TextView view = new TextView(this);
        view.setText(text); view.setTextSize(size); view.setTextColor(Color.rgb(30, 40, 60));
        return view;
    }
    private Button button(String text, int id, Runnable action) {
        Button button = new Button(this);
        button.setText(text); button.setAllCaps(false); button.setId(id);
        button.setOnClickListener(view -> action.run());
        return button;
    }
    private void showError(RuntimeException error) {
        new AlertDialog.Builder(this).setTitle("Could not save notes").setMessage(error.getMessage()).setPositiveButton("OK", null).show();
    }
    private int dp(int value) { return Math.round(value * getResources().getDisplayMetrics().density); }

    private final class AnimationTrack extends View {
        private final Paint paint = new Paint(Paint.ANTI_ALIAS_FLAG);
        private ValueAnimator animator;
        private float position;
        AnimationTrack() { super(MainActivity.this); setBackgroundColor(Color.rgb(228, 233, 241)); }
        void start() {
            if (animator != null && animator.isStarted()) return;
            animator = ValueAnimator.ofFloat(0, 1);
            animator.setDuration(1200); animator.setRepeatCount(ValueAnimator.INFINITE);
            animator.setRepeatMode(ValueAnimator.REVERSE); animator.setInterpolator(new LinearInterpolator());
            animator.addUpdateListener(value -> { position = (float)value.getAnimatedValue(); invalidate(); });
            animator.start();
        }
        void stop() { if (animator != null) { animator.cancel(); animator = null; } }
        @Override protected void onDraw(Canvas canvas) {
            super.onDraw(canvas);
            paint.setColor(Color.rgb(38, 105, 224));
            float radius = dp(7);
            canvas.drawCircle(dp(11) + position * Math.max(0, getWidth() - dp(22)), getHeight() / 2f, radius, paint);
        }
    }
}
