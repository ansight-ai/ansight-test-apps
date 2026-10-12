#nullable enable

using System.Text;
using Ansight;
using Ansight.Pairing;

namespace Ansight.QrPairingHarness.Integration;

internal static class AnsightConnectionFailureMessage
{
    public static string Build(HostConnectionResult result, Func<string> describeNetwork)
    {
        ArgumentNullException.ThrowIfNull(result);

        var builder = new StringBuilder();
        builder.Append(string.IsNullOrWhiteSpace(result.Message)
            ? "Unable to connect to the Ansight host."
            : result.Message.Trim());

        var reason = ResolveReason(result);
        if (!string.IsNullOrWhiteSpace(reason))
        {
            builder.AppendLine();
            builder.AppendLine();
            builder.Append(reason);
        }

        var networkSummary = ShouldIncludeNetworkSummary(result) ? describeNetwork() : null;
        if (!string.IsNullOrWhiteSpace(networkSummary))
        {
            builder.AppendLine();
            builder.AppendLine();
            builder.Append(networkSummary);
        }

        if (!string.IsNullOrWhiteSpace(result.ReasonCode))
        {
            builder.AppendLine();
            builder.AppendLine();
            builder.Append("Technical reason: ");
            builder.Append(result.ReasonCode);
        }

        return builder.ToString();
    }

    private static string? ResolveReason(HostConnectionResult result)
    {
        return result.ReasonCode switch
        {
            PairingFailureCodes.WifiRequired =>
                "Reason: A local network connection is required. Make sure this device can reach the computer running Ansight.",
            PairingFailureCodes.HostAddressRequired =>
                "Reason: The app could not resolve a usable Ansight endpoint. Open Pair Any App in Ansight and scan a fresh enrollment QR.",
            PairingFailureCodes.UdpBootstrapFailed =>
                "Reason: The app could not begin local enrollment. Check the device network connection and that Ansight is running.",
            PairingFailureCodes.UdpBootstrapTimeout =>
                "Reason: Ansight did not answer the local enrollment request. Check that Ansight is running, authenticated, and reachable on the local network.",
            PairingFailureCodes.WebSocketHandoffUnavailable =>
                "Reason: Ansight accepted enrollment but did not provide a live session endpoint. Restart Ansight and try again.",
            PairingFailureCodes.WebSocketEndpointUnreachable =>
                "Reason: Enrollment reached Ansight, but the app could not reach the live session endpoint. Check that Ansight is still running and that a firewall is not blocking it.",
            PairingFailureCodes.WebSocketHandshakeFailed =>
                "Reason: The live session handshake failed. Restart Ansight and try enrollment again.",
            PairingFailureCodes.EnrollmentRequired =>
                "Reason: This physical device is not enrolled. Open Pair Any App in Ansight and scan the generic enrollment QR.",
            PairingFailureCodes.EnrollmentUnavailable =>
                "Reason: Ansight could not issue an enrollment. Make sure Ansight is running and authenticated, then scan a fresh generic QR.",
            PairingFailureCodes.EnrollmentExpired or
                PairingFailureCodes.EnrollmentConsumed or
                PairingFailureCodes.AccessTokenInvalid or
                PairingFailureCodes.RegistrationExpired =>
                "Reason: The enrollment credentials were rejected. Open Pair Any App in Ansight and scan a fresh generic QR.",
            PairingFailureCodes.SignInRequired =>
                "Reason: Ansight must be signed in before it can enroll this app.",
            _ => ResolveReasonFromMessage(result.Message)
        };
    }

    private static string? ResolveReasonFromMessage(string? message)
    {
        if (string.IsNullOrWhiteSpace(message))
        {
            return null;
        }

        if (ContainsAny(message, "could not resolve", "NameResolution", "No such host", "nodename nor servname"))
        {
            return "Reason: The Ansight endpoint could not be resolved. Check that Ansight is running and reachable from this device.";
        }

        if (ContainsAny(message, "timed out", "timeout"))
        {
            return "Reason: The connection timed out before Ansight responded. Check that Ansight is running and reachable from this device.";
        }

        if (ContainsAny(message, "refused"))
        {
            return "Reason: Ansight refused the connection. Check that Ansight is running and authenticated.";
        }

        if (ContainsAny(message, "network is unreachable", "host is unreachable", "no route to host"))
        {
            return "Reason: Ansight is unreachable from the current network. Check the device connection, VPN, and firewall.";
        }

        return null;
    }

    private static bool ShouldIncludeNetworkSummary(HostConnectionResult result)
    {
        return result.ReasonCode is null or ""
            || result.ReasonCode is
                PairingFailureCodes.WifiRequired or
                PairingFailureCodes.HostAddressRequired or
                PairingFailureCodes.UdpBootstrapFailed or
                PairingFailureCodes.UdpBootstrapTimeout or
                PairingFailureCodes.WebSocketHandoffUnavailable or
                PairingFailureCodes.WebSocketEndpointUnreachable or
                PairingFailureCodes.WebSocketHandshakeFailed;
    }

    private static bool ContainsAny(string value, params string[] candidates)
    {
        return candidates.Any(candidate => value.Contains(candidate, StringComparison.OrdinalIgnoreCase));
    }

}
