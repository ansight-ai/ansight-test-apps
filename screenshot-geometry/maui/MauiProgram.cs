using System.Reflection;
using Ansight.Maui;

namespace Ansight.ScreenshotGeometryHarness;

public static class MauiProgram
{
    public static MauiApp CreateMauiApp()
    {
        string Setting(string key) => typeof(MauiProgram).Assembly.GetCustomAttributes<AssemblyMetadataAttribute>().Single(item => item.Key == key).Value!;
        return MauiApp.CreateBuilder().UseMauiApp<App>()
            .UseAnsight<App>(options =>
            {
#if DEBUG
                options.WithReadWriteToolAccess().AddTool(new ClockBoundsTool());
#else
                options.WithToolsDisabled();
#endif
                options.WithHostConnectionDiscoveryPort(int.Parse(Setting("AnsightHostDiscoveryPort"), System.Globalization.CultureInfo.InvariantCulture))
                    .WithSessionJpegCapture(intervalMilliseconds: 1000, quality: 90, maxWidth: 720,
                        mode: SessionJpegCaptureMode.ScreenshotAndVisualTree,
                        includeSystemUiMetadata: bool.Parse(Setting("IncludeSystemUiMetadata")));
            }).Build();
    }
}
