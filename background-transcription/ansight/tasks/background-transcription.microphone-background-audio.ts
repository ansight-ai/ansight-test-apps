import type {
  AppToolCallResult,
  ArtifactDescriptor,
  TaskDefinition,
  TaskInvocation
} from "./ansight-task.d.ts";

const providerId = "background-transcription.runs";
const artifactId = "transcript-result";
const fixtureFile = "fixtures/fdr-day-of-infamy-10s.wav";

type ArtifactCatalog = {
  providers?: Array<{
    id?: string;
    artifacts?: Array<{
      id?: string;
      metadata?: Record<string, string>;
    }>;
  }>;
};

type TranscriptResult = {
  id: string;
  platform: string;
  audioSource: string;
  expectedDurationSeconds: number;
  phase: string;
  backgroundedDuringRun: boolean;
  transcript: string;
};

export const task = {
  "schemaVersion": 1,
  "appId": "ai.ansight.testapps.backgroundtranscription",
  "title": "Transcribe injected microphone audio while backgrounded",
  "description": "Starts live microphone transcription, backgrounds the app, injects a bundled speech fixture through the virtual microphone, foregrounds the app after delivery, and verifies the durable transcript artifact.",
  "keywords": ["background", "transcription", "microphone", "audio", "speech"],
  "platforms": ["ios", "android"],
  "deviceKinds": ["virtual"],
  "frameworks": ["ios-swiftui", "android-views"],
  "timeoutSeconds": 90,
  "maximumActions": 100
} satisfies TaskDefinition;

export default async function runTask({ ansight, app, expect }: TaskInvocation) {
  const initialState = await ansight.session.getAppState();
  const platform = normalizePlatform(initialState.osName);
  expect(["ios", "android"].includes(platform), {
    id: "supported-platform",
    message: `The task requires an iOS Simulator or Android emulator; reported OS was '${initialState.osName ?? "unknown"}'.`
  }).toBe(true);
  expect(initialState.isVirtual === true || initialState.isEmulator === true, {
    id: "virtual-device",
    message: "Microphone audio injection is supported only on virtual devices."
  }).toBe(true);

  const capabilities = await ansight.device.audioCapabilities();
  expect(capabilities.available, {
    id: "audio-provider-ready",
    message: capabilities.message
  }).toBe(true);

  const previousRunId = await queryLatestRunId(app.artifacts.query({ providerId, artifactId }));

  await ansight.ui.tap({ text: "Device mic" });
  await ansight.ui.tap({ text: "60 seconds" });
  await ansight.ui.tap({ text: "20 seconds" });
  await ansight.ui.tap({ text: "Start background transcription" });

  const started = await waitForRun(app, previousRunId, 10_000);
  expect(started.runId !== "none" && started.runId !== previousRunId, {
    id: "microphone-run-started",
    message: "A new device-microphone transcription run must begin before the app is backgrounded."
  }).toBe(true);

  let deliveryCompleted = false;
  try {
    const backgroundResult = await ansight.lifecycle.background();
    expect(backgroundResult.isSuccess, {
      id: "app-backgrounded",
      message: backgroundResult.message
    }).toBe(true);

    const backgroundState = await waitForAppState(ansight, "background", 5_000);
    expect(backgroundState, {
      id: "background-state-observed",
      message: "Ansight must observe the application in the background before injecting audio."
    }).toBe("background");

    const delivery = await ansight.device.injectMicrophoneAudio({
      file: fixtureFile,
      timeoutMs: 30_000,
      waitForMicrophoneMs: 10_000
    });
    deliveryCompleted = delivery.status === "completed";
    expect(delivery.captureVerified, {
      id: "provider-does-not-claim-capture",
      message: "Provider delivery evidence must remain distinct from app-level capture verification."
    }).toBe(false);
  } finally {
    const foregroundResult = await ansight.lifecycle.foreground();
    expect(foregroundResult.isSuccess, {
      id: "app-foregrounded",
      message: foregroundResult.message
    }).toBe(true);
    const foregroundState = await waitForAppState(ansight, "foreground", 5_000);
    expect(foregroundState, {
      id: "foreground-state-observed",
      message: "Ansight must observe the application in the foreground after audio delivery."
    }).toBe("foreground");
  }

  expect(deliveryCompleted, {
    id: "audio-delivery-completed",
    message: "The virtual microphone provider must finish delivering the bundled speech fixture."
  }).toBe(true);

  const terminal = await waitForTerminalRun(app, started.runId, 35_000);
  expect(terminal.phase, {
    id: "transcription-completed",
    message: `The transcription run ended in '${terminal.phase}'.`
  }).toBe("completed");

  const artifactResponse = await app.artifacts.request({
    providerId,
    artifactId,
    arguments: { runId: started.runId }
  });
  expect(artifactResponse.responseType, {
    id: "transcript-artifact-captured",
    message: "The completed run must be captured as an Ansight artifact."
  }).toBe("tool.result");

  const result = await readTranscriptResult(ansight, artifactResponse, started.runId);
  expect(result.phase, {
    id: "artifact-terminal-phase"
  }).toBe("completed");
  expect(result.audioSource, {
    id: "artifact-audio-source"
  }).toBe("device_microphone");
  expect(result.expectedDurationSeconds, {
    id: "artifact-duration"
  }).toBe(20);
  expect(result.backgroundedDuringRun, {
    id: "artifact-background-evidence"
  }).toBe(true);
  expect(result.transcript.trim().length > 0, {
    id: "artifact-transcript-present"
  }).toBe(true);

  return {
    runId: result.id,
    platform,
    transcript: result.transcript,
    artifactCaptured: true
  };
}

