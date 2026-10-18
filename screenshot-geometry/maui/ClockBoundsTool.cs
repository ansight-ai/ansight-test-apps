#if DEBUG
using System.Text.Json.Nodes;
using Ansight.Tools;

namespace Ansight.ScreenshotGeometryHarness;

// Read-only fixture geometry, in the same app-window coordinates as SDK screenshots.
internal sealed class ClockBoundsTool : ITool
{
    public string Id => "harness.clock_bounds";
    public string Name => "Clock bounds";
    public string Description => "Read the app clock rectangle in normalized app-window coordinates.";
    public string Category => "harness";
    public string Keywords => "clock screenshot mask";
    public ToolPolicy Policy => ToolPolicy.Read;
    public ToolSchema ArgumentsSchema => ToolSchema.Object();
    public ToolSchema ResultSchema => ToolSchema.Object(properties: new Dictionary<string, ToolSchema> {
        ["x"] = ToolSchema.Number(), ["y"] = ToolSchema.Number(),
        ["width"] = ToolSchema.Number(), ["height"] = ToolSchema.Number()
    }, required: ["x", "y", "width", "height"]);

    public Task<ToolResult> Execute(IReadOnlyDictionary<string, string> arguments) => MainThread.InvokeOnMainThreadAsync(() =>
    {
        var clock = GeometryPage.Current?.Clock;
        double x, y, width, height, windowWidth, windowHeight;
#if ANDROID
        if (clock?.Handler?.PlatformView is not Android.Views.View view || Platform.CurrentActivity?.Window?.DecorView is not { } root)
            return ToolResult.Failure("Clock is not laid out.", "fixture_not_ready");
        var origin = new int[2]; var rootOrigin = new int[2];
        view.GetLocationInWindow(origin); root.GetLocationInWindow(rootOrigin);
        x = origin[0] - rootOrigin[0]; y = origin[1] - rootOrigin[1]; width = view.Width; height = view.Height;
        windowWidth = root.Width; windowHeight = root.Height;
#elif IOS
        if (clock?.Handler?.PlatformView is not UIKit.UIView view || view.Window is not { } window)
            return ToolResult.Failure("Clock is not laid out.", "fixture_not_ready");
        var bounds = view.ConvertRectToView(view.Bounds, window);
        x = bounds.X; y = bounds.Y; width = bounds.Width; height = bounds.Height;
        windowWidth = window.Bounds.Width; windowHeight = window.Bounds.Height;
#else
        return ToolResult.Failure("Unsupported fixture platform.", "unsupported_platform");
#endif
        if (windowWidth <= 0 || windowHeight <= 0 || width <= 0 || height <= 0)
            return ToolResult.Failure("Clock is not laid out.", "fixture_not_ready");
        // Pad for image resampling at the edge, clipped to the actual screenshot bounds.
        var left = Math.Max(0, x - 2); var top = Math.Max(0, y - 2);
        return ToolResult.Success(new JsonObject { ["x"] = left / windowWidth, ["y"] = top / windowHeight,
            ["width"] = (Math.Min(windowWidth, x + width + 2) - left) / windowWidth,
            ["height"] = (Math.Min(windowHeight, y + height + 2) - top) / windowHeight });
    });
}
#endif
