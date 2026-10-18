import type { TaskDefinition, TaskInvocation } from "./ansight-task.d.ts";

export const task = {
  "schemaVersion": 1,
  "appId": "ai.ansight.testapps.keyboard",
  "title": "Dismiss the keyboard without closing the root MAUI page",
  "description": "Exercise Entry and Editor keyboards, repeat dismissal when already closed, and verify retained text and a responsive root page.",
  "feature": "keyboard",
  "keywords": ["Evergine", "IME", "root page", "dismiss", "Back"],
  "platforms": ["android", "ios"],
  "requires": { "appTools": ["ui.dismiss_keyboard"] },
  "inputSchema": { "type": "object", "properties": {}, "additionalProperties": false },
  "timeoutSeconds": 180,
  "maximumActions": 50
} satisfies TaskDefinition;

export default async function runTask({ ansight, expect }: TaskInvocation) {
  const root = await ansight.ui.waitFor({ automationId: "keyboard.root-marker", timeoutMs: 5000 });
  expect(root.satisfied, { id: "root-page-ready" }).toBe(true);
  await ansight.ui.tap({ automationId: "keyboard.reset" });

  const entryOpen = await ansight.keyboard.open({ automationId: "keyboard.entry" });
  expect(entryOpen.isOpen, { id: "entry-keyboard-open" }).toBe(true);
  await ansight.ui.typeText({ automationId: "keyboard.entry", value: "Entry survives dismissal", replaceExisting: true });
  expect((await ansight.keyboard.isOpen()).isOpen, { id: "entry-keyboard-confirmed-open" }).toBe(true);
  const entryDismiss = await ansight.keyboard.dismiss();
  expect(entryDismiss.isOpen, { id: "entry-keyboard-dismissed" }).toBe(false);
  expect(entryDismiss.inputBackend, { id: "entry-dismissed-with-input-method" }).toBe("app-input-method");
  expect((await ansight.ui.assert({ automationId: "keyboard.root-marker", expectedText: "Root page active" })).passed,
    { id: "root-preserved-after-entry-dismissal" }).toBe(true);
  expect((await ansight.ui.assert({ automationId: "keyboard.entry", expectedText: "Entry survives dismissal" })).passed,
    { id: "entry-text-preserved" }).toBe(true);

  const entryRepeat = await ansight.keyboard.dismiss();
  expect(entryRepeat.isOpen, { id: "entry-keyboard-stays-closed" }).toBe(false);
  expect(entryRepeat.performed, { id: "closed-keyboard-dismissal-is-no-op" }).toBe(false);
  await ansight.ui.tap({ automationId: "keyboard.verify" });
  expect((await ansight.ui.assert({ automationId: "keyboard.response", expectedText: "Response count: 1" })).passed,
    { id: "root-responsive-after-repeated-dismissal" }).toBe(true);

  const editorOpen = await ansight.keyboard.open({ automationId: "keyboard.editor" });
  expect(editorOpen.isOpen, { id: "editor-keyboard-open" }).toBe(true);
  await ansight.ui.typeText({ automationId: "keyboard.editor", value: "Editor survives dismissal", replaceExisting: true });
  expect((await ansight.keyboard.isOpen()).isOpen, { id: "editor-keyboard-confirmed-open" }).toBe(true);
  const editorDismiss = await ansight.keyboard.dismiss();
  expect(editorDismiss.isOpen, { id: "editor-keyboard-dismissed" }).toBe(false);
  expect(editorDismiss.inputBackend, { id: "editor-dismissed-with-input-method" }).toBe("app-input-method");
  const editorRepeat = await ansight.keyboard.dismiss();
  expect(editorRepeat.isOpen, { id: "editor-keyboard-stays-closed" }).toBe(false);
  expect(editorRepeat.performed, { id: "editor-repeat-is-no-op" }).toBe(false);
  expect((await ansight.ui.assert({ automationId: "keyboard.root-marker", expectedText: "Root page active" })).passed,
    { id: "root-preserved-after-editor-dismissal" }).toBe(true);
  expect((await ansight.ui.assert({ automationId: "keyboard.entry", expectedText: "Entry survives dismissal" })).passed,
    { id: "entry-text-preserved-after-focus-change" }).toBe(true);
  expect((await ansight.ui.assert({ automationId: "keyboard.editor", expectedText: "Editor survives dismissal" })).passed,
    { id: "editor-text-preserved" }).toBe(true);
  await ansight.ui.tap({ automationId: "keyboard.verify" });
  expect((await ansight.ui.assert({ automationId: "keyboard.response", expectedText: "Response count: 2" })).passed,
    { id: "root-responsive-after-both-inputs" }).toBe(true);
  expect((await ansight.keyboard.isOpen()).isOpen, { id: "final-keyboard-closed" }).toBe(false);
  return { rootPagePreserved: true, entryTextPreserved: true, editorTextPreserved: true, responseCount: 2 };
}
