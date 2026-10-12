using Ansight;
using Ansight.Pairing;
using Ansight.QrPairingHarness.Integration;

var networkReads = 0;
string Network()
{
    networkReads++;
    return "Network status: Wi-Fi connected.";
}

var expired = AnsightConnectionFailureMessage.Build(
    HostConnectionResult.FromFailure("Expired QR", reasonCode: PairingFailureCodes.EnrollmentExpired), Network);
Require(expired.Contains("fresh generic QR") && expired.Contains(PairingFailureCodes.EnrollmentExpired), "Expired QR must explain recovery and retain its technical reason.");
Require(networkReads == 0, "Rejected credentials must not be presented as a Wi-Fi problem.");

var timeout = AnsightConnectionFailureMessage.Build(
    HostConnectionResult.FromFailure("Enrollment timed out", reasonCode: PairingFailureCodes.UdpBootstrapTimeout), Network);
Require(networkReads == 1 && timeout.Contains("Wi-Fi connected") && timeout.Contains("did not answer"), "Network failures must include current network evidence and recovery advice.");

var unknown = AnsightConnectionFailureMessage.Build(
    HostConnectionResult.FromFailure("New SDK failure", reasonCode: "future_reason"), Network);
Require(unknown.Contains("New SDK failure") && unknown.Contains("future_reason") && networkReads == 1, "New SDK reason codes must survive without invented network advice.");

var legacy = AnsightConnectionFailureMessage.Build(HostConnectionResult.FromFailure("NameResolution failed"), Network);
Require(legacy.Contains("could not be resolved") && networkReads == 2, "Legacy SDK failures without reason codes must still be actionable.");

var empty = AnsightConnectionFailureMessage.Build(HostConnectionResult.FromFailure(" "), Network);
Require(empty.StartsWith("Unable to connect to the Ansight host."), "Empty SDK messages must have a useful fallback.");
await RemoteToolConsentChecks.RunAsync();
Console.WriteLine("Passed: expired QR, network failure, unknown reason, legacy failure and empty-message checks.");

static void Require(bool condition, string message)
{
    if (!condition) throw new InvalidOperationException(message);
}
