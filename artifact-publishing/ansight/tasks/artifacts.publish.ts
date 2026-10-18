import { Buffer } from "node:buffer";
import { createHash } from "node:crypto";
import type { ArtifactDescriptor, TaskDefinition, TaskInvocation } from "./ansight-task.d.ts";

export const task = {
  "schemaVersion": 1,
  "appId": "ai.ansight.testapps.artifacts",
  "title": "Publish and retain app artifacts",
  "description": "Publish through app buttons, verify retained UTF-8 and binary contents, and reject invalid or cancelled transfers.",
  "feature": "artifacts",
  "keywords": [
    "publish",
    "client",
    "stream",
    "binary",
    "cancellation"
  ],
  "platforms": [
    "android",
    "ios"
  ],
  "requires": {
    "capabilities": [
      "ui.semantic",
      "app.tools",
      "evidence.artifacts"
    ]
  },
  "inputSchema": {
    "type": "object",
    "properties": {},
    "additionalProperties": false
  },
  "maximumActions": 50,
  "timeoutSeconds": 240
} satisfies TaskDefinition;

// The host returns these snapshot/file metadata fields in addition to the generic descriptor.
type RetainedFile = ArtifactDescriptor & {
  snapshotId: string;
  rootAlias: string;
  relativePath: string;
  snapshotRelativePath: string;
  mimeType: string;
};
const reportText = '{"schema":"ansight.artifact-harness/v1","message":"Published from the app — café 🚀","value":42}';
const binarySize = 131089;
const digest = (value: Uint8Array) => createHash("sha256").update(value).digest("hex");

