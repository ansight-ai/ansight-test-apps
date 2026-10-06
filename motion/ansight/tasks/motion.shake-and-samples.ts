import type { TaskDefinition, TaskInvocation } from "./ansight-task.d.ts";

export const task = {
  "schemaVersion": 1,
  "appId": "ai.ansight.testapps.motionharness",
  "title": "Verify shake and accelerometer injection",
  "description": "Inject a shake and custom accelerometer sample, then assert app-observed states.",
  "platforms": ["android"],
  "deviceKinds": ["virtual"],
  "frameworks": ["android-views"],
  "inputSchema": { "type": "object", "properties": {}, "additionalProperties": false },
  "timeoutSeconds": 30,
  "maximumActions": 24
} satisfies TaskDefinition;

export default async function runTask({ ansight, expect }: TaskInvocation) {
  const sensorReady = await ansight.ui.waitFor({ text: "Sensor ready", timeoutMs: 4_000 });
  expect(sensorReady.satisfied, { id: "sensor-ready" }).toBe(true);
  await ansight.ui.tap({ text: "RESET COUNTERS" });
  const ready = await ansight.ui.assert({ text: "Shake waiting", exists: true });
  expect(ready.passed, { id: "shake-baseline-visible" }).toBe(true);

  const shake = await ansight.device.shake({ intensity: 22, repetitions: 3, intervalMs: 90 });
  expect(shake.sampleCount, { id: "shake-pulses-delivered" }).toBe(6);
  const shakeObserved = await ansight.ui.waitFor({ text: "Shake detected", timeoutMs: 4_000 });
  expect(shakeObserved.satisfied, {
    id: "app-detected-shake",
    message: "The app must observe sign-changing acceleration, not just host delivery."
  }).toBe(true);

  await ansight.ui.tap({ text: "RESET COUNTERS" });
  const sequence = await ansight.device.playAccelerometer({
    samples: [
      { x: 0, y: 9.81, z: 0, holdMs: 100 },
      { x: 32, y: 0, z: 0, holdMs: 250 },
      { x: 0, y: 9.81, z: 0, holdMs: 100 }
    ]
  });
  expect(sequence.sampleCount, { id: "custom-samples-delivered" }).toBe(3);
  const customObserved = await ansight.ui.waitFor({ text: "Custom sample observed", timeoutMs: 4_000 });
  expect(customObserved.satisfied, {
    id: "app-observed-custom-sample",
    message: "The app must observe the 32 m/s² sample through SensorManager."
  }).toBe(true);

  return { shakeDetected: true, customSampleObserved: true };
}
