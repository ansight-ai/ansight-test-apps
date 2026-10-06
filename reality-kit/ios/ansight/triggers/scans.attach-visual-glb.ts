import type { TriggerContext, TriggerDefinition } from "./ansight-trigger.d.ts";

type ScanReady = { label: string; details?: string };

export const trigger = {
  "schemaVersion": 1,
  "appId": "ai.ansight.testapps.realitykitcapture",
  "eventKind": "app.event",
  "conditions": [
    { "field": "payload.label", "operator": "equals", "value": "boulder.scan.glb.ready" },
    { "field": "sessionId", "operator": "exists" }
  ],
  "actionTimeoutSeconds": 120,
  "retry": { "maxAttempts": 2, "initialDelayMs": 500, "backoffMultiplier": 2, "maxDelayMs": 2000 }
} satisfies TriggerDefinition;

export default function attachVisualGlb({ event, app }: TriggerContext<ScanReady>) {
  return app.artifacts.request({
    providerId: "boulder.scan",
    artifactId: "visual-glb",
    chunkBytes: 524288,
    arguments: { scanId: event.payload.details ?? "" },
  });
}
