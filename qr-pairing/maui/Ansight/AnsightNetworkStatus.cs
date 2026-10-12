namespace Ansight.QrPairingHarness.Integration;

internal static class AnsightNetworkStatus
{
    public static string Describe()
    {
        try
        {
            var networkAccess = Microsoft.Maui.Networking.Connectivity.Current.NetworkAccess;
            var profiles = Microsoft.Maui.Networking.Connectivity.Current.ConnectionProfiles
                .Distinct()
                .ToArray();
            var profileNames = profiles
                .Select(profile => profile.ToString())
                .ToArray();
            var profileSummary = profileNames.Length == 0
                ? "none"
                : string.Join(", ", profileNames);

            if (networkAccess == NetworkAccess.None)
            {
                return $"Network status: no network access. Connections: {profileSummary}.";
            }

            if (!profiles.Contains(ConnectionProfile.WiFi))
            {
                return $"Network status: Wi-Fi does not appear to be connected. Access: {networkAccess}. Connections: {profileSummary}.";
            }

            return $"Network status: Wi-Fi connected. Access: {networkAccess}. Connections: {profileSummary}.";
        }
        catch (Exception ex)
        {
            return $"Network status could not be checked: {ex.Message}";
        }
    }

}
