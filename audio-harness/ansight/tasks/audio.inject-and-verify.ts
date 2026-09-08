import type { TaskDefinition, TaskInvocation } from "./ansight-task.d.ts";
import { copyFileSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { compareRecording, evidenceDirectory, normalizeTranscript, prepareFixture, prepareVerifier,
  repositoryFile, requestArtifact, seekVisible, sha256, writeEvidence } from "./audio-support.ts";
import type { AudioTaskOutput, HarnessResult } from "./audio-support.ts";

type Input = { fixtureId: string; mode: "capture" | "transcript" };

export const task = {
  "schemaVersion": 1,
  "appId": "ai.ansight.audioharness",
  "title": "Inject speech and verify microphone capture",
  "description": "Starts normal microphone capture in an existing harness session, injects one quote, downloads the exact app run artifacts, and verifies the full waveform plus a wrong-fixture control. Optional transcript mode requires a matching final native transcript. Resets only after success; preserves failures.",
  "feature": "audio",
  "keywords": ["microphone", "speech", "wav", "injection", "recording", "transcription", "ios", "android"],
  "inputSchema": {
    "type": "object",
    "properties": {
      "fixtureId": { "type": "string", "default": "shakespeare-hamlet", "enum": [
        "shakespeare-hamlet", "shakespeare-macbeth", "shakespeare-as-you-like-it", "shakespeare-twelfth-night",
        "lincoln-gettysburg", "roosevelt-fear-itself", "austen-pride-and-prejudice", "descartes-i-think"
      ] },
      "mode": { "type": "string", "enum": ["capture", "transcript"], "default": "capture" }
    },
    "additionalProperties": false
  },
  "timeoutSeconds": 120,
  "maximumActions": 80
} satisfies TaskDefinition;

export default async function runTask(context: TaskInvocation<Input>): Promise<AudioTaskOutput> {
  const { ansight, expect, input, run } = context;
  const fixture = prepareFixture(run.repositoryRootPath, input.fixtureId);
  if (input.mode === "capture") prepareVerifier(run.repositoryRootPath);
  const directory = evidenceDirectory(run.repositoryRootPath, run.runId);
  copyFileSync(fixture.path, join(directory, "fixture.wav"));
  writeEvidence(directory, "fixture.json", fixture.quote);
  let started = false;
  let completed = false;
  try {
    const capabilities = await ansight.device.audioCapabilities();
    writeEvidence(directory, "capabilities.json", capabilities);
    // Android's idle app has no microphone reader yet. Other failed prerequisites stop before any tap.
    const readyForStart = capabilities.available || (capabilities.platform === "android"
      && capabilities.code === "microphone-not-ready" && capabilities.diagnostics.transportAvailable === true
      && capabilities.diagnostics.hostMicrophoneEnabled === false);
    expect(readyForStart, { id: "audio-route-preflight", message: capabilities.message }).toBe(true);

    // The saved-result footer may be outside the viewport on small phones. Empty initial run IDs are valid.
    await seekVisible(ansight, () => ansight.ui.find({ automationId: "result-saved", exact: true, limit: 1 }), "bottom");
    const oldRun = await ansight.ui.find({ automationId: "run-id", exact: true, limit: 1 });
    const oldRunId = oldRun.matches[0]?.text ?? "";
    const start = await seekVisible(ansight, () => ansight.ui.find({ automationId: "start-listening", exact: true, limit: 1 }), "top");
    expect(start.enabled, { id: "harness-idle-before-run" }).toBe(true);
    const mode = await seekVisible(ansight, () => ansight.ui.find({ automationId: "capture-only-state", exact: true, limit: 1 }), "top");
    const currentMode = mode.text;
    expect(currentMode === "Capture only" || currentMode === "Transcription", { id: "capture-mode-observable" }).toBe(true);
    if (currentMode !== (input.mode === "capture" ? "Capture only" : "Transcription")) {
      await ansight.ui.tap({ automationId: "capture-only", exact: true });
    }
    if (input.mode === "transcript") {
      await ansight.ui.typeText({ automationId: "expected-phrase", exact: true, value: fixture.quote.text, replaceExisting: true });
      await ansight.keyboard.dismiss();
    }

    await seekVisible(ansight, () => ansight.ui.find({ automationId: "start-listening", exact: true, limit: 1 }), "bottom");
    // No intervening UI observation or screenshot call: the provider owns the bounded readiness wait.
    await ansight.ui.tap({ automationId: "start-listening", exact: true });
    started = true;
    const injection = await ansight.device.injectAudio({
      file: fixture.file, timeoutMs: 30_000, waitForMicrophoneMs: 5_000,
    });
    writeEvidence(directory, "injection.json", injection);
    expect(injection.status, { id: "audio-delivery-completed" }).toBe("completed");
    expect(injection.fixture.sha256, { id: "injected-fixture-identity" }).toBe(fixture.sha256);

    // Stop while the recording controls are still in the viewport, before seeking the result footer.
    const stop = await ansight.ui.find({ automationId: "stop-listening", exact: true, limit: 1 });
    if (stop.matches[0]?.enabled) await ansight.ui.tap({ automationId: "stop-listening", exact: true });
    await seekVisible(ansight, () => ansight.ui.find({ automationId: "result-saved", exact: true, limit: 1 }), "bottom");
    const saved = await ansight.ui.waitFor({ automationId: "result-saved", exact: true, text: "Saved",
      timeoutMs: 20_000, pollIntervalMs: 500 });
    expect(saved.satisfied, { id: "app-result-persisted" }).toBe(true);
    const currentRun = await ansight.ui.find({ automationId: "run-id", exact: true, limit: 1 });
    const harnessRunId = currentRun.matches[0]?.text ?? "";
    expect(/^[a-f0-9]{32}$/.test(harnessRunId) && harnessRunId !== oldRunId,
      { id: "fresh-app-run" }).toBe(true);
    const resultPath = await requestArtifact(context, harnessRunId, "run-result", directory, "app-result.json");
    const result = JSON.parse(readFileSync(resultPath, "utf8")) as HarnessResult;
    expect(result.schema, { id: "app-result-schema" }).toBe("ansight.audio-harness-result/v1");
    expect(result.runId, { id: "app-result-belongs-to-run" }).toBe(harnessRunId);
    expect(result.captureOnly, { id: "app-used-requested-mode" }).toBe(input.mode === "capture");
    const output: AudioTaskOutput = {
      fixtureId: fixture.quote.id, harnessRunId, taskRunId: run.runId, sessionId: run.sessionId,
      mode: input.mode, captureVerified: false, transcriptionVerified: false,
      negativeControlRejected: false, evidenceDirectory: directory, injectionEvidenceId: injection.evidenceId,
    };
    if (input.mode === "capture") {
      expect(result.phase, { id: "app-captured-microphone" }).toBe("Captured");
      expect(result.capture?.available && result.capture.frameCount > 0 && result.capture.nonSilentFrameCount > 0,
        { id: "app-recording-has-audio-samples" }).toBe(true);
      const microphonePath = await requestArtifact(context, harnessRunId, "microphone-wav", directory, "microphone.wav");
      expect(sha256(readFileSync(microphonePath)), { id: "recording-sha256-matches-app" }).toBe(result.capture.sha256);
      const positive = compareRecording(run.repositoryRootPath, join(directory, "fixture.wav"), microphonePath,
        join(directory, "waveform-verification.json"));
      expect(positive.passed && positive.comparison?.wholeSpeechSpanCompared === true,
        { id: "whole-spoken-fixture-received" }).toBe(true);
      const wrong = fixture.quotes.find(candidate => candidate.id ===
        (fixture.quote.id === "descartes-i-think" ? "shakespeare-hamlet" : "descartes-i-think"))!;
      const wrongPath = repositoryFile(run.repositoryRootPath, `fixtures/audio/quotes/${wrong.filename}`);
      copyFileSync(wrongPath, join(directory, "wrong-fixture.wav"));
      const negative = compareRecording(run.repositoryRootPath, wrongPath, microphonePath,
        join(directory, "wrong-fixture-verification.json"));
      expect(negative.passed, { id: "different-spoken-fixture-rejected" }).toBe(false);
      output.captureVerified = true;
      output.negativeControlRejected = true;
      output.waveformCorrelation = positive.comparison?.waveformCorrelation;
    } else {
      expect(result.phase, { id: "speech-recognizer-completed" }).toBe("Completed");
      expect(result.isFinal && result.passed, { id: "app-final-transcript-passed" }).toBe(true);
      expect(normalizeTranscript(result.transcript), { id: "actual-transcript-matches-fixture" })
        .toBe(normalizeTranscript(fixture.quote.text));
      output.transcriptionVerified = true;
      output.transcript = result.transcript;
    }
    writeEvidence(directory, "verification.json", output);
    await seekVisible(ansight, () => ansight.ui.find({ automationId: "reset-test", exact: true, limit: 1 }), "top");
    await ansight.ui.tap({ automationId: "reset-test", exact: true });
    await seekVisible(ansight, () => ansight.ui.find({ automationId: "capture-phase", exact: true, limit: 1 }), "top");
    const ready = await ansight.ui.assert({ automationId: "capture-phase", exact: true, expectedText: "Ready" });
    expect(ready.passed, { id: "harness-reset-after-verification" }).toBe(true);
    completed = true;
    return output;
  } catch (error) {
    writeEvidence(directory, "failure.json", { message: error instanceof Error ? error.message : String(error),
      taskRunId: run.runId, sessionId: run.sessionId, fixtureId: fixture.quote.id });
    throw error;
  } finally {
    // Preserve failed result state; stop an active recorder once, without reinjection or automatic retries.
    if (started && !completed) {
      try {
        const stop = await seekVisible(ansight, () => ansight.ui.find({ automationId: "stop-listening", exact: true, limit: 1 }), "top");
        if (stop.enabled) await ansight.ui.tap({ automationId: "stop-listening", exact: true });
      } catch (error) {
        writeEvidence(directory, "cleanup-unconfirmed.json", { message: String(error) });
      }
    }
  }
}
