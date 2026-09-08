import { createHash } from "node:crypto";
import { copyFileSync, mkdirSync, readFileSync, realpathSync, statSync, writeFileSync } from "node:fs";
import { isAbsolute, join, relative, resolve, sep } from "node:path";
import { execFileSync } from "node:child_process";
import type { AnsightHost, AppToolCallResult, TaskInvocation, UiFindResult, UiNode } from "./ansight-task.d.ts";

export interface QuoteFixture { id: string; text: string; filename: string }
export type AudioTaskMode = "capture" | "transcript" | "whisper";
export interface HarnessTranscription {
  provider: string;
  model: string;
  modelSha256: string;
  sourceAudioSha256: string;
  transcriptionAudioSha256: string;
  sampleRate: number;
  channels: number;
  processingMilliseconds: number;
}
export interface WhisperModelManifest {
  schema: string;
  provider: string;
  model: string;
  fileName: string;
  sha256: string;
  sizeBytes: number;
}
export interface HarnessResult {
  schema: string;
  runId: string;
  phase: string;
  captureOnly: boolean;
  isFinal: boolean;
  passed: boolean;
  transcript: string;
  expected: string;
  transcription?: HarnessTranscription | null;
  capture: {
    available: boolean;
    sha256: string;
    fileBytes: number;
    frameCount: number;
    durationSeconds: number;
    nonSilentFrameCount: number;
  };
}
export interface ArtifactTransfer {
  status: string;
  transferId: string;
  artifactPath: string;
  receivedBytes: number;
  artifact: { providerId: string; artifactId: string; sizeBytes: number; metadata: { runId: string } };
}
export interface WaveformReport {
  schema: string;
  passed: boolean;
  transcriptionVerified: false;
  error?: string;
  fixture?: { sha256: string };
  recording?: { sha256: string };
  comparison?: {
    passed: boolean;
    waveformCorrelation?: number;
    minimumCorrelation?: number;
    wholeSpeechSpanCompared?: boolean;
    reason?: string;
  };
}
export interface AudioTaskOutput {
  fixtureId: string;
  harnessRunId: string;
  taskRunId: string;
  sessionId: string;
  mode: AudioTaskMode;
  captureVerified: boolean;
  transcriptionVerified: boolean;
  negativeControlRejected: boolean;
  evidenceDirectory: string;
  injectionEvidenceId: string;
  waveformCorrelation?: number;
  transcript?: string;
  transcription?: HarnessTranscription;
}

export function repositoryFile(repositoryRoot: string, relativePath: string): string {
  if (isAbsolute(relativePath)) throw new Error("Fixture paths must be repository relative.");
  const root = realpathSync(repositoryRoot);
  const path = realpathSync(resolve(root, relativePath));
  const child = relative(root, path);
  if (child === ".." || child.startsWith(`..${sep}`) || isAbsolute(child)) {
    throw new Error("Fixture resolved outside the repository.");
  }
  return path;
}

export function loadQuotes(repositoryRoot: string): QuoteFixture[] {
  const manifest = JSON.parse(readFileSync(repositoryFile(repositoryRoot,
    "fixtures/audio/quotes/manifest.json"), "utf8")) as { schemaVersion: number; fixtures: QuoteFixture[] };
  if (manifest.schemaVersion !== 1 || manifest.fixtures.length !== 8) {
    throw new Error("Expected the versioned eight-quote fixture corpus.");
  }
  for (const quote of manifest.fixtures) {
    if (!/^[a-z0-9-]+$/.test(quote.id) || quote.filename !== `${quote.id}.wav` || !quote.text.trim()) {
      throw new Error("The quote manifest contains an invalid fixture entry.");
    }
  }
  return manifest.fixtures;
}

export function prepareFixture(repositoryRoot: string, fixtureId: string) {
  const quotes = loadQuotes(repositoryRoot);
  const quote = quotes.find(candidate => candidate.id === fixtureId);
  if (!quote) throw new Error(`Unknown fixture: ${fixtureId}`);
  const file = `fixtures/audio/quotes/${quote.filename}`;
  const path = repositoryFile(repositoryRoot, file);
  const bytes = readFileSync(path);
  if (bytes.length > 1_048_576 || bytes.toString("ascii", 0, 4) !== "RIFF"
    || bytes.toString("ascii", 8, 12) !== "WAVE") throw new Error("Invalid or oversized WAV fixture.");
  // Decode/check the format before any UI tap starts the app's recording window.
  const probe = JSON.parse(execFileSync("ffprobe", ["-v", "error", "-show_entries",
    "stream=codec_name,sample_rate,channels,bits_per_sample:format=duration", "-of", "json", path],
  { encoding: "utf8", timeout: 10_000, maxBuffer: 64 * 1024 })) as {
    streams: { codec_name: string; sample_rate: string; channels: number; bits_per_sample: number }[];
    format: { duration: string };
  };
  const stream = probe.streams[0];
  if (probe.streams.length !== 1 || stream?.codec_name !== "pcm_s16le" || stream.sample_rate !== "16000"
    || stream.channels !== 1 || stream.bits_per_sample !== 16
    || !(Number(probe.format.duration) > 0 && Number(probe.format.duration) <= 15)) {
    throw new Error("Use a PCM16 mono 16 kHz fixture no longer than 15 seconds.");
  }
  return { quote, file, path, sha256: sha256(bytes), quotes };
}

export function prepareVerifier(repositoryRoot: string): void {
  execFileSync(join(realpathSync(repositoryRoot), ".venv-audio/bin/python"),
    ["-c", "import numpy; import shutil; assert shutil.which('ffmpeg'); assert shutil.which('ffprobe')"],
    { timeout: 10_000, maxBuffer: 64 * 1024 });
}

