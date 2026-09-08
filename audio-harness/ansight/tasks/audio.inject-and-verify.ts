import type { TaskDefinition, TaskInvocation } from "./ansight-task.d.ts";
import { copyFileSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { compareRecording, evidenceDirectory, expectationForTyping, loadWhisperModel, normalizeTranscript, prepareFixture, prepareVerifier,
  repositoryFile, requestArtifact, seekVisible, sha256, writeEvidence } from "./audio-support.ts";
import type { AudioTaskMode, AudioTaskOutput, HarnessResult } from "./audio-support.ts";

type Input = { fixtureId: string; mode: AudioTaskMode };

export const task = {
  "schemaVersion": 1,
  "appId": "ai.ansight.audioharness",
  "title": "Inject speech and verify microphone capture",
  "description": "Starts normal microphone capture in an existing harness session and injects one quote. Capture mode verifies the exact-run WAV and a wrong-fixture control; whisper mode also requires a matching final offline transcript with recorded-audio provenance. Explicit transcript mode uses native recognition. Resets only after success; preserves failures.",
  "feature": "audio",
  "keywords": ["microphone", "speech", "wav", "injection", "recording", "transcription", "whisper", "offline", "ios", "android"],
  "inputSchema": {
    "type": "object",
    "properties": {
      "fixtureId": { "type": "string", "default": "shakespeare-hamlet", "enum": [
        "shakespeare-hamlet", "shakespeare-macbeth", "shakespeare-as-you-like-it", "shakespeare-twelfth-night",
        "lincoln-gettysburg", "roosevelt-fear-itself", "austen-pride-and-prejudice", "descartes-i-think"
      ] },
      "mode": { "type": "string", "enum": ["capture", "transcript", "whisper"], "default": "capture" }
    },
    "additionalProperties": false
  },
  "timeoutSeconds": 180,
  "maximumActions": 96
} satisfies TaskDefinition;

export default async function runTask(context: TaskInvocation<Input>): Promise<AudioTaskOutput> {
  const { ansight, expect, input, run } = context;
  const fixture = prepareFixture(run.repositoryRootPath, input.fixtureId);
  const expectedForUi = input.mode === "capture" ? undefined : expectationForTyping(fixture.quote.text);
  const verifyMicrophone = input.mode !== "transcript";
  if (verifyMicrophone) prepareVerifier(run.repositoryRootPath);
  const whisperModel = input.mode === "whisper" ? loadWhisperModel(run.repositoryRootPath) : undefined;
  const directory = evidenceDirectory(run.repositoryRootPath, run.runId);
  copyFileSync(fixture.path, join(directory, "fixture.wav"));
  writeEvidence(directory, "fixture.json", fixture.quote);
  if (expectedForUi !== undefined) writeEvidence(directory, "expected-input.json", {
    fixtureText: fixture.quote.text, enteredExpectation: expectedForUi, purpose: "Final assertion only; never a recognition prompt.",
  });
  if (whisperModel) writeEvidence(directory, "whisper-model.json", whisperModel);
  let started = false;
  let completed = false;
  try {
    const capabilities = await ansight.device.audioCapabilities();
    writeEvidence(directory, "capabilities.json", capabilities);
    const waitForWhisperUi = input.mode === "whisper" && capabilities.platform === "ios";
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
    if (input.mode !== "capture") {
      // Whisper controls observed in iOS accessibility session 1538 on 2026-09-09 (local time).
      // Receipt: artifacts/audio-harness/whisper-20260909/workspace/selector-grounding-ios.json.
      const provider = await seekVisible(ansight, () => ansight.ui.find({ automationId: "transcription-provider-state", exact: true, limit: 1 }), "top");
      expect(provider.text === "Whisper (offline)" || provider.text === "Native speech",
        { id: "transcription-provider-observable" }).toBe(true);
      const desiredProvider = input.mode === "whisper" ? "Whisper (offline)" : "Native speech";
      if (provider.text !== desiredProvider) {
        await ansight.ui.tap({ automationId: "use-whisper", exact: true });
      }
      const selectedProvider = await ansight.ui.find({ automationId: "transcription-provider-state", exact: true, limit: 1 });
      expect(selectedProvider.matches[0]?.text, { id: "transcription-provider-selected" }).toBe(desiredProvider);
      // This field configures the app's final assertion only; neither engine receives it as a prompt.
      await ansight.ui.typeText({ automationId: "expected-phrase", exact: true, value: expectedForUi!, replaceExisting: true });
      await ansight.keyboard.dismiss();
    }

    await seekVisible(ansight, () => ansight.ui.find({ automationId: "start-listening", exact: true, limit: 1 }), "bottom");
    // Android verifies the active guest microphone inside injectAudio. Avoid UI work that can outlast capture.
    // iOS has no guest-microphone readiness probe, so wait for its model preparation and visible Listening state.
    await ansight.ui.tap({ automationId: "start-listening", exact: true });
    started = true;
    if (waitForWhisperUi) {
      await seekVisible(ansight, () => ansight.ui.find({ automationId: "capture-phase", exact: true, limit: 1 }), "top");
      const listening = await ansight.ui.waitFor({ automationId: "capture-phase", exact: true, text: "Listening",
        timeoutMs: 35_000, pollIntervalMs: 500 });
      expect(listening.satisfied, { id: "whisper-microphone-listening" }).toBe(true);
    }
    const injection = await ansight.device.injectAudio({
      file: fixture.file, timeoutMs: 30_000, waitForMicrophoneMs: input.mode === "whisper" ? 10_000 : 5_000,
    });
    writeEvidence(directory, "injection.json", injection);
    expect(injection.status, { id: "audio-delivery-completed" }).toBe("completed");
    expect(injection.fixture.sha256, { id: "injected-fixture-identity" }).toBe(fixture.sha256);

    // Stop while the recording controls are still in the viewport, before seeking the result footer.
    if (waitForWhisperUi) {
      await seekVisible(ansight, () => ansight.ui.find({ automationId: "stop-listening", exact: true, limit: 1 }), "bottom");
    }
    const stop = await ansight.ui.find({ automationId: "stop-listening", exact: true, limit: 1 });
    if (stop.matches[0]?.enabled) await ansight.ui.tap({ automationId: "stop-listening", exact: true });
    await seekVisible(ansight, () => ansight.ui.find({ automationId: "result-saved", exact: true, limit: 1 }), "bottom");
    const saved = await ansight.ui.waitFor({ automationId: "result-saved", exact: true, text: "Saved",
      timeoutMs: input.mode === "whisper" ? 60_000 : 20_000, pollIntervalMs: 500 });
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
    if (verifyMicrophone) {
      expect(result.phase, { id: "app-captured-microphone" }).toBe(input.mode === "whisper" ? "Completed" : "Captured");
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
    }
    if (input.mode !== "capture") {
      expect(result.phase, { id: "speech-recognizer-completed" }).toBe("Completed");
      expect(result.isFinal && result.passed, { id: "app-final-transcript-passed" }).toBe(true);
      expect(normalizeTranscript(result.transcript), { id: "actual-transcript-matches-fixture" })
        .toBe(normalizeTranscript(fixture.quote.text));
      output.transcriptionVerified = true;
      output.transcript = result.transcript;
    }
    if (input.mode === "whisper") {
      expect(result.transcription?.provider, { id: "whisper-provider-used" }).toBe("whisper.net");
      expect(result.transcription?.model, { id: "whisper-model-used" }).toBe("base.en");
      const transcription = result.transcription!;
      expect(transcription.modelSha256, { id: "whisper-model-hash-matches-pinned-model" }).toBe(whisperModel!.sha256);
      expect(transcription.sourceAudioSha256, { id: "whisper-source-is-recorded-audio" }).toBe(result.capture.sha256);
      expect(/^[a-f0-9]{64}$/i.test(transcription.transcriptionAudioSha256),
        { id: "whisper-normalized-audio-hash-recorded" }).toBe(true);
      expect(transcription.sampleRate, { id: "whisper-input-sample-rate" }).toBe(16_000);
      expect(transcription.channels, { id: "whisper-input-channels" }).toBe(1);
      expect(Number.isFinite(transcription.processingMilliseconds) && transcription.processingMilliseconds >= 0,
        { id: "whisper-processing-time-recorded" }).toBe(true);
      output.transcription = transcription;
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
      taskRunId: run.runId, sessionId: run.sessionId, fixtureId: fixture.quote.id, mode: input.mode });
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
