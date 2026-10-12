namespace Ansight.QrPairingHarness.Integration;

// App consent is separate from the SDK's authenticated host grant and tool policies.
public sealed class AnsightRemoteToolConsent(
    bool requiresConsent,
    Func<bool> readAllowed,
    Action<bool> writeAllowed,
    Func<string?, Task<bool>> confirm)
{
    private readonly SemaphoreSlim promptGate = new(1, 1);
    private readonly Lock stateGate = new();
    private int revision;

    public bool RequiresConsent => requiresConsent;
    public bool IsAllowed
    {
        get { lock (stateGate) return !requiresConsent || readAllowed(); }
    }
    public event EventHandler? Changed;

    public void Revoke()
    {
        lock (stateGate)
        {
            revision++;
            writeAllowed(false);
        }
        Changed?.Invoke(this, EventArgs.Empty);
    }

    public async Task<bool> EnsureAllowedAsync(
        string? toolName = null, CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();
        if (IsAllowed) return true;

        await promptGate.WaitAsync(cancellationToken);
        try
        {
            if (IsAllowed) return true;
            int promptRevision;
            lock (stateGate) promptRevision = revision;
            var allowed = await confirm(toolName);
            cancellationToken.ThrowIfCancellationRequested();
            lock (stateGate)
            {
                if (!allowed || promptRevision != revision) return false;
                writeAllowed(true);
            }
            Changed?.Invoke(this, EventArgs.Empty);
            return true;
        }
        finally
        {
            promptGate.Release();
        }
    }
}
