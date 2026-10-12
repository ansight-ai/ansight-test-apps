using Ansight.Annotations;
using Ansight.Connectivity;
using Ansight.Network;
using Ansight.Maui;

namespace Ansight.QrPairingHarness.Integration;

internal static class AnsightConfiguration
{
    private const string CaptureEnabledPreference = "ansight.capture-enabled";

    public static bool IsVirtualDevice => DeviceInfo.Current.DeviceType == DeviceType.Virtual;

    public static Options CreateOptions(AnsightRemoteToolConsent consent)
    {
        var options = Options.CreateBuilder().WithAnsightMaui(Configure).Build();
        // Wrap after the aggregate SDK has registered every default suite.
        return Options.CreateBuilder(options)
            .WithTools(options.Tools.Select(tool => UserConfirmedAnsightTool.Create(tool, consent)))
            .Build();
    }

    private static void Configure(Options.OptionsBuilder options)
    {
        // The aggregate MAUI SDK supplies platform pairing, auto-probe and remote tools.
        options.WithBatteryLevel()
            .WithConnectivityCapture()
            .WithTouchCapture()
            .WithSessionJpegCapture(
                intervalMilliseconds: 750,
                quality: 65,
                maxWidth: 720,
                captureGpuBackedSurfaces: true,
                mode: SessionJpegCaptureMode.ScreenshotWithVisualTreeOnTouch,
                captureKeyboardPresence: false)
            .WithAnnotatedFeedback()
            .WithNetworkCapture(ConfigureNetwork)
            .WithSampleFrequencyMilliseconds(400)
            .WithRetentionPeriodSeconds(120)
            .WithCellularHostConnections(true);
#if ANSIGHT_UNATTENDED_PROVISIONING
        options.WithUnattendedProvisioning();
#endif
    }

    public static void ApplyStartupActivation()
    {
        // Virtual targets start active; physical targets remember the capture toggle.
        if (!IsVirtualDevice && !Preferences.Default.Get(CaptureEnabledPreference, true))
        {
            Runtime.Deactivate();
        }
    }

    public static void SetCaptureEnabled(bool enabled)
    {
        Preferences.Default.Set(CaptureEnabledPreference, enabled);
        if (enabled)
        {
            Runtime.Activate();
        }
        else
        {
            // The SDK also stops auto-probe and disconnects the host.
            Runtime.Deactivate();
        }
    }

    private static void ConfigureNetwork(NetworkRequestSanitizationOptionsBuilder network)
    {
        if (IsVirtualDevice)
        {
            network.WithRequestBodies().WithResponseBodies().WithBinaryBodies();
        }
        else
        {
            network.WithoutRequestBodies().WithoutResponseBodies().WithBinaryBodies(false);
        }
    }
}