export default async function runTask({ ansight, expect }: TaskInvocation) {
  expect((await ansight.ui.waitFor({ automationId: "artifacts.connection", text: "Connected", exact: true, timeoutMs: 15000 })).satisfied,
    { id: "connected-to-host" }).toBe(true);
  await ansight.ui.tap({ automationId: "artifacts.reset" });
  expect((await ansight.ui.waitFor({ automationId: "artifacts.report-status", text: "Report: not published", exact: true })).satisfied,
    { id: "check-counters-reset" }).toBe(true);

  const baseline = await ansight.artifacts.listFiles({ limit: 5000 });
  expect(baseline.isTruncated, { id: "baseline-list-complete" }).toBe(false);
  const existing = new Set(baseline.entries.map(entry => entry.snapshotId));
  const retained = async () => {
    const result = await ansight.artifacts.listFiles({ limit: 5000 });
    if (result.isTruncated) throw new Error("Artifact listing is truncated; cannot prove the publication count.");
    return (result.entries as RetainedFile[]).filter(entry => entry.rootAlias === "artifact-harness" && !existing.has(entry.snapshotId));
  };

  await ansight.ui.tap({ automationId: "artifacts.publish-report" });
  expect((await ansight.ui.waitFor({ automationId: "artifacts.report-status", text: "Report published: 1", exact: true, timeoutMs: 20000 })).satisfied,
    { id: "report-host-receipt" }).toBe(true);
  const firstFiles = await retained();
  expect(firstFiles.length, { id: "report-retained-before-receipt" }).toBe(1);
  const first = firstFiles[0]!;
  expect(first.relativePath, { id: "report-artifact-id" }).toBe("report");
  expect(first.mimeType, { id: "report-mime-type" }).toBe("application/json");
  const report = await ansight.artifacts.readFile({ snapshotId: first.snapshotId, path: first.snapshotRelativePath, maxBytes: 4096 });
  expect(report.isTruncated, { id: "report-content-complete" }).toBe(false);
  expect(report.encoding, { id: "report-is-utf8" }).toBe("utf-8");
  expect(report.text, { id: "report-unicode-content" }).toBe(reportText);
  expect(report.byteCount, { id: "report-byte-length" }).toBe(Buffer.byteLength(reportText));

  await ansight.ui.tap({ automationId: "artifacts.publish-file" });
  expect((await ansight.ui.waitFor({ automationId: "artifacts.file-status", text: "File published: 1", exact: true, timeoutMs: 20000 })).satisfied,
    { id: "binary-host-receipt" }).toBe(true);
  const binaryFiles = await retained();
  expect(binaryFiles.length, { id: "binary-retained-before-receipt" }).toBe(2);
  const binary = binaryFiles.find(entry => entry.relativePath === "binary")!;
  expect(Boolean(binary), { id: "binary-entry-present" }).toBe(true);
  expect(binary.mimeType, { id: "binary-mime-type" }).toBe("application/octet-stream");
  const file = await ansight.artifacts.readFile({ snapshotId: binary.snapshotId, path: binary.snapshotRelativePath, maxBytes: binarySize, forceBase64: true });
  expect(file.isTruncated, { id: "binary-content-complete" }).toBe(false);
  expect(file.byteCount, { id: "binary-spans-three-chunks" }).toBe(binarySize);
  expect(file.encoding, { id: "binary-content-encoding" }).toBe("base64");
  const bytes = Buffer.from(file.base64 ?? "", "base64");
  const expected = Buffer.from(Array.from({ length: binarySize }, (_, index) => index % 251));
  expect(bytes.length, { id: "binary-decoded-length" }).toBe(binarySize);
  expect(digest(bytes), { id: "binary-sha256-after-source-deletion" }).toBe(digest(expected));

  await ansight.ui.tap({ automationId: "artifacts.publish-report" });
  expect((await ansight.ui.waitFor({ automationId: "artifacts.report-status", text: "Report published: 2", exact: true, timeoutMs: 20000 })).satisfied,
    { id: "repeat-publication-acknowledged" }).toBe(true);
  const repeated = await retained();
  expect(repeated.length, { id: "repeat-creates-separate-snapshot" }).toBe(3);
  expect(new Set(repeated.map(entry => entry.snapshotId)).size, { id: "snapshot-ids-are-distinct" }).toBe(3);

  await ansight.ui.tap({ automationId: "artifacts.reject" });
  expect((await ansight.ui.waitFor({ automationId: "artifacts.reject-status", text: "Invalid metadata rejected", exact: true, timeoutMs: 10000 })).satisfied,
    { id: "invalid-metadata-rejected" }).toBe(true);
  expect((await retained()).length, { id: "rejected-upload-not-retained" }).toBe(3);

  await ansight.ui.tap({ automationId: "artifacts.cancel" });
  expect((await ansight.ui.waitFor({ automationId: "artifacts.cancel-status", text: "Partial upload cancelled", exact: true, timeoutMs: 10000 })).satisfied,
    { id: "partial-upload-cancellation-propagated" }).toBe(true);
  expect((await retained()).length, { id: "cancelled-upload-not-retained" }).toBe(3);
  expect((await ansight.ui.assert({ automationId: "artifacts.connection", expectedText: "Connected" })).passed,
    { id: "connection-survives-cancellation" }).toBe(true);

  await ansight.ui.tap({ automationId: "artifacts.publish-report" });
  expect((await ansight.ui.waitFor({ automationId: "artifacts.report-status", text: "Report published: 3", exact: true, timeoutMs: 20000 })).satisfied,
    { id: "publication-after-abort-succeeds" }).toBe(true);
  const finalFiles = await retained();
  expect(finalFiles.length, { id: "four-successful-publications-retained" }).toBe(4);
  expect(finalFiles.filter(entry => entry.relativePath === "report").length, { id: "three-report-snapshots-retained" }).toBe(3);
  const finalReport = finalFiles.find(entry => entry.relativePath === "report" && entry.snapshotId !== first.snapshotId)!;
  expect((await ansight.artifacts.readFile({ snapshotId: finalReport.snapshotId, path: finalReport.snapshotRelativePath, maxBytes: 4096 })).text,
    { id: "repeated-report-content-preserved" }).toBe(reportText);

  return { publishedSnapshots: finalFiles.map(entry => ({ snapshotId: entry.snapshotId, artifactId: entry.relativePath, path: entry.snapshotRelativePath })),
    binarySize, binarySha256: digest(bytes), invalidUploadRetained: false, cancelledUploadRetained: false };
}
