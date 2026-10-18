using Ansight.Artifacts;

namespace Ansight.ArtifactHarness;

public sealed class ArtifactPage : ContentPage
{
    public const int BinarySize = 131089;
    public const string ReportText = "{\"schema\":\"ansight.artifact-harness/v1\",\"message\":\"Published from the app — café 🚀\",\"value\":42}";
    private readonly Label connection = Status("artifacts.connection", "Waiting for host");
    private readonly Label reportStatus = Status("artifacts.report-status", "Report: not published");
    private readonly Label fileStatus = Status("artifacts.file-status", "File: not published");
    private readonly Label rejectStatus = Status("artifacts.reject-status", "Rejection: not checked");
    private readonly Label cancelStatus = Status("artifacts.cancel-status", "Cancellation: not checked");
    private readonly List<Button> actions = [];
    private int reportCount;
    private int fileCount;
    private bool busy;

    public ArtifactPage()
    {
        Title = "Artifact publishing";
        AutomationId = "artifacts.root";
        BackgroundColor = Color.FromArgb("#F3F5FA");
        Content = new ScrollView
        {
            Content = new VerticalStackLayout
            {
                Padding = 20,
                Spacing = 10,
                Children =
                {
                    new Label { Text = "Artifact publishing", FontSize = 26, TextColor = Colors.Black },
                    new Label { Text = "Publish from app buttons. No artifact provider or custom remote tool is registered.", TextColor = Colors.Black },
                    connection,
                    Action("artifacts.reset", "Reset check counters", reportStatus, () =>
                    {
                        reportCount = 0;
                        fileCount = 0;
                        MainThread.BeginInvokeOnMainThread(() =>
                        {
                            fileStatus.Text = "File: not published";
                            rejectStatus.Text = "Rejection: not checked";
                            cancelStatus.Text = "Cancellation: not checked";
                        });
                        return Task.FromResult("Report: not published");
                    }),
                    Action("artifacts.publish-report", "Publish JSON report", reportStatus, async () =>
                    {
                        var result = await ArtifactPublisher.PublishAsync(new ArtifactResult(
                            Metadata("report", "Harness JSON report", "report", "application/json", "report.json"),
                            ArtifactPayload.FromText(ReportText)));
                        return result.Success ? $"Report published: {++reportCount}" : $"FAILED: {result.Message}";
                    }),
                    reportStatus,
                    Action("artifacts.publish-file", "Publish 128 KiB file", fileStatus, async () =>
                    {
                        var path = Path.Combine(FileSystem.CacheDirectory, "artifact-fixture.bin");
                        await File.WriteAllBytesAsync(path, BinaryPayload());
                        var result = await ArtifactPublisher.PublishAsync(new ArtifactResult(
                            Metadata("binary", "Harness binary file", "binary", "application/octet-stream", "fixture.bin"),
                            ArtifactPayload.FromFile(path)));
                        // The retained copy must remain readable after the app deletes its source.
                        File.Delete(path);
                        return result.Success ? $"File published: {++fileCount}" : $"FAILED: {result.Message}";
                    }),
                    fileStatus,
                    Action("artifacts.reject", "Try invalid metadata", rejectStatus, async () =>
                    {
                        var result = await ArtifactPublisher.PublishAsync(new ArtifactResult(
                            Metadata("invalid", "Invalid artifact", "report", "text/plain", ""), ArtifactPayload.FromText("must not be retained")));
                        return result.Success ? "FAILED: invalid metadata accepted" : "Invalid metadata rejected";
                    }),
                    rejectStatus,
                    Action("artifacts.cancel", "Cancel a partial upload", cancelStatus, async () =>
                    {
                        using var cancellation = new CancellationTokenSource();
                        var payload = ArtifactPayload.FromStream(_ => ValueTask.FromResult<Stream>(
                            new CancelAfterChunkStream(BinaryPayload(), cancellation)), BinarySize);
                        try
                        {
                            var result = await ArtifactPublisher.PublishAsync(new ArtifactResult(
                                Metadata("cancelled", "Cancelled artifact", "binary", "application/octet-stream", "cancelled.bin"), payload), cancellation.Token);
                            return $"FAILED: cancellation did not propagate ({result.Success}: {result.Message})";
                        }
                        catch (OperationCanceledException) when (cancellation.IsCancellationRequested)
                        {
                            return "Partial upload cancelled";
                        }
                    }),
                    cancelStatus
                }
            }
        };
    }

    protected override void OnAppearing()
    {
        base.OnAppearing();
        Runtime.HostConnection.StatusChanged += ConnectionChanged;
        RefreshConnection();
    }

    protected override void OnDisappearing()
    {
        Runtime.HostConnection.StatusChanged -= ConnectionChanged;
        base.OnDisappearing();
    }

    private void ConnectionChanged(object? sender, HostConnectionChangedEventArgs args)
        => MainThread.BeginInvokeOnMainThread(RefreshConnection);

    private void RefreshConnection()
    {
        connection.Text = Runtime.HostConnection.IsConnected ? "Connected" : "Waiting for host";
        foreach (var button in actions) button.IsEnabled = !busy && Runtime.HostConnection.IsConnected;
    }

    private Button Action(string id, string text, Label status, Func<Task<string>> publish)
    {
        var button = new Button { AutomationId = id, Text = text, IsEnabled = false };
        actions.Add(button);
        button.Clicked += async (_, _) =>
        {
            busy = true;
            RefreshConnection();
            status.Text = "Publishing…";
            try { status.Text = await Task.Run(publish); }
            catch (Exception error) { status.Text = $"FAILED: {error.Message}"; }
            finally { busy = false; RefreshConnection(); }
        };
        return button;
    }

    private static Label Status(string id, string text)
        => new() { AutomationId = id, Text = text, TextColor = Colors.Black, FontSize = 14 };

    private static ArtifactMetadata Metadata(string id, string name, string kind, string mime, string file)
        => new(id, "artifact-harness", name, kind, mime, file);

    private static byte[] BinaryPayload()
        => Enumerable.Range(0, BinarySize).Select(index => (byte)(index % 251)).ToArray();

    private sealed class CancelAfterChunkStream(byte[] bytes, CancellationTokenSource cancellation)
        : MemoryStream(bytes, writable: false)
    {
        private bool readOnce;
        public override ValueTask<int> ReadAsync(Memory<byte> buffer, CancellationToken cancellationToken = default)
        {
            if (readOnce)
            {
                cancellation.Cancel();
                cancellationToken.ThrowIfCancellationRequested();
            }
            readOnce = true;
            return base.ReadAsync(buffer[..Math.Min(buffer.Length, 65536)], cancellationToken);
        }
    }
}
