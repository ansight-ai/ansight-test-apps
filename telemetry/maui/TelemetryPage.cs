using Ansight.Telemetry.Events;

namespace Ansight.TelemetryHarness;

public sealed class TelemetryPage : ContentPage
{
    private readonly Label connection = new() { AutomationId = "telemetry.connection", Text = "Waiting for host", TextColor = Colors.Black };
    private readonly Label status = new() { AutomationId = "telemetry.status", Text = "Ready", TextColor = Colors.Black };
    private readonly Button run = new() { AutomationId = "telemetry.run", Text = "Record telemetry", IsEnabled = false, Padding = 12, BorderWidth = 2, BorderColor = Colors.CornflowerBlue };
    private bool busy;

    public TelemetryPage()
    {
        Title = "Telemetry harness";
        AutomationId = "telemetry.root";
        BackgroundColor = Colors.White;
        Content = new VerticalStackLayout { AutomationId = "telemetry.layout", Padding = new Thickness(20, 24, 20, 12), Spacing = 14,
            Children = {
                new Label { AutomationId = "telemetry.title", Text = "Telemetry harness", FontSize = 26, FontAttributes = FontAttributes.Bold,
                    TextColor = Colors.DarkSlateBlue, CharacterSpacing = 0.5, HorizontalTextAlignment = TextAlignment.Center },
                new Label { Text = "Record fractions and nested, overlapping, async and interrupted spans.", TextColor = Colors.Black },
                connection, run, status,
                new Border { AutomationId = "telemetry.border", Stroke = Colors.CornflowerBlue, StrokeThickness = 3, Padding = 10,
                    Content = new Label { Text = "MAUI appearance properties", TextColor = Colors.Black, FontSize = 18 } }
            } };
        run.Clicked += async (_, _) => await RecordAsync();
    }

    protected override void OnAppearing() { base.OnAppearing(); Runtime.HostConnection.StatusChanged += ConnectionChanged; RefreshConnection(); }
    protected override void OnDisappearing() { Runtime.HostConnection.StatusChanged -= ConnectionChanged; base.OnDisappearing(); }
    private void ConnectionChanged(object? sender, HostConnectionChangedEventArgs args) => MainThread.BeginInvokeOnMainThread(RefreshConnection);
    private void RefreshConnection() { connection.Text = Runtime.HostConnection.IsConnected ? "Connected" : "Waiting for host"; run.IsEnabled = !busy && Runtime.HostConnection.IsConnected; }

    private async Task RecordAsync()
    {
        busy = true; RefreshConnection(); status.Text = "Recording";
        try
        {
            Runtime.Metric(16.67, 64); Runtime.Metric(0.125, 64); Runtime.Metric(-0.25, 64); Runtime.Metric(7L, 66);
            using (var outer = Runtime.BeginSpan("Frame", 64))
            {
                using (Runtime.BeginSpan("Build", 64, outer.Id)) { await Task.Delay(80); }
                using (Runtime.BeginSpan("Raster", 64, outer.Id)) { await Task.Delay(40); }
                using var first = Runtime.BeginSpan("Overlap A", 64, outer.Id);
                using var second = Runtime.BeginSpan("Overlap B", 64, outer.Id);
                await Task.Delay(50);
            }
            await Runtime.MeasureAsync("Async work", () => Task.Run(async () => { await Task.Delay(35); return 42; }), 65);
            try { await Runtime.MeasureAsync<int>("Failed work", () => Task.FromException<int>(new InvalidOperationException("Expected harness failure")), 65); }
            catch (InvalidOperationException) { }
            try { await Runtime.MeasureAsync<int>("Cancelled work", () => Task.FromCanceled<int>(new CancellationToken(true)), 65); }
            catch (OperationCanceledException) { }
            _ = Runtime.BeginSpan("Interrupted work", 65);
            Runtime.Event("Telemetry recorded", AppEventType.Info, 66, "fractional metrics and spans");
            status.Text = "Recorded";
        }
        catch (Exception error) { status.Text = "Failed: " + error.Message; }
        finally { busy = false; RefreshConnection(); }
    }
}
