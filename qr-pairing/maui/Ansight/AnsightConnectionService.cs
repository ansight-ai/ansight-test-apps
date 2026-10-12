namespace Ansight.QrPairingHarness.Integration;

public sealed partial class AnsightConnectionService : IDisposable
{
    private const string InactiveMessage = "Enable capture before connecting to an Ansight host.";
    private readonly IHostConnection hostConnection;
    private int connectedState;

    public AnsightConnectionService(IHostConnection hostConnection)
    {
        this.hostConnection = hostConnection;
        hostConnection.StatusChanged += OnStatusChanged;
        UpdateConnectionState();
    }

    public HostConnectionStatus Status => hostConnection.Status;
    public string StatusSummary => Status.SummaryKind is
        HostConnectionSummaryKind.RuntimeInactive or HostConnectionSummaryKind.RuntimeUnavailable
        ? InactiveMessage : Status.SummaryMessage;

    public event EventHandler<HostConnectionChangedEventArgs>? StatusChanged;

    public Task<HostConnectionResult> ScanAsync() => ConnectAsync(
        HostConnectionRequest.QrCode("Scan Ansight enrollment QR"));

    public Task<HostConnectionResult> ConnectAsync(HostConnectionRequest? request = null)
    {
        if (!Runtime.IsActive)
        {
            return Task.FromResult(HostConnectionResult.FromFailure(InactiveMessage));
        }

        // Saved hosts, Wi-Fi profiles, trust, retries and request serialization belong to the SDK.
        return hostConnection.ConnectAsync(request);
    }

    public HostConnectionResult ForgetEnrollment() => hostConnection.ClearSavedConfigs();

    public Task<HostConnectionResult> DisconnectAsync() => hostConnection.DisconnectAsync();

    public void Dispose() => hostConnection.StatusChanged -= OnStatusChanged;

    private void OnStatusChanged(object? sender, HostConnectionChangedEventArgs args)
    {
        UpdateConnectionState();
        StatusChanged?.Invoke(this, args);
    }

    private void UpdateConnectionState()
    {
        var connected = hostConnection.IsConnected;
        var wasConnected = Interlocked.Exchange(ref connectedState, connected ? 1 : 0) == 1;
        if (connected && !wasConnected)
        {
            NotifyConnected(Status.SummaryMessage);
        }
    }

    partial void NotifyConnected(string summary);
}
