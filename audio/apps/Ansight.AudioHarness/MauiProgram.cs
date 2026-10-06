using Ansight.AudioHarness.Services;
using Ansight.AudioHarness.ViewModels;
using Microsoft.Extensions.Logging;
#if DEBUG
using Ansight.Maui;
#endif

namespace Ansight.AudioHarness;

public static class MauiProgram
{
    public static MauiApp CreateMauiApp()
    {
        var builder = MauiApp.CreateBuilder();
        builder.UseMauiApp<App>()
            .ConfigureFonts(fonts =>
            {
                fonts.AddFont("OpenSans-Regular.ttf", "OpenSansRegular");
                fonts.AddFont("OpenSans-Semibold.ttf", "OpenSansSemibold");
            });
        builder.Services.AddSingleton<PlatformSpeechCaptureService>();
        builder.Services.AddSingleton<IAudioTranscriber, WhisperAudioTranscriber>();
        builder.Services.AddSingleton<ISpeechCaptureService, TranscribingSpeechCaptureService>();
        var runs = new AudioRunStore();
        builder.Services.AddSingleton(runs);
        builder.Services.AddSingleton<HarnessViewModel>();
        builder.Services.AddSingleton<MainPage>();
#if DEBUG
        builder.UseAnsight<App>(options =>
        {
            options.AddArtifactProvider(new AudioRunArtifactProvider(runs));
            options.WithHostAutoProbe(new HostAutoProbeOptions
            {
                ClientName = "Audio Harness",
                InitialDelay = TimeSpan.FromSeconds(1),
                ProbeInterval = TimeSpan.FromSeconds(5)
            });
        });
        builder.Logging.AddDebug();
#endif
        return builder.Build();
    }
}
