import type { TaskDefinition, TaskInvocation, ScreenshotFrame } from './ansight-task.d.ts';

export const task = {
  "schemaVersion": 1,
  "appId": "ai.ansight.testapps.screenshotgeometry",
  "title": "Verify periodic screenshot metadata",
  "description": "Check periodic JPEG metadata against the selected SDK capture setting before any task screenshots.",
  "platforms": [
    "android",
    "ios"
  ],
  "requires": {
    "capabilities": [
      "ui.semantic"
    ]
  },
  "maximumActions": 15,
  "timeoutSeconds": 45,
  "inputSchema": {
    "type": "object",
    "properties": {
      "expectedMetadata": {
        "type": "boolean",
        "default": true
      }
    },
    "additionalProperties": false
  }
} satisfies TaskDefinition;

export default async function runTask({ ansight, input, expect }: TaskInvocation<{ expectedMetadata: boolean }>) {
  let frame: ScreenshotFrame | undefined;
  for (let attempt = 0; attempt < 5; attempt++) {
    await ansight.ui.waitFor({ automationId: 'geometry.connection', text: 'Connected', exact: true,
      condition: 'stable', stableSamples: 3, pollIntervalMs: 600, timeoutMs: 10000 });
    try { frame = (await ansight.screenshots.getFrame()).frame; } catch { continue; }
    if (!input.expectedMetadata || frame.format === 'jpeg') break;
  }
  expect(Boolean(frame?.frameId), { id: 'periodic-image-retained' }).toBe(true);
  expect(Boolean(frame?.geometry), { id: 'periodic-setting-respected' }).toBe(input.expectedMetadata);
  if (input.expectedMetadata) {
    expect(frame?.geometry?.coordinateSpace, { id: 'periodic-normalized' }).toBe('image-normalized');
    expect(frame?.geometry?.captureTarget, { id: 'periodic-app-window' }).toBe('appWindow');
  }
  return { frameId: frame?.frameId, geometry: frame?.geometry, expectedMetadata: input.expectedMetadata };
}
