using System.Text.Json;
using Ansight.AudioHarness.Core;

namespace Ansight.AudioHarness.Services;

public sealed record SavedAudioRun(string RunId, string Json, string ResultPath, string? CapturePath, MicrophoneCaptureInfo Capture);

public sealed class AudioRunStore
{
    public const string ProviderId = "audio-harness.runs";
    public const string ResultArtifactId = "run-result";
    public const string CaptureArtifactId = "microphone-wav";
    private readonly string resultsDirectory = Path.Combine(FileSystem.AppDataDirectory, "audio-results");
    private string? latestRunId;

    public string? LatestRunId => Volatile.Read(ref latestRunId);

    public async Task<SavedAudioRun> SaveAsync(string runId, string? sourceCapture, Func<MicrophoneCaptureInfo, string> createJson)
    {
        var directory = GetRunDirectory(runId);
        Directory.CreateDirectory(directory);
        var resultPath = Path.Combine(directory, "result.json");
        if (File.Exists(resultPath)) throw new InvalidOperationException("A terminal run snapshot is immutable.");
        string? capturePath = null;
        var capture = new MicrophoneCaptureInfo(false, "This run did not produce a finalized microphone WAV.");
        if (sourceCapture is not null)
        {
            try
            {
                var nativePath = Path.GetFullPath(sourceCapture);
                var allowedRoot = Path.Combine(FileSystem.AppDataDirectory, "audio-captures") + Path.DirectorySeparatorChar;
                if (!nativePath.StartsWith(allowedRoot, StringComparison.Ordinal)) throw new InvalidDataException("The recording is outside the harness capture directory.");
                if (new FileInfo(nativePath).Length > 32 * 1024 * 1024) throw new InvalidDataException("The microphone recording exceeds the harness snapshot limit.");
                var bytes = await File.ReadAllBytesAsync(nativePath);
                capture = MicrophoneWaveInspector.Inspect(bytes);
                capturePath = Path.Combine(directory, "microphone.wav");
                await File.WriteAllBytesAsync(capturePath, bytes);
            }
            catch (Exception error)
            {
                capture = new MicrophoneCaptureInfo(false, "Microphone WAV could not be snapshotted: " + error.Message);
                capturePath = null;
            }
        }
        var json = createJson(capture);
        var temporaryResult = resultPath + ".tmp";
        await File.WriteAllTextAsync(temporaryResult, json);
        File.Move(temporaryResult, resultPath, overwrite: false);
        var temporaryLatest = Path.Combine(resultsDirectory, "latest.json.tmp");
        await File.WriteAllTextAsync(temporaryLatest, json);
        File.Move(temporaryLatest, Path.Combine(resultsDirectory, "latest.json"), overwrite: true);
        Volatile.Write(ref latestRunId, runId);
        return new(runId, json, resultPath, capturePath, capture);
    }

    public SavedAudioRun GetRun(string runId)
    {
        var directory = GetRunDirectory(runId);
        var path = Path.Combine(directory, "result.json");
        if (!File.Exists(path)) throw new InvalidOperationException("No saved terminal result exists for this exact run ID.");
        var json = File.ReadAllText(path);
        using var parsed = JsonDocument.Parse(json);
        if (parsed.RootElement.GetProperty("runId").GetString() != runId) throw new InvalidDataException("The saved run identity does not match the request.");
        var capture = JsonSerializer.Deserialize<MicrophoneCaptureInfo>(parsed.RootElement.GetProperty("capture"), new JsonSerializerOptions(JsonSerializerDefaults.Web))!;
        return new(runId, json, path, capture.Available ? Path.Combine(directory, "microphone.wav") : null, capture);
    }

    private string GetRunDirectory(string runId)
    {
        if (!Guid.TryParseExact(runId, "N", out var id) || id.ToString("N") != runId)
            throw new ArgumentException("Specify an exact lowercase run ID from the harness.", nameof(runId));
        return Path.Combine(resultsDirectory, "runs", runId);
    }

    public static void AnnounceTerminalRun(SavedAudioRun run, string phase, bool captureOnly)
    {
#if DEBUG
        global::Ansight.Runtime.Event("audio-harness.run.finished", global::Ansight.Telemetry.Events.AppEventType.Info,
            JsonSerializer.Serialize(new
            {
                schema = "ansight.audio-harness-terminal/v1", runId = run.RunId,
                providerId = ProviderId, resultArtifactId = ResultArtifactId,
                captureArtifactId = run.Capture.Available ? CaptureArtifactId : null,
                phase, captureOnly, captureAvailable = run.Capture.Available
            }));
#endif
    }
}
