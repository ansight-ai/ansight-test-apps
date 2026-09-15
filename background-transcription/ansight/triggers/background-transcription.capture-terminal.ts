import type {
  TriggerContext,
  TriggerDefinition
} from "./ansight-trigger.d.ts";

export const trigger = {
  "schemaVersion": 1,
  "appId": "ai.ansight.testapps.backgroundtranscription",
  "eventKind": "app.event",
  "eventSchema": {
    "type": "object",
    "properties": {
      "label": { "type": "string" },
      "details": { "type": "string" }
    },
    "required": ["label", "details"],
    "additionalProperties": true
  },
  "conditions": [
    {
      "field": "payload.label",
      "operator": "equals",
      "value": "background_transcription.terminal"
    },
    {
      "field": "payload.details",
      "operator": "exists"
    }
  ],
  "functionTimeoutMs": 100,
  "actionTimeoutSeconds": 30,
  "retry": {
    "maxAttempts": 3,
    "initialDelayMs": 250,
    "backoffMultiplier": 2,
    "maxDelayMs": 1000
  }
} satisfies TriggerDefinition;

type TerminalEventPayload = {
  label: string;
  details: string;
};

type TerminalEventDetails = {
  schema: string;
  runId: string;
  phase: string;
  providerId: string;
  resultArtifactId: string;
};

export default async function captureTerminalTranscript({
  event,
  app
}: TriggerContext<TerminalEventPayload, "app.event">) {
  let details: TerminalEventDetails;
  try {
    details = JSON.parse(event.payload.details) as TerminalEventDetails;
  } catch {
    throw new Error("Terminal transcription event contains invalid JSON details.");
  }

  const terminalPhases = new Set(["completed", "cancelled", "interrupted", "failed", "expired"]);
  if (
    details.schema !== "ansight.background-transcription-terminal/v1" ||
    !terminalPhases.has(details.phase) ||
    !/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(details.runId) ||
    details.providerId !== "background-transcription.runs" ||
    details.resultArtifactId !== "transcript-result"
  ) {
    throw new Error("Terminal transcription event does not match the expected contract.");
  }

  return app.artifacts.request({
    providerId: details.providerId,
    artifactId: details.resultArtifactId,
    arguments: { runId: details.runId }
  });
}
