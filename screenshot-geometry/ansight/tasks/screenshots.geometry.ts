import type { TaskDefinition, TaskInvocation, ScreenshotIgnoreRegion } from './ansight-task.d.ts';

export const task = {
  "schemaVersion": 1,
  "appId": "ai.ansight.testapps.screenshotgeometry",
  "title": "Validate screenshot metadata and masks",
  "description": "Prove capture opt-out, retained geometry, explicit app-clock masks, and changes outside the mask.",
  "platforms": [
    "android",
    "ios"
  ],
  "requires": {
    "capabilities": [
      "ui.semantic",
      "app.tools"
    ]
  },
  "maximumActions": 50,
  "timeoutSeconds": 120,
  "inputSchema": {
    "type": "object",
    "properties": {},
    "additionalProperties": false
  }
} satisfies TaskDefinition;

export default async function runTask({ ansight, app, expect }: TaskInvocation) {
  expect((await ansight.ui.waitFor({ automationId: 'geometry.connection', text: 'Connected', exact: true, timeoutMs: 20000 })).satisfied,
    { id: 'connected' }).toBe(true);
  await ansight.ui.tap({ automationId: 'geometry.reset' });
  const capture = (includeSystemUiMetadata = true) => ansight.screenshots.capture({ format: 'png', maxWidth: 720, afterScreenUpdates: true, includeSystemUiMetadata });
  const baseline = await capture();
  expect(baseline.geometry?.coordinateSpace, { id: 'normalized-coordinates' }).toBe('image-normalized');
  expect(baseline.geometry?.captureTarget, { id: 'app-window-target' }).toBe('appWindow');
  const safe = baseline.geometry?.safeAreaInsets;
  expect(Boolean(safe && Object.values(safe).every(value => Number.isFinite(value) && value >= 0 && value < 1)
    && safe.top + safe.bottom < 1 && safe.left + safe.right < 1), { id: 'valid-safe-insets' }).toBe(true);
  for (const kind of ['statusBar', 'navigationBar'] as const)
    expect(baseline.geometry?.systemUi[kind].state, { id: `${kind}-not-in-app-window` }).toBe('absent');
  expect((await ansight.screenshots.getFrame({ frameId: baseline.frameId })).frame.geometry, { id: 'geometry-retained' }).toEqual(baseline.geometry);
  const without = await capture(false);
  expect(without.geometry == null, { id: 'capture-opt-out' }).toBe(true);
  expect((await ansight.screenshots.getFrame({ frameId: without.frameId })).frame.geometry == null, { id: 'opt-out-retained' }).toBe(true);
  let unavailable = false;
  try { await ansight.screenshots.compare({ image: { frameId: without.frameId }, reference: { frameId: baseline.frameId }, ignoreSystemUi: ['statusBar'] }); }
  catch (error) { unavailable = /geometry|metadata/i.test(String(error)); }
  expect(unavailable, { id: 'missing-metadata-fails-explicitly' }).toBe(true);
  const bounds = await app.callTool<ScreenshotIgnoreRegion>('harness.clock_bounds');
  if (bounds.responseType === 'tool.error') throw new Error(bounds.payload.message);
  const clockMask = bounds.payload.result;
  await ansight.ui.tap({ automationId: 'geometry.advance' });
  expect((await ansight.ui.waitFor({ automationId: 'geometry.clock', text: '12:00:01', exact: true })).satisfied, { id: 'clock-advanced' }).toBe(true);
  const clock = await capture();
  const compare = (frameId: string, ignoreRegions: ScreenshotIgnoreRegion[] = []) => ansight.screenshots.compare({
    image: { frameId }, reference: { frameId: baseline.frameId }, ignoreSystemUi: ['statusBar', 'navigationBar'],
    ignoreRegions, maxDifferenceRatio: 0, pixelThreshold: 16, maxWidth: 720,
  });
  const unmasked = await compare(clock.frameId);
  expect(unmasked.passed, { id: 'system-mask-does-not-hide-app-clock' }).toBe(false);
  expect(unmasked.ignoredPixelCount, { id: 'absent-bars-mask-zero-pixels' }).toBe(0);
  const masked = await compare(clock.frameId, [clockMask]);
  expect(masked.passed, { id: 'explicit-clock-mask-passes' }).toBe(true);
  expect((masked.ignoredPixelCount ?? 0) > 0, { id: 'mask-excludes-pixels' }).toBe(true);
  await ansight.ui.tap({ automationId: 'geometry.change' });
  const changed = await capture();
  const mismatch = await compare(changed.frameId, [clockMask]);
  expect(mismatch.passed, { id: 'cube-change-remains-visible' }).toBe(false);
  expect(mismatch.regions.length > 0, { id: 'difference-regions-retained' }).toBe(true);
  expect(mismatch.systemUiMaskResolutions?.every(item => item.frameId === changed.frameId), { id: 'mask-origin-is-actual-frame' }).toBe(true);
  return { frames: { baseline: baseline.frameId, without: without.frameId, clock: clock.frameId, changed: changed.frameId },
    geometry: baseline.geometry, clockMask, unmasked, masked, mismatch };
}
