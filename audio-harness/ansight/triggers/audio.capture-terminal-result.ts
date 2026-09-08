import type {
  TriggerContext,
  TriggerDefinition
} from "./ansight-trigger.d.ts";

export const trigger = {
  "schemaVersion": 1,
  "appId": "ai.ansight.audioharness",
  "eventKind": "app.event",
  "conditions": [{ "field": "payload.label", "operator": "equals", "value": "audio-harness.run.finished" }],
  "functionTimeoutMs": 100,
  "actionTimeoutSeconds": 30,
  "retry": { "maxAttempts": 1 }
} satisfies TriggerDefinition;

export default async function runTrigger({ event, app }: TriggerContext<{ details: string }>) {
  const terminal = JSON.parse(event.payload.details) as {
    schema: string; runId: string; providerId: string; resultArtifactId: string;
  };
  if (terminal.schema !== "ansight.audio-harness-terminal/v1" || !/^[a-f0-9]{32}$/.test(terminal.runId)
    || terminal.providerId !== "audio-harness.runs" || terminal.resultArtifactId !== "run-result") {
    throw new Error("Invalid audio harness terminal event.");
  }
  return app.artifacts.request({ providerId: "audio-harness.runs", artifactId: "run-result",
    arguments: { runId: terminal.runId } });
}
