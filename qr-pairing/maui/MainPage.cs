#if DEBUG
using Ansight.QrPairingHarness.Integration;
using Ansight.Telemetry.Events;
#endif

namespace Ansight.QrPairingHarness;

public sealed class MainPage : ContentPage
{
#if DEBUG
    private readonly AnsightConnectionService connection;
    private readonly AnsightRemoteToolConsent remoteToolConsent;
    private readonly Switch remoteTools = new() { AutomationId = "pairing.remote-tools" };
    private readonly Label remoteToolsStatus = new() { AutomationId = "pairing.remote-tools-status", FontSize = 12 };
    private readonly Label status = new() { AutomationId = "pairing.status", FontSize = 16 };
    private readonly Label saved = new() { AutomationId = "pairing.saved", FontSize = 14 };
    private readonly Label lastResult = new() { AutomationId = "pairing.result", FontSize = 14 };
    private readonly Switch capture = new() { AutomationId = "pairing.capture" };
    private readonly Button scan;
    private readonly Button reconnect;
    private readonly Button disconnect;
    private readonly Button forget;
    private bool updating;
    private bool busy;

    public MainPage(AnsightConnectionService connection, AnsightRemoteToolConsent remoteToolConsent)
    {
        this.connection = connection;
        this.remoteToolConsent = remoteToolConsent;
        Title = "Ansight QR pairing";
        BackgroundColor = Color.FromArgb("F4F7F8");
        scan = ActionButton("Scan Ansight enrollment QR", "pairing.scan", connection.ScanAsync);
        reconnect = ActionButton("Connect using saved enrollment", "pairing.reconnect", () => connection.ConnectAsync());
        disconnect = ActionButton("Disconnect", "pairing.disconnect", connection.DisconnectAsync);
        forget = ActionButton("Forget saved enrollment", "pairing.forget", () => Task.FromResult(connection.ForgetEnrollment()));
        var emitEvent = new Button { Text = "Record a test event", AutomationId = "pairing.event" };
        emitEvent.Clicked += (_, _) =>
        {
            Runtime.Event("QR pairing sample: test event", AppEventType.Event, "Synthetic verification event");
            lastResult.Text = Runtime.IsActive ? "Test event recorded." : "Capture is disabled.";
        };
        capture.Toggled += (_, args) =>
        {
            if (updating) return;
            AnsightConfiguration.SetCaptureEnabled(args.Value);
            Refresh();
        };
        remoteTools.Toggled += async (_, args) =>
        {
            if (updating || busy) return;
            busy = true;
            Refresh();
            try
            {
                if (args.Value)
                {
                    await remoteToolConsent.EnsureAllowedAsync();
                }
                else
                {
                    remoteToolConsent.Revoke();
                }
            }
            finally
            {
                busy = false;
                Refresh();
            }
        };
        Content = new ScrollView
        {
            Content = new VerticalStackLayout
            {
                Padding = 24, Spacing = 14,
                Children =
                {
                    new Label { Text = "Pair this app with Ansight", FontSize = 26, FontAttributes = FontAttributes.Bold },
                    new Label { Text = "Simulators and emulators connect automatically. On a phone, open Pair Any App in Ansight and scan its enrollment QR.", FontSize = 15 },
                    new HorizontalStackLayout { Spacing = 16, Children = { new Label { Text = "Capture enabled", VerticalOptions = LayoutOptions.Center }, capture } },
                    status, saved, scan, reconnect, disconnect, forget,
                    new HorizontalStackLayout { Spacing = 16, Children = { new Label { Text = "Remote tools", VerticalOptions = LayoutOptions.Center }, remoteTools } },
                    remoteToolsStatus, emitEvent, lastResult,
                    new Label { Text = "The SDK remembers enrollment and network profiles. This app stores your capture and remote-tools consent preferences. Remote tools are included only in Debug builds.", FontSize = 12 }
                }
            }
        };
        Refresh();
    }

    protected override void OnAppearing()
    {
        base.OnAppearing();
        connection.StatusChanged += OnStatusChanged;
        remoteToolConsent.Changed += OnRemoteToolConsentChanged;
        Refresh();
    }

    protected override void OnDisappearing()
    {
        connection.StatusChanged -= OnStatusChanged;
        remoteToolConsent.Changed -= OnRemoteToolConsentChanged;
        base.OnDisappearing();
    }

    private void OnStatusChanged(object? sender, HostConnectionChangedEventArgs args)
        => MainThread.BeginInvokeOnMainThread(Refresh);

    private void OnRemoteToolConsentChanged(object? sender, EventArgs args)
        => MainThread.BeginInvokeOnMainThread(Refresh);

    private void Refresh()
    {
        updating = true;
        capture.IsToggled = Runtime.IsActive;
        remoteTools.IsToggled = remoteToolConsent.IsAllowed;
        updating = false;
        var current = connection.Status;
        status.Text = connection.StatusSummary;
        saved.Text = current.HasSavedConfig ? "Saved enrollment: available" : "Saved enrollment: none";
        capture.IsEnabled = !busy;
        remoteTools.IsEnabled = !busy && remoteToolConsent.RequiresConsent;
        remoteToolsStatus.Text = !remoteToolConsent.RequiresConsent
            ? "Remote tools are automatically allowed on simulators and emulators."
            : remoteToolConsent.IsAllowed
                ? "Remote tools are allowed. Turn off to revoke consent. The connection's permissions still apply."
                : "Remote tools need your consent. Enable here or approve the first remote-tool request.";
        scan.IsEnabled = !busy && Runtime.IsActive && !current.IsConnected;
        reconnect.IsEnabled = !busy && Runtime.IsActive && !current.IsConnected;
        disconnect.IsEnabled = !busy && current.IsConnected;
        forget.IsEnabled = !busy && !current.IsConnected;
    }

    private Button ActionButton(string text, string automationId, Func<Task<HostConnectionResult>> action)
    {
        var button = new Button { Text = text, AutomationId = automationId };
        button.Clicked += async (_, _) =>
        {
            if (busy) return;
            busy = true;
            Refresh();
            try
            {
                var result = await action();
                lastResult.Text = result.Message;
                if (!result.Success)
                {
                    await DisplayAlertAsync("Ansight connection failed", AnsightConnectionFailureMessage.Build(result, AnsightNetworkStatus.Describe), "OK");
                }
            }
            catch (OperationCanceledException)
            {
                lastResult.Text = "Ansight connection cancelled.";
            }
            catch (Exception exception)
            {
                lastResult.Text = exception.Message;
                await DisplayAlertAsync("Ansight connection failed", exception.Message, "OK");
            }
            finally
            {
                busy = false;
                Refresh();
            }
        };
        return button;
    }
#else
    public MainPage()
    {
        Title = "Ansight QR pairing";
        Content = new Label
        {
            Text = "Run the Debug build to try Ansight QR pairing. This Release build contains no Ansight SDK or remote tools.",
            Margin = 24
        };
    }
#endif
}
