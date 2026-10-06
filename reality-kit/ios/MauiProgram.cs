#if DEBUG
using Ansight;
using Ansight.Maui;
#endif

namespace BoulderCaptureSpike;

public static class MauiProgram
{
    public static MauiApp CreateMauiApp()
    {
        AppDomain.CurrentDomain.UnhandledException += (_, args) =>
            SpikeDiagnostics.Record($"Unhandled exception: {args.ExceptionObject}");
        TaskScheduler.UnobservedTaskException += (_, args) =>
            SpikeDiagnostics.Record(args.Exception, "Unobserved task exception");
        var builder = MauiApp.CreateBuilder();
        builder.UseMauiApp<App>();
#if DEBUG
        // GPU readback lets Ansight include RealityKit's live AR surface in screenshots.
        // Set -p:EnableAnsightGpuCapture=false if this diagnostic mode destabilizes a scan.
#if BOULDER_ANSIGHT_GPU_CAPTURE
        const bool captureGpuBackedSurfaces = true;
#else
        const bool captureGpuBackedSurfaces = false;
#endif
        builder.UseAnsight<App>(ansight =>
        {
            ansight.AddArtifactProvider(new ScanArtifactProvider());
            ansight.WithSessionJpegCapture(
                intervalMilliseconds: 2500,
                quality: 65,
                maxWidth: 720,
                captureGpuBackedSurfaces: captureGpuBackedSurfaces,
                mode: SessionJpegCaptureMode.ScreenshotWithVisualTreeOnTouch,
                captureKeyboardPresence: false);
        });
#endif
        return builder.Build();
    }
}
