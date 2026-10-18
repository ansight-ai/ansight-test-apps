import type { TaskDefinition, TaskInvocation, TelemetrySpan } from './ansight-task.d.ts';

export const task = {
  "schemaVersion": 1,
  "appId": "ai.ansight.testapps.telemetry",
  "title": "Record fractional metrics and timed spans",
  "description": "Validate precision, metadata, nested/overlapping spans, outcomes, incomplete operations, and MAUI appearance properties.",
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
  "maximumActions": 30,
  "timeoutSeconds": 120,
  "inputSchema": {
    "type": "object",
    "properties": {},
    "additionalProperties": false
  }
} satisfies TaskDefinition;

type Series = { channelId: number; unit?: string; group?: string; samples: Array<{ value: number }> };
type Node = { automationId?: string; properties?: Record<string, any>; children?: Node[] };
function find(value: unknown, id: string): Node | undefined {
  if (!value || typeof value !== 'object') return undefined;
  const node = value as Node;
  if (node.automationId === id) return node;
  for (const child of Object.values(value)) {
    if (Array.isArray(child)) { for (const item of child) { const match = find(item, id); if (match) return match; } }
    else if (typeof child === 'object') { const match = find(child, id); if (match) return match; }
  }
  return undefined;
}

export default async function runTask({ ansight, app, expect }: TaskInvocation) {
  expect((await ansight.ui.waitFor({ automationId: 'telemetry.connection', text: 'Connected', exact: true, timeoutMs: 20000 })).satisfied,
    { id: 'connected' }).toBe(true);
  const before = await ansight.telemetry.getTimeline({ channelIds: [64, 65, 66] });
  const prior = new Set(before.spans.map(span => span.spanId));
  await ansight.ui.tap({ automationId: 'telemetry.run' });
  expect((await ansight.ui.waitFor({ automationId: 'telemetry.status', text: 'Recorded', exact: true, timeoutMs: 15000 })).satisfied,
    { id: 'recorded' }).toBe(true);
  const telemetry = await ansight.telemetry.get({ channelIds: [64, 65, 66] });
  const series = telemetry.telemetry as unknown as Series[];
  const render = series.find(item => item.channelId === 64)!;
  expect(Boolean(render), { id: 'render-channel' }).toBe(true);
  expect(render.unit, { id: 'unit-preserved' }).toBe('ms');
  expect(render.group, { id: 'group-preserved' }).toBe('Rendering');
  for (const value of [16.67, 0.125, -0.25]) expect(render.samples.some(sample => sample.value === value), { id: `fraction-${value}` }).toBe(true);
  expect(series.find(item => item.channelId === 66)?.samples.some(sample => sample.value === 7), { id: 'integer-still-supported' }).toBe(true);
  const timeline = await ansight.telemetry.getTimeline({ channelIds: [64, 65, 66] });
  expect(timeline.spansTruncated, { id: 'complete-span-query' }).toBe(false);
  const spans = timeline.spans.filter(span => !prior.has(span.spanId));
  expect(spans.length, { id: 'nine-spans' }).toBe(9);
  const span = (name: string): TelemetrySpan => spans.find(item => item.name === name)!;
  const frame = span('Frame');
  for (const name of ['Build', 'Raster', 'Overlap A', 'Overlap B']) {
    expect(span(name).parentSpanId, { id: `parent-${name}` }).toBe(frame.spanId);
    expect(span(name).status, { id: `success-${name}` }).toBe('ok');
  }
  expect(span('Async work').status, { id: 'async-success' }).toBe('ok');
  expect(span('Failed work').status, { id: 'failure-outcome' }).toBe('error');
  expect(span('Cancelled work').status, { id: 'cancelled-outcome' }).toBe('cancelled');
  expect(span('Interrupted work').status, { id: 'incomplete-outcome' }).toBe('incomplete');
  expect(span('Interrupted work').durationMs, { id: 'no-invented-duration' }).toBe(null);
  expect(spans.filter(item => item.status !== 'incomplete').every(item => Number.isFinite(item.durationMs) && item.durationMs! >= 0), { id: 'finite-monotonic-durations' }).toBe(true);
  const a = span('Overlap A'), b = span('Overlap B');
  expect(Date.parse(a.startedAtUtc) + a.durationMs! >= Date.parse(b.startedAtUtc), { id: 'overlap-preserved' }).toBe(true);
  const tree = await app.maui.getVisualTree({ includeProperties: true, includeBindableProperties: false });
  expect(tree.responseType, { id: 'maui-tree-success' }).toBe('tool.result');
  expect(Boolean(tree.persistedVisualTree?.snapshotId), { id: 'tree-retained' }).toBe(true);
  const retained = await ansight.ui.getVisualTreeSnapshot({ snapshotId: tree.persistedVisualTree!.snapshotId! });
  const title = find(retained.visualTree.payload, 'telemetry.title');
  expect(title?.properties?.font?.size, { id: 'font-size' }).toBe(26);
  expect(title?.properties?.font?.attributes, { id: 'font-bold' }).toBe('Bold');
  expect(title?.properties?.font?.characterSpacing, { id: 'character-spacing' }).toBe(0.5);
  expect(title?.properties?.horizontalTextAlignment, { id: 'text-alignment' }).toBe('Center');
  const layout = find(retained.visualTree.payload, 'telemetry.layout');
  expect(layout?.properties?.spacing, { id: 'layout-spacing' }).toBe(14);
  expect(layout?.properties?.paddingInsets?.top, { id: 'numeric-padding' }).toBe(24);
  expect(find(retained.visualTree.payload, 'telemetry.border')?.properties?.border?.thickness, { id: 'border-thickness' }).toBe(3);
  return { spanIds: spans.map(item => item.spanId), samples: render.samples, spans };
}
