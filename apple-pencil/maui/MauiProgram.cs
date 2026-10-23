using Ansight;
using Ansight.Maui;
using Ansight.Pencil;
using Ansight.Tools;
using Foundation;
using Microsoft.Maui.Handlers;

namespace Pencil.Maui;

public static class MauiProgram
{
    public static bool PenOptIn => NSProcessInfo.ProcessInfo.Arguments.Contains("--pen-simulation");

    public static MauiApp CreateMauiApp()
    {
        var builder = MauiApp.CreateBuilder();
        builder.UseMauiApp<PencilApp>()
            .ConfigureMauiHandlers(handlers => handlers.AddHandler<PencilView, PencilViewHandler>())
            .UseAnsight<PencilApp>(options =>
            {
                options.WithHostConnectionDiscoveryPort(49332);
                options.WithHostAutoProbe(new HostAutoProbeOptions
                {
                    InitialDelay = TimeSpan.FromSeconds(1),
                    ProbeInterval = TimeSpan.FromSeconds(3),
                    ClientName = "Pencil precompiled MAUI verification"
                });
                options.WithSessionJpegCapture(new SessionJpegCaptureOptions
                {
                    IntervalMilliseconds = 100, Quality = 85, MaxWidth = 1200
                });
                options.WithTouchCapture();
                // Verify Pencil opt-in grants no unrelated write tools.
                options.WithToolGuard(ToolGuard.ReadOnly);
                // Default launch deliberately tests the existing-app behavior: no opt-in.
                if (PenOptIn) options.WithSimulatorPenInput();
            });
        File.WriteAllText(Path.Combine(FileSystem.AppDataDirectory, "pen-capability.json"),
            System.Text.Json.JsonSerializer.Serialize(new
            {
                optedIn = PenOptIn,
                nativeCapability = PenOptIn && PencilSimulation.IsSupported,
                bridgeVersion = "Ansight.Pencil"
            }));
        return builder.Build();
    }
}

public sealed class PencilApp : Application
{
    protected override Window CreateWindow(IActivationState? activationState)
        => new(new ContentPage { Content = new PencilView() });
}

public sealed class PencilView : View { }

public sealed class PencilViewHandler : ViewHandler<PencilView, PencilCanvas>
{
    public PencilViewHandler() : base(ViewMapper) { }
    protected override PencilCanvas CreatePlatformView() => new();
}
