#if DEBUG
using Ansight.Maui;
using EvergineToolsDemo.Tools;
#endif

namespace EvergineToolsDemo;

public static class MauiProgram
{
    public static MauiApp CreateMauiApp()
    {
        var builder = MauiApp.CreateBuilder();
        builder.UseMauiApp<App>();
        builder.ConfigureMauiHandlers(handlers =>
            handlers.AddHandler<DemoSurfaceView, DemoSurfaceViewHandler>());

#if DEBUG
        builder.UseAnsight<App>(options =>
        {
            options.AddTools([
                new SceneSummaryTool(),
                new FindEntitiesTool(),
                new ResetCameraTool()
            ]);
            options.WithReadWriteToolAccess();
            options.WithSessionJpegCapture(
                intervalMilliseconds: 3000,
                quality: 65,
                maxWidth: 720,
                captureGpuBackedSurfaces: true);
        });
#endif
        return builder.Build();
    }
}