function normalizePlatform(osName?: string | null): "ios" | "android" | "unknown" {
  const normalized = osName?.toLowerCase() ?? "";
  if (normalized.includes("ios")) return "ios";
  if (normalized.includes("android")) return "android";
  return "unknown";
}

async function queryLatestRunId(
  responsePromise: Promise<AppToolCallResult<ArtifactCatalog>>
): Promise<string | undefined> {
  const response = await responsePromise;
  if (response.responseType !== "tool.result") return undefined;
  return response.payload.result.providers
    ?.find(provider => provider.id === providerId)
    ?.artifacts?.find(artifact => artifact.id === artifactId)
    ?.metadata?.latestRunId;
}

async function waitForRun(
  app: TaskInvocation["app"],
  previousRunId: string | undefined,
  timeoutMs: number
): Promise<{ runId: string; phase: string }> {
  const deadline = Date.now() + timeoutMs;
  do {
    const response = await app.artifacts.query<ArtifactCatalog>({ providerId, artifactId });
    if (response.responseType === "tool.result") {
      const metadata = response.payload.result.providers
        ?.find(provider => provider.id === providerId)
        ?.artifacts?.find(artifact => artifact.id === artifactId)
        ?.metadata;
      const runId = metadata?.latestRunId;
      if (runId && runId !== "none" && runId !== previousRunId) {
        return { runId, phase: metadata?.phase ?? "unknown" };
      }
    }
    await delay(750);
  } while (Date.now() < deadline);
  return { runId: "none", phase: "unknown" };
}

async function waitForTerminalRun(
  app: TaskInvocation["app"],
  runId: string,
  timeoutMs: number
): Promise<{ runId: string; phase: string }> {
  const terminalPhases = new Set(["completed", "cancelled", "interrupted", "failed", "expired"]);
  const deadline = Date.now() + timeoutMs;
  do {
    const response = await app.artifacts.query<ArtifactCatalog>({ providerId, artifactId });
    if (response.responseType === "tool.result") {
      const metadata = response.payload.result.providers
        ?.find(provider => provider.id === providerId)
        ?.artifacts?.find(artifact => artifact.id === artifactId)
        ?.metadata;
      if (metadata?.latestRunId === runId && terminalPhases.has(metadata.phase ?? "")) {
        return { runId, phase: metadata.phase };
      }
    }
    await delay(1_000);
  } while (Date.now() < deadline);
  return { runId, phase: "timed_out" };
}

async function readTranscriptResult(
  ansight: TaskInvocation["ansight"],
  response: AppToolCallResult<unknown>,
  runId: string
): Promise<TranscriptResult> {
  const direct = newestArtifact(response.artifacts ?? [], runId);
  const snapshot = direct ?? await waitForArtifactSnapshot(ansight, runId, 10_000);
  if (!snapshot.snapshotId) {
    throw new Error("The transcript artifact was captured without a readable snapshot ID.");
  }
  const files = await ansight.artifacts.listFiles({ snapshotId: snapshot.snapshotId, limit: 20 });
  const jsonFile = files.entries.find(entry =>
    entry.path?.endsWith(".json") && (entry.path.includes(runId) || files.entries.length === 1)
  );
  if (!jsonFile?.path) {
    throw new Error("The transcript artifact snapshot contains no JSON result file.");
  }
  const content = await ansight.artifacts.readFile({
    snapshotId: snapshot.snapshotId,
    path: jsonFile.path,
    maxBytes: 1_048_576
  });
  if (content.encoding !== "utf-8" || content.isTruncated || !content.text) {
    throw new Error("The transcript JSON artifact could not be read completely as UTF-8.");
  }
  return JSON.parse(content.text) as TranscriptResult;
}

function newestArtifact(artifacts: ArtifactDescriptor[], runId: string): ArtifactDescriptor | undefined {
  return artifacts
    .filter(artifact => artifact.snapshotId && (
      artifact.artifactId === artifactId || artifact.path?.includes(runId) || !artifact.path
    ))
    .sort((left, right) => (right.capturedAtUtc ?? "").localeCompare(left.capturedAtUtc ?? ""))[0];
}

async function waitForAppState(
  ansight: TaskInvocation["ansight"],
  expectedState: "background" | "foreground",
  timeoutMs: number
): Promise<string> {
  const deadline = Date.now() + timeoutMs;
  let observedState = "unknown";
  do {
    observedState = (await ansight.session.getAppState()).appState;
    if (observedState === expectedState) return observedState;
    await delay(250);
  } while (Date.now() < deadline);
  return observedState;
}

async function waitForArtifactSnapshot(
  ansight: TaskInvocation["ansight"],
  runId: string,
  timeoutMs: number
): Promise<ArtifactDescriptor> {
  const deadline = Date.now() + timeoutMs;
  do {
    const sessionArtifacts = await ansight.artifacts.getSession({
      types: ["artifactSnapshots"],
      limit: 100
    });
    const artifact = newestArtifact(sessionArtifacts.artifactSnapshots ?? [], runId);
    if (artifact) return artifact;
    await delay(1_000);
  } while (Date.now() < deadline);
  throw new Error("The captured transcript artifact did not appear in session evidence.");
}

function delay(milliseconds: number): Promise<void> {
  return new Promise(resolve => globalThis.setTimeout(resolve, milliseconds));
}
