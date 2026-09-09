import type { TaskDefinition, TaskInvocation } from "./ansight-task.d.ts";
import { seekVisible } from "./audio-support.ts";

export const task = {
  "schemaVersion": 1,
  "appId": "ai.ansight.audioharness",
  "title": "Inject speech and show its transcript",
  "description": "Records and transcribes one injected quote with offline Whisper, leaving the result visible.",
  "inputSchema": {
    "type": "object",
    "properties": {},
    "additionalProperties": false
  },
  "timeoutSeconds": 180,
  "maximumActions": 80
} satisfies TaskDefinition;

export default async function run({ ansight, expect }: TaskInvocation) {
  const expected = "To be or not to be that is the question.";
  const { platform } = await ansight.device.audioCapabilities();

  const mode = await seekVisible(ansight, { automationId: "capture-only-state" }, "top");
  if (mode.text === "Capture only") {
    await ansight.ui.tap({ automationId: "capture-only", exact: true });
  }

  const provider = await seekVisible(ansight, { automationId: "transcription-provider-state" }, "top");
  if (provider.text === "Native speech") {
    await ansight.ui.tap({ automationId: "use-whisper", exact: true });
  }

  // The expected phrase is used only for the app's final comparison.
  await ansight.ui.tap({ automationId: "expected-phrase", exact: true });
  await ansight.ui.typeText({
    automationId: "expected-phrase",
    exact: true,
    value: expected,
    replaceExisting: true,
  });
  await ansight.keyboard.dismiss();

  const start = await seekVisible(ansight, { automationId: "start-listening" }, "bottom");
  expect(start.enabled, { id: "ready-to-record" }).toBe(true);

  await ansight.ui.tap({ automationId: "start-listening", exact: true });

  try {
    // Android waits for its microphone inside injectMicrophoneAudio; iOS needs the visible state.
    if (platform === "ios") {
      await seekVisible(ansight, { automationId: "capture-phase" }, "top");

      const listening = await ansight.ui.waitFor({
        automationId: "capture-phase",
        exact: true,
        text: "Listening",
        timeoutMs: 35_000,
      });

      expect(listening.satisfied, { id: "microphone-listening" }).toBe(true);
    }

    const injection = await ansight.device.injectMicrophoneAudio({
      file: "fixtures/speech.wav",
      timeoutMs: 30_000,
      waitForMicrophoneMs: 10_000,
    });

    expect(injection.status, { id: "audio-injected" }).toBe("completed");
  } finally {
    if (platform === "ios") {
      await seekVisible(ansight, { automationId: "stop-listening" }, "bottom");
    }

    const stop = await ansight.ui.find({ automationId: "stop-listening", exact: true });
    if (stop.matches[0]?.enabled) {
      await ansight.ui.tap({ automationId: "stop-listening", exact: true });
    }
  }

  await seekVisible(ansight, { automationId: "result-saved" }, "bottom");

  const saved = await ansight.ui.waitFor({
    automationId: "result-saved",
    exact: true,
    text: "Saved",
    timeoutMs: 60_000,
  });

  expect(saved.satisfied, { id: "transcription-finished" }).toBe(true);

  const transcript = await seekVisible(ansight, { automationId: "transcript" }, "top");

  expect(normalize(transcript.text ?? ""), {
    id: "injected-speech-transcribed",
  }).toBe(normalize(expected));

  return { transcript: transcript.text };
}

function normalize(text: string): string {
  return text.toLowerCase().replace(/[^a-z]+/g, " ").trim();
}
