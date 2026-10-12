using System.Diagnostics;

namespace Ansight.QrPairingHarness.Integration;

internal static class AnsightRemoteTools
{
    private const string AllowedPreference = "ansight.remote-tools-allowed";

    public static AnsightRemoteToolConsent CreateConsent() => new(
        requiresConsent: !AnsightConfiguration.IsVirtualDevice,
        readAllowed: () => Preferences.Default.Get(AllowedPreference, false),
        writeAllowed: allowed => Preferences.Default.Set(AllowedPreference, allowed),
        confirm: ConfirmAsync);

    private static async Task<bool> ConfirmAsync(string? toolName)
    {
        try
        {
            return await MainThread.InvokeOnMainThreadAsync(async () =>
            {
                var page = Application.Current?.Windows.FirstOrDefault()?.Page;
                if (page is null) return false;
                var message = "Allow paired Ansight hosts to use remote tools? These tools can inspect the app UI, screenshots, local files, databases, preferences and secure storage, and can modify or delete app data when the connection permits it.\n\nOnly allow hosts you trust. Your choice is remembered; turn remote tools off in this screen to revoke it.";
                if (!string.IsNullOrWhiteSpace(toolName))
                {
                    message += $"\n\nRequested tool: {toolName}";
                }
                return await page.DisplayAlertAsync(
                    "Allow Ansight remote tools?", message, "Allow remote tools", "Cancel");
            });
        }
        catch (Exception exception)
        {
            Debug.WriteLine($"Ansight remote tools consent failed: {exception.Message}");
            return false;
        }
    }
}
