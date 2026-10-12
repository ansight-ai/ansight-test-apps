#if DEBUG
using Ansight.Maui;
using Ansight.QrPairingHarness.Integration;
#endif

namespace Ansight.QrPairingHarness;

public static class MauiProgram
{
    public static MauiApp CreateMauiApp()
    {
        var builder = MauiApp.CreateBuilder().UseMauiApp<App>();
#if DEBUG
        var remoteToolConsent = AnsightRemoteTools.CreateConsent();
        builder.UseAnsight(AnsightConfiguration.CreateOptions(remoteToolConsent));
        builder.Services.AddSingleton(remoteToolConsent);
        AnsightConfiguration.ApplyStartupActivation();
        builder.Services.AddSingleton<AnsightConnectionService>();
#endif
        builder.Services.AddSingleton<MainPage>();
        return builder.Build();
    }
}
