import type { TaskDefinition, TaskInvocation } from "./ansight-task.d.ts";

export const task = {
  "schemaVersion": 1,
  "appId": "ai.ansight.pencil.flutter",
  "title": "Play and verify Flutter Pencil framework input",
  "description": "Play the pen fixture; verify SDK-captured Pencil contact, pressure, tilt, barrel roll, hover and taps.",
  "startingState": "Flutter Pencil harness is foreground in an iPad Simulator with pen simulation opted in and the Ansight SDK connected and recording.",
  "successState": "The SDK has recorded simulated Pencil contact and hover with varying pressure and angles; a final screenshot is retained.",
  "feature": "pencil",
  "requires": {
    "appTools": [
      "ui.simulate_pen_framework",
      "ui.get_screenshot"
    ]
  },
  "timeoutSeconds": 40,
  "maximumActions": 16
} satisfies TaskDefinition;

export default async function runTask({ ansight, expect }: TaskInvocation) {
  const startUtc = new Date().toISOString();
  const playback = await ansight.ui.playPen({ file: "ansight/fixtures/pencil-demo.pen.json", mode: "sdk", target: "drawing-canvas" });
  expect(playback.performed, { id: "pen-file-delivered" }).toBe(true);
  await ansight.screenshots.take();
  const context = await ansight.touches.getContext({ startUtc, timestampUtc: startUtc, before: 0, after: 200, limit: 200 });
  const samples = context.touches.filter(touch => touch.details?.tool === "stylus");
  const contact = samples.filter(touch => touch.details?.inputSource === "simulator-sdk-framework" && !touch.action.startsWith("hover"));
  const hover = samples.filter(touch => touch.details?.inputSource === "simulator-sdk-framework" && touch.action.startsWith("hover"));
  const spread = (values: number[]) => values.length ? Math.max(...values) - Math.min(...values) : 0;
  expect(contact.length > 40, { id: "sdk-captured-pencil-contact" }).toBe(true);
  expect(samples.some(touch => touch.action === "up"), { id: "pencil-contact-released" }).toBe(true);
  expect(contact.filter(touch => touch.action === "down").length, { id: "stroke-and-three-taps" }).toBe(4);
  expect(spread(contact.map(touch => touch.details?.force ?? 0)) > .7, { id: "received-variable-pressure" }).toBe(true);
  expect(spread(contact.map(touch => touch.details?.altitudeRadians ?? 0)) > 1, { id: "received-variable-tilt" }).toBe(true);
  expect(spread(contact.map(touch => touch.details?.azimuthRadians ?? 0)) > 1, { id: "received-variable-azimuth" }).toBe(true);
  expect(spread(contact.map(touch => touch.details?.rollRadians ?? 0)) > 6, { id: "received-barrel-roll" }).toBe(true);
  expect(hover.length > 10, { id: "sdk-captured-hover" }).toBe(true);
  expect(spread(hover.map(touch => touch.details?.distance ?? 0)) > .8, { id: "received-hover-distance" }).toBe(true);
  return { capturedContactSamples: contact.length, capturedHoverSamples: hover.length, mode: playback.mode };
}
