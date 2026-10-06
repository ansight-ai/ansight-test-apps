import type { TaskDefinition, TaskInvocation } from "./ansight-task.d.ts";

export const task = {
  "schemaVersion": 1,
  "appId": "ai.ansight.testapps.motionharness",
  "title": "Verify iOS Simulator shake delivery",
  "description": "Post a UIKit shake gesture to the selected iOS Simulator and assert the app receives it.",
  "platforms": ["ios"],
  "deviceKinds": ["virtual"],
  "frameworks": ["ios-uikit"],
  "inputSchema": { "type": "object", "properties": {}, "additionalProperties": false },
  "timeoutSeconds": 20,
  "maximumActions": 10
} satisfies TaskDefinition;

export default async function runTask({ ansight, expect }: TaskInvocation) {
  await ansight.ui.tap({ text: "RESET COUNTERS" });
  const baseline = await ansight.ui.assert({ text: "Shake waiting", exists: true });
  expect(baseline.passed, { id: "ios-shake-baseline-visible" }).toBe(true);

  const delivery = await ansight.device.shake();
  expect(delivery.platform, { id: "ios-shake-target" }).toBe("ios");
  expect(delivery.gestureCount, { id: "ios-gesture-posted" }).toBe(1);

  const observed = await ansight.ui.waitFor({ text: "Shake detected", timeoutMs: 4_000 });
  expect(observed.satisfied, {
    id: "ios-app-detected-shake",
    message: "The iOS app must receive the UIKit shake gesture, not just the host post."
  }).toBe(true);

  return { shakeDetected: true };
}
