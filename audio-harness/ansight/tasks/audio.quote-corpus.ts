import type { TaskDefinition, TaskInvocation } from "./ansight-task.d.ts";
import { evidenceDirectory, loadQuotes, writeEvidence } from "./audio-support.ts";
import type { AudioTaskMode, AudioTaskOutput } from "./audio-support.ts";

type Input = { mode: AudioTaskMode };

export const task = {
  "schemaVersion": 1,
  "appId": "ai.ansight.audioharness",
  "title": "Verify all eight speech fixtures",
  "description": "Composes audio.inject-and-verify for all eight quote WAVs serially on the selected session. Capture requires microphone waveforms and wrong-fixture controls; whisper additionally requires matching offline transcripts and provenance. Explicit transcript mode uses native recognition. Stops and preserves evidence at the first failed child.",
  "feature": "audio",
  "keywords": ["corpus", "quotes", "microphone", "speech", "whisper", "offline", "all", "eight"],
  "inputSchema": {
    "type": "object",
    "properties": { "mode": { "type": "string", "enum": ["capture", "transcript", "whisper"], "default": "capture" } },
    "additionalProperties": false
  },
  "timeoutSeconds": 300,
  "maximumActions": 10
} satisfies TaskDefinition;

export default async function runTask({ run, input, ansight, expect }: TaskInvocation<Input>) {
  const directory = evidenceDirectory(run.repositoryRootPath, run.runId);
  const quotes = loadQuotes(run.repositoryRootPath);
  const catalog = await ansight.tasks.list({ query: "microphone", feature: "audio", maxResults: 20 });
  expect(catalog.tasks.some(candidate => candidate.taskId === "audio.inject-and-verify"),
    { id: "single-fixture-task-discovered" }).toBe(true);
  const results: AudioTaskOutput[] = [];
  try {
    for (const quote of quotes) {
      const child = await ansight.tasks.run<AudioTaskOutput>({
        taskId: "audio.inject-and-verify", input: { fixtureId: quote.id, mode: input.mode },
      });
      expect(child.output?.fixtureId, { id: `fixture-${quote.id}-verified` }).toBe(quote.id);
      const microphoneVerified = child.output?.captureVerified && child.output?.negativeControlRejected;
      const outcomeVerified = input.mode === "capture" ? microphoneVerified
        : input.mode === "whisper" ? microphoneVerified && child.output?.transcriptionVerified
        : child.output?.transcriptionVerified;
      expect(outcomeVerified, { id: `fixture-${quote.id}-outcome` }).toBe(true);
      results.push(child.output!);
      writeEvidence(directory, "corpus.json", { complete: false, mode: input.mode, results });
    }
    expect(results.length, { id: "all-eight-fixtures-verified" }).toBe(8);
    writeEvidence(directory, "corpus.json", { complete: true, mode: input.mode, results });
    return { complete: true, mode: input.mode, fixtureCount: results.length, results, evidenceDirectory: directory };
  } catch (error) {
    writeEvidence(directory, "corpus.json", { complete: false, mode: input.mode, results, error: String(error) });
    throw error;
  }
}
