using System.Reflection;
using Ansight.Maui;

namespace Ansight.KeyboardHarness;

public static class MauiProgram
{
    public static MauiApp CreateMauiApp()
    {
        var discoveryPort = typeof(MauiProgram).Assembly
            .GetCustomAttributes<AssemblyMetadataAttribute>()
            .Single(attribute => attribute.Key == "AnsightHostDiscoveryPort").Value!;
        return MauiApp.CreateBuilder()
            .UseMauiApp<App>()
            .UseAnsight<App>(options => options
                .WithReadWriteToolAccess()
                .WithHostConnectionDiscoveryPort(int.Parse(discoveryPort, System.Globalization.CultureInfo.InvariantCulture))
                .WithSessionJpegCapture(
                    intervalMilliseconds: 1000,
                    quality: 65,
                    maxWidth: 720,
                    captureGpuBackedSurfaces: true,
                    mode: SessionJpegCaptureMode.ScreenshotWithVisualTreeOnTouch,
                    captureKeyboardPresence: true)
                .WithTouchCapture())
            .Build();
    }
}
