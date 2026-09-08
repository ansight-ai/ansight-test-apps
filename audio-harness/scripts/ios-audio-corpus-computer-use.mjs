// Fallback orchestration for use ONLY from node_repl with the official @oai/sky client.
// The standard runner is run-ios-audio-corpus.py. This helper keeps every UI action
// in Computer Use and uses child processes only for non-UI audio/file verification.
// Import this module, call createCorpus({sky,...}), then await corpus.runNext()
// for each fixture and await corpus.finish(). No default audio device is changed.
import { execFile } from "node:child_process";
import { promisify } from "node:util";
import * as fs from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const execute = promisify(execFile);
const repository = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const app = "/Applications/Xcode.app/Contents/Developer/Applications/Simulator.app";
const appId = "ai.ansight.audioharness";
const now = () => new Date().toISOString();
const writeJson = (filename, value) => fs.writeFile(filename, JSON.stringify(value, null, 2) + "\n");

export async function createCorpus({ sky, simulator, windowTitle, audioDevice = "BlackHole2ch_UID", output, python }) {
  if (!sky || !simulator || !windowTitle || !output) throw Error("Supply sky, simulator, windowTitle, and a new output path.");
  const container = (await execute("xcrun", ["simctl", "get_app_container", simulator, appId, "data"])).stdout.trim();
  if (!path.resolve(container).split(path.sep).includes(simulator)) throw Error("Unexpected simulator app container.");
  const manifestDirectory = path.join(repository, "fixtures/audio/quotes");
  const manifest = JSON.parse(await fs.readFile(path.join(manifestDirectory, "manifest.json"), "utf8"));
  await fs.mkdir(output, { recursive: false });
  await writeJson(path.join(output, "manifest.json"), manifest);
  const summary = { schema: "ansight.ios-microphone-corpus/v1", simulator, appId, audioDevice,
    uiBackend: "Computer Use @oai/sky through node_repl", startedUtc: now(), transcriptionVerified: false,
    passed: false, cases: [] };
  let index = 0;
  let observation;

  async function observe(filename) {
    observation = await sky.get_app_state({ app, disableDiff: true });
    if (!observation.text.includes(windowTitle)) throw Error("The expected Simulator window is not active.");
    if (filename) {
      await fs.writeFile(filename + ".txt", observation.text);
      if (observation.screenshot?.url?.startsWith("file:"))
        await fs.copyFile(fileURLToPath(observation.screenshot.url), filename + ".png");
    }
    return observation;
  }

  function node(identifier) {
    const lines = observation.text.split("\n").filter(line => line.includes(`ID: ${identifier},`));
    if (lines.length !== 1) throw Error(`Expected one visible ${identifier}; found ${lines.length}.`);
    const match = lines[0].match(/^\s*(\d+)\s/);
    if (!match) throw Error(`Cannot resolve the fresh accessibility index for ${identifier}.`);
    return { index: Number(match[1]), line: lines[0] };
  }

  function phase() {
    return node("capture-phase").line.match(/Description: ([^,]+), ID:/)?.[1];
  }

  async function tap(identifier) {
    await observe();
    const target = node(identifier);
    if (target.line.includes("(disabled)")) throw Error(`${identifier} is disabled.`);
    await sky.click({ app, element_index: target.index });
    await observe();
  }

  async function waitPhase(expected) {
    const deadline = Date.now() + 15000;
    while (phase() !== expected) {
      if (phase() === "Error" || Date.now() >= deadline) throw Error(`Expected ${expected}; observed ${phase()}.`);
      await observe();
    }
  }

  async function ready() {
    await observe();
    if (phase() === "Listening") await tap("stop-listening");
    if (phase() !== "Ready") await tap("reset-test");
    await waitPhase("Ready");
    if (!node("capture-only").line.includes("Value: 1,")) throw Error("Capture-only mode must already be checked.");
  }

  async function runNext() {
    if (index >= manifest.fixtures.length) throw Error("All fixtures have already been attempted.");
    const fixture = manifest.fixtures[index++];
    if (!/^[a-z0-9-]+$/.test(fixture.id) || path.basename(fixture.filename) !== fixture.filename)
      throw Error("Unsafe fixture identifier or filename.");
    const directory = path.join(output, fixture.id);
    await fs.mkdir(directory);
    const result = { fixtureId: fixture.id, startedUtc: now(), passed: false,
      transcriptionVerified: false, evidenceDirectory: directory };
    try {
      const retainedFixture = path.join(directory, "fixture.wav");
      await fs.copyFile(path.join(manifestDirectory, fixture.filename), retainedFixture);
      await writeJson(path.join(directory, "fixture.json"), fixture);
      await ready();
      await observe(path.join(directory, "before"));
      const latest = path.join(container, "Library/audio-results/latest.json");
      const previousRun = JSON.parse(await fs.readFile(latest, "utf8")).runId;
      const started = Date.now();
      await tap("start-listening");
      await waitPhase("Listening");
      await observe(path.join(directory, "listening"));
      const playback = await execute(path.join(repository, "scripts/play-to-audio-device.sh"),
        ["--device", audioDevice, retainedFixture], { timeout: 45000 });
      await fs.writeFile(path.join(directory, "playback.stdout.log"), playback.stdout);
      await fs.writeFile(path.join(directory, "playback.stderr.log"), playback.stderr);
      await tap("stop-listening");
      await waitPhase("Captured");
      await observe(path.join(directory, "captured"));
      const appResult = JSON.parse(await fs.readFile(latest, "utf8"));
      await writeJson(path.join(directory, "app-result.json"), appResult);
      if (!/^[0-9a-f]{32}$/.test(appResult.runId) || appResult.runId === previousRun || Date.parse(appResult.startedUtc) < started)
        throw Error("App result does not belong to this fresh capture.");
      if (appResult.phase !== "Captured" || appResult.captureOnly !== true || appResult.isFinal || appResult.passed || appResult.transcript)
        throw Error("App result is not a capture-only result.");
      const actualPath = await fs.realpath(appResult.captureFilePath);
      const expectedPath = path.join(container, "Library/audio-captures", appResult.runId + ".wav");
      if (actualPath !== expectedPath) throw Error("Capture does not match the fresh run inside this app container.");
      const recording = path.join(directory, "microphone.wav");
      await fs.copyFile(actualPath, recording);
      try {
        await execute(python || path.join(repository, ".venv-audio/bin/python"),
          [path.join(repository, "scripts/verify-microphone-capture.py"), retainedFixture, recording,
            "--output", path.join(directory, "verification.json")], { timeout: 60000 });
      } catch (error) {
        await fs.writeFile(path.join(directory, "verification.stderr.log"), error.stderr || error.message);
      }
      const verification = JSON.parse(await fs.readFile(path.join(directory, "verification.json"), "utf8"));
      Object.assign(result, { runId: appResult.runId, passed: verification.passed === true,
        comparison: verification.comparison, captureDurationSeconds: appResult.durationSeconds });
    } catch (error) {
      result.error = error.message;
      if (error.stdout) await fs.writeFile(path.join(directory, "failed-command.stdout.log"), error.stdout);
      if (error.stderr) await fs.writeFile(path.join(directory, "failed-command.stderr.log"), error.stderr);
    }
    result.completedUtc = now();
    await writeJson(path.join(directory, "result.json"), result);
    summary.cases.push(result);
    await writeJson(path.join(output, "summary.json"), summary);
    return result;
  }

  async function finish() {
    await ready();
    await observe(path.join(output, "final-ready"));
    summary.finalPhase = phase();
    summary.captureOnly = true;
    summary.completedUtc = now();
    summary.passed = summary.cases.length === manifest.fixtures.length && summary.cases.every(item => item.passed);
    await writeJson(path.join(output, "summary.json"), summary);
    return summary;
  }

  return { runNext, finish, total: manifest.fixtures.length, output };
}