export function loadWhisperModel(repositoryRoot: string): WhisperModelManifest {
  const model = JSON.parse(readFileSync(repositoryFile(repositoryRoot,
    "apps/Ansight.AudioHarness/Resources/Raw/models/whisper-model.json"), "utf8")) as WhisperModelManifest;
  if (model.schema !== "ansight.whisper-model/v1" || model.provider !== "whisper.net"
    || model.model !== "base.en" || model.fileName !== "ggml-base.en.bin"
    || !/^[a-f0-9]{64}$/.test(model.sha256) || !Number.isSafeInteger(model.sizeBytes) || model.sizeBytes <= 0) {
    throw new Error("The pinned Whisper model manifest is invalid.");
  }
  return model;
}

export function sha256(bytes: Uint8Array): string {
  return createHash("sha256").update(bytes).digest("hex");
}

export function evidenceDirectory(repositoryRoot: string, taskRunId: string): string {
  if (!/^[a-zA-Z0-9_-]+$/.test(taskRunId)) throw new Error("Unexpected task run ID.");
  const directory = join(realpathSync(repositoryRoot), "artifacts/audio-harness/ansight", taskRunId);
  mkdirSync(directory, { recursive: true });
  return directory;
}

export function writeEvidence(directory: string, name: string, value: unknown): void {
  writeFileSync(join(directory, name), JSON.stringify(value, null, 2) + "\n");
}

export async function requestArtifact(
  context: TaskInvocation<object>, runId: string, artifactId: "run-result" | "microphone-wav",
  directory: string, fileName: string,
): Promise<string> {
  const response = await context.app.artifacts.request<ArtifactTransfer>({
    providerId: "audio-harness.runs", artifactId, arguments: { runId },
  });
  writeEvidence(directory, `${artifactId}-transfer.json`, response);
  const transfer = successfulPayload(response);
  if (transfer.status !== "complete" || transfer.artifact.providerId !== "audio-harness.runs"
    || transfer.artifact.artifactId !== artifactId || transfer.artifact.metadata?.runId !== runId
    || !transfer.transferId || !isAbsolute(transfer.artifactPath)) {
    throw new Error("The SDK artifact transfer did not complete with the expected identity.");
  }
  const source = realpathSync(transfer.artifactPath);
  const size = statSync(source).size;
  const maximum = artifactId === "run-result" ? 65_536 : 16 * 1024 * 1024;
  if (size <= 0 || size > maximum || size !== transfer.receivedBytes || size !== transfer.artifact.sizeBytes) {
    throw new Error("The complete artifact size does not match its transfer metadata.");
  }
  const destination = join(directory, fileName);
  copyFileSync(source, destination);
  return destination;
}

export function successfulPayload<T>(response: AppToolCallResult<T>): T {
  if (response.responseType !== "tool.result" || !response.payload.success) {
    throw new Error(`App tool failed: ${JSON.stringify(response.payload)}`);
  }
  return response.payload.result;
}

export function compareRecording(repositoryRoot: string, fixturePath: string, microphonePath: string,
  outputPath: string): WaveformReport {
  try {
    execFileSync(join(realpathSync(repositoryRoot), ".venv-audio/bin/python"), [
      repositoryFile(repositoryRoot, "scripts/verify-microphone-capture.py"), fixturePath,
      microphonePath, "--output", outputPath,
    ], { timeout: 20_000, maxBuffer: 128 * 1024 });
  } catch (error) {
    // Exit 1 is the verifier's deliberate nonmatch result; timeouts/spawn errors remain failures.
    if ((error as { status?: number }).status !== 1) throw error;
  }
  const report = JSON.parse(readFileSync(outputPath, "utf8")) as WaveformReport;
  if (report.schema !== "ansight.microphone-waveform-verification/v1" || report.error || !report.comparison) {
    throw new Error(`Waveform verification failed to run: ${report.error ?? "invalid report"}`);
  }
  return report;
}

export function normalizeTranscript(value: string): string {
  return value.toLowerCase().replace(/[^\p{L}\p{N}]+/gu, " ").trim();
}

export function expectationForTyping(value: string): string {
  // Simulator HID cannot type the corpus's em dash/curly apostrophe. These replacements
  // preserve TranscriptValidator's punctuation rules, including contractions as one word.
  const text = value.replace(/[\u2019\u02bc]/g, "'").replace(/[\u2013\u2014]/g, " ");
  if (/[^\x20-\x7e]/.test(text)) throw new Error("The fixture expectation needs an explicit Simulator keyboard mapping.");
  return text;
}

/** Seek an observed target using at most three gestures in the observed scroll container.
 * Target selectors stay as inline literals at the task call site for evidence review.
 */
export async function seekVisible(ansight: AnsightHost, find: () => Promise<UiFindResult>,
  toward: "top" | "bottom"): Promise<UiNode> {
  for (let attempt = 0; attempt <= 3; attempt++) {
    const result = await find();
    const node = result.matches.find(candidate => candidate.visible && candidate.onScreen === true
      && candidate.viewportRelation === "inside");
    if (node) return node;
    if (attempt === 3) throw new Error(`The observed UI target remained offscreen after three gestures toward ${toward}.`);
    // Swipe direction describes finger motion: up reveals content farther down the page.
    await ansight.ui.swipe({ automationId: "harness-scroll", exact: true, direction: toward === "bottom" ? "up" : "down", length: 0.6 });
  }
  throw new Error("The bounded UI search did not resolve a visible target.");
}
