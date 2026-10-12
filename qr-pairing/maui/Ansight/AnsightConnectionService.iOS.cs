#if IOS
using System.Diagnostics;
using UserNotifications;

namespace Ansight.QrPairingHarness.Integration;

public sealed partial class AnsightConnectionService
{
    partial void NotifyConnected(string summary)
    {
        if (AnsightConfiguration.IsVirtualDevice)
        {
            return;
        }

        MainThread.BeginInvokeOnMainThread(async () =>
        {
            try
            {
                var center = UNUserNotificationCenter.Current;
                var settings = await center.GetNotificationSettingsAsync();
                var allowed = settings.AuthorizationStatus is
                    UNAuthorizationStatus.Authorized or UNAuthorizationStatus.Provisional;
                if (settings.AuthorizationStatus == UNAuthorizationStatus.NotDetermined)
                {
                    var authorization = await center.RequestAuthorizationAsync(
                        UNAuthorizationOptions.Alert | UNAuthorizationOptions.Sound);
                    allowed = authorization.Item1;
                }

                if (allowed)
                {
                    var content = new UNMutableNotificationContent
                    {
                        Title = "Ansight",
                        Body = string.IsNullOrWhiteSpace(summary) ? "Ansight host connected" : summary
                    };
                    await center.AddNotificationRequestAsync(UNNotificationRequest.FromIdentifier(
                        $"ansight-host-connected-{Guid.NewGuid():N}", content, null));
                }
            }
            catch (Exception exception)
            {
                Debug.WriteLine($"Ansight connection notification failed: {exception.Message}");
            }
        });
    }
}
#endif
