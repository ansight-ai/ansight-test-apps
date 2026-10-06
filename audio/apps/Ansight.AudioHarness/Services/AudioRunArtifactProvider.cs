#if DEBUG
using Ansight.Artifacts;
using Ansight.Tools;

namespace Ansight.AudioHarness.Services;

public sealed class AudioRunArtifactProvider(AudioRunStore runs) : IArtifactProvider
{
    public ArtifactProviderDescriptor Descriptor { get; } = new(AudioRunStore.ProviderId,
        "Audio harness runs", "Immutable terminal results and actual microphone recordings.", "audio-harness");

    public Task<IReadOnlyList<ArtifactDefinition>> QueryAsync(ArtifactQueryContext context, CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();
        var metadata = new Dictionary<string, string> { ["latestRunId"] = runs.LatestRunId ?? "", ["resultSchema"] = "ansight.audio-harness-result/v1" };
        IReadOnlyList<ArtifactDefinition> definitions =
        [
            Define(AudioRunStore.ResultArtifactId, "Run result", "application/json", "result.json", metadata),
            Define(AudioRunStore.CaptureArtifactId, "Microphone recording", "audio/wav", "microphone.wav", metadata)
        ];
        return Task.FromResult(definitions);
    }

    public Task<ArtifactResult> CreateAsync(ArtifactRequest request, CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();
        if (request.ProviderId != AudioRunStore.ProviderId || !request.Arguments.TryGetValue("runId", out var runId))
            throw new ArgumentException("Request audio-harness.runs with the exact runId argument.");
        var run = runs.GetRun(runId);
        var isRecording = request.ArtifactId == AudioRunStore.CaptureArtifactId;
        if (request.ArtifactId != AudioRunStore.ResultArtifactId && !isRecording) throw new ArgumentException("Unknown audio run artifact.");
        if (isRecording && (!run.Capture.Available || run.CapturePath is null)) throw new InvalidOperationException("This run has no finalized microphone recording.");
        var path = isRecording ? run.CapturePath! : run.ResultPath;
        var payload = ArtifactPayload.FromFile(path);
        return Task.FromResult(new ArtifactResult(new ArtifactMetadata(request.ArtifactId, Descriptor.Id,
            isRecording ? "Microphone recording" : "Audio run result", isRecording ? "audio" : "report",
            isRecording ? "audio/wav" : "application/json", $"{runId}-{(isRecording ? "microphone.wav" : "result.json")}")
        {
            SizeBytes = payload.SizeBytes,
            Tags = ["audio-harness", runId],
            Metadata = new Dictionary<string, string> { ["runId"] = runId, ["resultSchema"] = "ansight.audio-harness-result/v1", ["captureAvailable"] = run.Capture.Available.ToString().ToLowerInvariant() }
        }, payload));
    }

    private static ArtifactDefinition Define(string id, string name, string mimeType, string fileName, IReadOnlyDictionary<string, string> metadata)
        => new(id, name, "Request the immutable saved artifact for one exact terminal run.", mimeType == "audio/wav" ? "audio" : "report", "audio-harness",
            new ArtifactContentDescriptor([mimeType]) { DefaultMimeType = mimeType, SuggestedFileName = fileName, SupportsText = mimeType == "application/json", SupportsBinary = true },
            ToolSchema.Object(properties: new Dictionary<string, ToolSchema> { ["runId"] = ToolSchema.String("Exact run ID displayed by the harness.") }, required: ["runId"], additionalProperties: false), ToolPolicy.Read)
        { Metadata = metadata };
}
#endif
