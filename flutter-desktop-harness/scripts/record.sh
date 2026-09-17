#!/usr/bin/env bash
set -euo pipefail

app_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
sdk_root="$(cd "${app_root}/../../ansight-sdk" && pwd)"
app_id="ai.ansight.flutter.harness"
receipt="${app_root}/validation/latest-session.json"
screenshot="${app_root}/validation/latest-screenshot.jpg"
screenshot_receipt_path="validation/latest-screenshot.jpg"
started_utc="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

if ! command -v ansight >/dev/null 2>&1; then
  echo "error: ansight CLI is required" >&2
  exit 1
fi

if ! ansight host status --json | jq -e '.isRunning == true' >/dev/null; then
  echo "error: start the resident host with 'ansight host run'" >&2
  exit 1
fi

(
  cd "${app_root}"
  export ANSIGHT_USE_LOCAL_SDK=1
  export ANSIGHT_LOCAL_SDK_PATH="${sdk_root}/src/ios"
  flutter pub get
  flutter test integration_test/recording_test.dart -d macos
)

session_id=""
for _ in $(seq 1 20); do
  listing="$(
    ansight session list \
      --app-id "${app_id}" \
      --platform macos \
      --from "${started_utc}" \
      --has-telemetry \
      --limit 20 \
      --json
  )"
  session_id="$(
    jq -r '.sessions | sort_by(.createdUtc) | last | .sessionId // empty' \
      <<<"${listing}"
  )"
  if [[ -n "${session_id}" ]]; then
    break
  fi
  sleep 1
done

if [[ -z "${session_id}" ]]; then
  echo "error: no recorded macOS Ansight session was found" >&2
  exit 1
fi

ansight session metadata "${session_id}" \
  --name "Flutter desktop harness validation" \
  --notes "Full Flutter macOS harness integration scenario." \
  --tag flutter \
  --tag macos \
  --tag harness \
  --tag sdk-validation \
  --pin \
  --json >/dev/null

mkdir -p "$(dirname "${receipt}")"
evidence_dir="$(mktemp -d)"
trap 'rm -rf "${evidence_dir}"' EXIT
fps_file="${evidence_dir}/fps.json"
images_file="${evidence_dir}/images.json"
trees_file="${evidence_dir}/trees.json"
touches_file="${evidence_dir}/touches.json"
ansight session metrics "${session_id}" --channel 3 --limit 100 --json >"${fps_file}"
ansight session images "${session_id}" --limit 100 --json >"${images_file}"
ansight session trees "${session_id}" --limit 100 --json >"${trees_file}"
ansight session touches "${session_id}" --limit 100 --json >"${touches_file}"
tree_timestamp="$(jq -r '.items | last | .screenshotCapturedAtUtc // empty' "${trees_file}")"
correlated_frame_id="$(
  jq -r \
    --arg timestamp "${tree_timestamp}" \
    '.items | map(select(.capturedAtUtc == $timestamp)) | last | .frameId // empty' \
    "${images_file}"
)"

if [[ -z "${correlated_frame_id}" ]]; then
  echo "error: no screenshot is correlated with the recorded Flutter visual tree" >&2
  exit 1
fi

ansight session screenshot export "${session_id}" \
  --frame-id "${correlated_frame_id}" \
  --output "${screenshot}" \
  --force \
  --json >/dev/null

ansight session show "${session_id}" --json |
  jq \
    --arg screenshotPath "${screenshot_receipt_path}" \
    --slurpfile fps "${fps_file}" \
    --slurpfile images "${images_file}" \
    --slurpfile trees "${trees_file}" \
    --slurpfile touches "${touches_file}" \
    '($trees[0].items | last) as $tree | {
    schema: "ai.ansight.flutter-desktop-harness-session.v1",
    generatedUtc: (now | todateiso8601),
    evidence: {
      screenshot: (($images[0].items | map(
        select(.capturedAtUtc == $tree.screenshotCapturedAtUtc)
      ) | last) | {
        frameId,
        capturedAtUtc,
        format,
        width,
        height,
        quality,
        byteCount,
        exportedPath: $screenshotPath
      }),
      visualTree: ($tree | {
        snapshotId,
        capturedAtUtc,
        visualTreeKind,
        visualTreeFormat,
        runtimePlatform,
        source,
        nodeCount,
        visitedNodeCount: .payload.visitedNodeCount,
        automationIds: ([.payload.root | .. | objects | .automationId? // empty] | unique),
        truncated,
        screenshotCapturedAtUtc
      }),
      fps: {
        channelId: 3,
        sampleCount: ($fps[0].samples | length),
        latestSample: ($fps[0].samples | last)
      },
      touch: {
        sampleCount: $touches[0].totalCount,
        firstSample: ($touches[0].items | first),
        latestSample: ($touches[0].items | last)
      }
    },
    session: {
      sessionId: .session.sessionId,
      appId: .session.appId,
      clientName: .session.clientName,
      name: .session.name,
      status: .session.status,
      isHistorical: .session.isHistorical,
      isPinned: .session.isPinned,
      createdUtc: .session.createdUtc,
      lastUpdatedUtc: .session.lastUpdatedUtc,
      sdkVersion: .session.sdkVersion,
      tags: .session.tags,
      platform: .session.deviceProfile.device.osName,
      deviceFormFactor: .session.deviceProfile.device.formFactor,
      totals: {
        metrics: .session.totalMetricSampleCount,
        metricChannels: .session.totalMetricChannelCount,
        fpsSamples: ($fps[0].samples | length),
        logs: .session.totalLogCount,
        events: .session.totalApplicationEventCount,
        images: .session.totalImageCount,
        networkRequests: .session.totalNetworkRequestCount,
        visualTrees: (.session.visualTreeSnapshots | length),
        touches: (.session.touches | length),
        artifacts: (.session.artifactSnapshots | length)
      }
    }
  }' >"${receipt}"

if ! jq -e '
  .session.appId == "ai.ansight.flutter.harness" and
  .session.platform == "macos" and
  .session.isPinned == true and
  .session.totals.metrics > 0 and
  .session.totals.fpsSamples > 0 and
  .session.totals.events > 0 and
  .session.totals.logs > 0 and
  .session.totals.images > 0 and
  .session.totals.visualTrees > 0 and
  .session.totals.touches > 0 and
  .evidence.screenshot.frameId != null and
  .evidence.screenshot.byteCount > 0 and
  .evidence.visualTree.snapshotId != null and
  .evidence.visualTree.visualTreeKind == "flutter" and
  .evidence.visualTree.nodeCount > 0 and
  .evidence.visualTree.truncated == false and
  (.evidence.visualTree.automationIds | index("harness-scroll")) != null and
  (.evidence.visualTree.automationIds | index("run-e2e-scenario")) != null and
  .evidence.visualTree.screenshotCapturedAtUtc == .evidence.visualTree.capturedAtUtc and
  .evidence.screenshot.capturedAtUtc == .evidence.visualTree.screenshotCapturedAtUtc and
  .evidence.fps.sampleCount > 0 and
  (.evidence.fps.latestSample != null) and
  .evidence.touch.sampleCount > 0 and
  .evidence.touch.firstSample != null
' "${receipt}" >/dev/null; then
  echo "error: recorded session is missing required evidence" >&2
  cat "${receipt}" >&2
  exit 1
fi

cat "${receipt}"
