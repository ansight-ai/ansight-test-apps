#if DEBUG
using System.Globalization;
using System.Text.Json.Nodes;
using Ansight.Tools;
using Evergine.Framework;

namespace EvergineToolsDemo.Tools;

internal static class ToolHelpers
{
    internal static async Task<ToolResult> RunAsync(Func<DemoScene, ToolResult> action)
    {
        try
        {
            var engine = DemoEvergineApplication.ActiveInstance;
            return engine is null
                ? ToolResult.Failure("The Evergine app has not started.", "evergine_scene_unavailable")
                : await engine.InvokeAsync(action);
        }
        catch (Exception exception)
        {
            return ToolResult.Failure(exception.Message, "evergine_tool_failed");
        }
    }

    internal static JsonObject CameraPosition(DemoScene scene)
    {
        var position = scene.CameraPosition;
        return new JsonObject { ["x"] = position.X, ["y"] = position.Y, ["z"] = position.Z };
    }

    internal static JsonObject Entity(Entity entity) => new()
    {
        ["id"] = entity.Id.ToString(),
        ["name"] = entity.Name,
        ["path"] = entity.EntityPath,
        ["tag"] = entity.Tag
    };
}

internal sealed class SceneSummaryTool : ITool
{
    public string Category => "demo.evergine";
    public ToolPolicy Policy => ToolPolicy.Read;
    public string Id => "demo.evergine.scene_summary";
    public string Name => "Evergine Scene Summary";
    public string Description => "Summarizes the live demo scene, entity count, and camera position.";
    public string Keywords => "evergine scene entities camera summary";
    public ToolSchema ArgumentsSchema => ToolSchema.Object("No arguments.",
        new Dictionary<string, ToolSchema>());
    public ToolSchema ResultSchema => ToolSchema.Object("Live scene summary.", additionalProperties: true);

    public Task<ToolResult> Execute(IReadOnlyDictionary<string, string> arguments)
        => ToolHelpers.RunAsync(scene => ToolResult.Success(new JsonObject
        {
            ["sceneId"] = scene.Id.ToString(),
            ["sceneType"] = scene.GetType().FullName,
            ["entityCount"] = scene.Managers.EntityManager.AllEntities.Count(),
            ["glbLoaded"] = scene.HasModel,
            ["cameraPosition"] = ToolHelpers.CameraPosition(scene)
        }));
}

internal sealed class FindEntitiesTool : ITool
{
    public string Category => "demo.evergine";
    public ToolPolicy Policy => ToolPolicy.Read;
    public string Id => "demo.evergine.find_entities";
    public string Name => "Find Evergine Entities";
    public string Description => "Finds demo scene entities by exact name or tag, with a bounded result.";
    public string Keywords => "evergine entity manager find tag name path";
    public ToolSchema ArgumentsSchema => ToolSchema.Object(
        "Optional exact filters for entities in the live demo scene.",
        new Dictionary<string, ToolSchema>
        {
            ["name"] = ToolSchema.String("Exact entity name.", nullable: true),
            ["tag"] = ToolSchema.String("Exact entity tag.", nullable: true),
            ["maxResults"] = ToolSchema.Integer("Maximum entities to return, from 1 to 50.")
        });
    public ToolSchema ResultSchema => ToolSchema.Object("Matching entities.", additionalProperties: true);

    public Task<ToolResult> Execute(IReadOnlyDictionary<string, string> arguments)
    {
        var name = arguments.GetValueOrDefault("name");
        var tag = arguments.GetValueOrDefault("tag");
        var max = int.TryParse(arguments.GetValueOrDefault("maxResults"),
            NumberStyles.Integer, CultureInfo.InvariantCulture, out var requested)
            ? Math.Clamp(requested, 1, 50) : 20;

        return ToolHelpers.RunAsync(scene =>
        {
            var matches = scene.Managers.EntityManager.AllEntities
                .Where(entity => (string.IsNullOrWhiteSpace(name) || entity.Name == name)
                                 && (string.IsNullOrWhiteSpace(tag) || entity.Tag == tag))
                .ToList();
            var result = new JsonArray();
            foreach (var entity in matches.Take(max))
            {
                result.Add(ToolHelpers.Entity(entity));
            }

            return ToolResult.Success(new JsonObject
            {
                ["matchCount"] = matches.Count,
                ["returnedCount"] = result.Count,
                ["truncated"] = matches.Count > result.Count,
                ["entities"] = result
            });
        });
    }
}

internal sealed class ResetCameraTool : ITool
{
    public string Category => "demo.evergine";
    public ToolPolicy Policy => ToolPolicy.Write;
    public string Id => "demo.evergine.reset_camera";
    public string Name => "Reset Evergine Camera";
    public string Description => "Restores the demo camera to its initial position.";
    public string Keywords => "evergine camera reset position";
    public ToolSchema ArgumentsSchema => ToolSchema.Object("No arguments.",
        new Dictionary<string, ToolSchema>());
    public ToolSchema ResultSchema => ToolSchema.Object("Restored camera position.", additionalProperties: true);

    public Task<ToolResult> Execute(IReadOnlyDictionary<string, string> arguments)
        => ToolHelpers.RunAsync(scene =>
        {
            scene.ResetCamera();
            return ToolResult.Success(new JsonObject
            {
                ["cameraPosition"] = ToolHelpers.CameraPosition(scene)
            });
        });
}
#endif
