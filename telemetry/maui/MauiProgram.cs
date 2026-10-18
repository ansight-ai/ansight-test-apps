using System.Reflection;
using Ansight.Maui;
using Ansight.Telemetry.Channels;

namespace Ansight.TelemetryHarness;

public static class MauiProgram
{
    public static MauiApp CreateMauiApp()
    {
        var discoveryPort = typeof(MauiProgram).Assembly.GetCustomAttributes<AssemblyMetadataAttribute>()
            .Single(attribute => attribute.Key == "AnsightHostDiscoveryPort").Value!;
        return MauiApp.CreateBuilder().UseMauiApp<App>()
            .UseAnsight<App>(options => options.WithReadWriteToolAccess()
                .WithHostConnectionDiscoveryPort(int.Parse(discoveryPort, System.Globalization.CultureInfo.InvariantCulture))
                .WithAdditionalChannels(new[] {
                    new Channel(64, "Render", System.Drawing.Color.CornflowerBlue, unit: "ms", group: "Rendering", kind: "duration"),
                    new Channel(65, "Work", System.Drawing.Color.MediumPurple, unit: "ms", group: "Background", kind: "duration"),
                    new Channel(66, "Items", System.Drawing.Color.SeaGreen, unit: "count", group: "Work")
                })
                .WithSessionJpegCapture(intervalMilliseconds: 1000, quality: 65, maxWidth: 720,
                    mode: SessionJpegCaptureMode.ScreenshotWithVisualTreeOnTouch)
                .WithTouchCapture())
            .Build();
    }
}
