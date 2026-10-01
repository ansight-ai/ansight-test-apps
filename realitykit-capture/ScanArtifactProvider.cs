#if DEBUG
using Ansight.Artifacts;
using Ansight.Tools;

namespace BoulderCaptureSpike;

internal sealed class ScanArtifactProvider : IArtifactProvider
{
    public const string ProviderId = "boulder.scan";
    private const string MimeType = "model/gltf-binary";

    public ArtifactProviderDescriptor Descriptor => new(
        ProviderId, "Boulder scans", "GLB files exported by this capture app", "3D scans");

    public Task<IReadOnlyList<ArtifactDefinition>> QueryAsync(
        ArtifactQueryContext context, CancellationToken cancellationToken)
    {
        var schema = ToolSchema.Object(
            "Identify the completed scan",
            new Dictionary<string, ToolSchema> { ["scanId"] = ToolSchema.String("Scan folder UUID") },
            ["scanId"], false, false);
        IReadOnlyList<ArtifactDefinition> definitions =
        [
            new("visual-glb", "Textured scan GLB", "Visual camera-depth reconstruction",
                "model", "3D scans",
                new ArtifactContentDescriptor([MimeType])
                {
                    DefaultMimeType = MimeType,
                    SuggestedFileName = "space.glb",
                    SupportsBinary = true,
                }, schema, ToolPolicy.Read),
            new("structure-glb", "Structural LiDAR GLB", "Coarse ARKit structural mesh",
                "model", "3D scans",
                new ArtifactContentDescriptor([MimeType])
                {
                    DefaultMimeType = MimeType,
                    SuggestedFileName = "space-structure.glb",
                    SupportsBinary = true,
                }, schema, ToolPolicy.Read),
        ];
        return Task.FromResult(definitions);
    }

    public Task<ArtifactResult> CreateAsync(ArtifactRequest request, CancellationToken cancellationToken)
    {
        if (!request.Arguments.TryGetValue("scanId", out var scanId) ||
            !Guid.TryParse(scanId, out _))
            throw new ArgumentException("A valid scan ID is required.");

        var fileName = request.ArtifactId switch
        {
            "visual-glb" => "space.glb",
            "structure-glb" => "space-structure.glb",
            _ => throw new ArgumentException("Unknown scan artifact."),
        };
        var documents = Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments);
        var path = Path.Combine(documents, "BoulderScans", scanId, fileName);
        if (!File.Exists(path)) throw new FileNotFoundException("Scan export is unavailable.", path);
        var info = new FileInfo(path);
        var metadata = new ArtifactMetadata(request.ArtifactId, ProviderId,
            $"{scanId} {fileName}", "model", MimeType, $"{scanId}-{fileName}")
        {
            SizeBytes = info.Length,
            CreatedAtUtc = info.CreationTimeUtc,
            Description = "GLB exported from the matching Boulder Capture scan",
        };
        return Task.FromResult(new ArtifactResult(metadata, ArtifactPayload.FromFile(path)));
    }
}
#endif
