#!/usr/bin/env node
// Verify persisted capture files through the actual player span decoder after capture ends.
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { resolve, join } from 'node:path';
import { pathToFileURL } from 'node:url';
const [playerRoot, ...captureDirectories] = process.argv.slice(2);
if (!playerRoot || !captureDirectories.length) throw new Error('Usage: node scripts/verify-retained.mjs <built-player-repo> <capture-directory> [...]');
const { spansFromEvents } = await import(pathToFileURL(resolve(playerRoot, 'dist/library/replay/telemetrySpans.js')));
const read = async (directory, file) => JSON.parse(await readFile(join(directory, file), 'utf8'));
const results = [];
for (const directory of captureDirectories) {
  const { session } = await read(directory, 'session.json');
  assert.equal(session.isHistorical, true, 'Capture must be stopped');
  const { channels } = await read(directory, 'metric-channels.json');
  const render = channels.find(channel => channel.channelId === 64);
  assert.equal(render.unit, 'ms'); assert.equal(render.group, 'Rendering');
  const { metrics } = await read(directory, 'telemetry/channel-064.json');
  for (const value of [16.67, 0.125, -0.25]) assert(metrics.some(sample => sample.value === value));
  const { events } = await read(directory, 'application-events.json');
  const spans = spansFromEvents(events);
  assert(spans.length >= 9 && spans.length % 9 === 0);
  const count = spans.length / 9;
  assert.equal(spans.filter(span => span.status === 'ok').length, count * 6);
  assert.equal(spans.filter(span => span.status === 'error').length, count);
  assert.equal(spans.filter(span => span.status === 'cancelled').length, count);
  const incomplete = spans.filter(span => span.status === 'incomplete');
  assert.equal(incomplete.length, count);
  assert(incomplete.every(span => span.name === 'Interrupted work' && span.durationMs === null));
  for (const span of spans.filter(span => span.parentSpanId)) assert(spans.some(parent => parent.id === span.parentSpanId && parent.name === 'Frame'));
  results.push({ sessionId: session.sessionId, passed: true, values: metrics.map(sample => sample.value), spanCount: spans.length, incompleteSpanCount: incomplete.length });
}
console.log(JSON.stringify({ sessions: results }, null, 2));
