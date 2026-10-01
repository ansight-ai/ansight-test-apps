namespace BoulderCaptureSpike;

public sealed class MainPage : ContentPage
{
    private readonly Label statusLabel;
    private readonly Button scanButton;
    private readonly Picker qualityPicker;
    private readonly Button viewGlbButton;
    private readonly Button photoScanButton;
    private readonly Button connectAnsightButton;
    private readonly Button shareGlbButton;
    private readonly Button shareUsdzButton;
    private readonly Button shareDiagnosticsButton;
    private readonly IDispatcherTimer statusTimer;
    private string lastCompletedGlbPath;
    private string lastAnnouncedGlbPath;

    public MainPage()
    {
        lastCompletedGlbPath = Preferences.Default.Get("LastCompletedGlbPath", string.Empty);
        if (!File.Exists(lastCompletedGlbPath))
            lastCompletedGlbPath = FindLatestExport();
        lastAnnouncedGlbPath = lastCompletedGlbPath;
        Title = "Boulder capture";
        statusLabel = new Label { Text = "Checking RealityKit support…", FontSize = 16 };
        scanButton = new Button { Text = "Scan whole space with LiDAR" };
        qualityPicker = new Picker { Title = "Processing quality" };
        qualityPicker.Items.Add("Balanced · faster, smaller GLB");
        qualityPicker.Items.Add("High detail · denser surfaces");
        qualityPicker.SelectedIndex = 0;
        viewGlbButton = new Button { Text = "View exported GLB", IsEnabled = false };
        photoScanButton = new Button { Text = "Photo area scan (experimental)" };
        connectAnsightButton = new Button { Text = "Connect Ansight" };
        shareGlbButton = new Button { Text = "Share GLB", IsEnabled = false };
        shareUsdzButton = new Button { Text = "Share USDZ", IsEnabled = false };
        shareDiagnosticsButton = new Button { Text = "Share diagnostics" };

        scanButton.Clicked += (_, _) =>
        {
            try
            {
                SpikeDiagnostics.Record("Scan button tapped");
                if (!BoulderCaptureNative.PresentSceneMesh(qualityPicker.SelectedIndex == 1))
                {
                    statusLabel.Text = "Could not open the LiDAR space scanner.";
                    SpikeDiagnostics.Record("LiDAR space scanner could not open");
                }
            }
            catch (Exception error)
            {
                SpikeDiagnostics.Record(error, "Open native scan view");
                statusLabel.Text = $"Could not open capture: {error.Message}";
            }
        };
        photoScanButton.Clicked += (_, _) =>
        {
            try
            {
                SpikeDiagnostics.Record("Photo area scan button tapped");
                if (!BoulderCaptureNative.Present())
                {
                    statusLabel.Text = "Could not open RealityKit photo capture.";
                }
            }
            catch (Exception error)
            {
                SpikeDiagnostics.Record(error, "Open photo area scan");
                statusLabel.Text = $"Could not open photo scan: {error.Message}";
            }
        };
#if DEBUG
        connectAnsightButton.Clicked += async (_, _) =>
        {
            try
            {
                await global::Ansight.Runtime.HostConnection.ConnectAsync(
                    global::Ansight.HostConnectionRequest.QrCode());
                statusLabel.Text = "Ansight connected. Return here after scanning to share the model.";
            }
            catch (Exception error)
            {
                SpikeDiagnostics.Record(error, "Connect Ansight");
                statusLabel.Text = $"Ansight connection failed: {error.Message}";
            }
        };
#else
        connectAnsightButton.IsVisible = false;
#endif
        shareGlbButton.Clicked += async (_, _) => await ShareModelAsync(lastCompletedGlbPath);
        viewGlbButton.Clicked += (_, _) =>
        {
            try
            {
                if (!BoulderCaptureNative.PresentGlb(lastCompletedGlbPath))
                    statusLabel.Text = "Could not open the exported GLB.";
            }
            catch (Exception error)
            {
                SpikeDiagnostics.Record(error, "Open exported GLB");
                statusLabel.Text = $"Could not open GLB: {error.Message}";
            }
        };
        shareUsdzButton.Clicked += async (_, _) => await ShareModelAsync(BoulderCaptureNative.UsdzPath);
        shareDiagnosticsButton.Clicked += async (_, _) => await ShareDiagnosticsAsync();

        Content = new ScrollView
        {
            Content = new VerticalStackLayout
            {
                Padding = new Thickness(24, 48),
                Spacing = 18,
                Children =
                {
                    new Label { Text = "Boulder and space scan", FontSize = 28, FontAttributes = FontAttributes.Bold },
                    new Label { Text = "LiDAR shows a live structural mesh as you move. The visual GLB uses matching camera color and depth samples to capture visible details across the space." },
                    statusLabel,
                    connectAnsightButton,
                    qualityPicker,
                    scanButton,
                    photoScanButton,
                    viewGlbButton,
                    shareGlbButton,
                    shareUsdzButton,
                    shareDiagnosticsButton,
                },
            },
        };

        statusTimer = Dispatcher.CreateTimer();
        statusTimer.Interval = TimeSpan.FromMilliseconds(500);
        statusTimer.Tick += (_, _) => RefreshStatus();
        Loaded += (_, _) =>
        {
            RefreshStatus();
            statusTimer.Start();
        };
        Unloaded += (_, _) => statusTimer.Stop();
    }

    private void RefreshStatus()
    {
        try
        {
            var sceneSupported = BoulderCaptureNative.IsSceneMeshSupported;
            scanButton.IsEnabled = sceneSupported;
            photoScanButton.IsEnabled = BoulderCaptureNative.IsSupported;
            statusLabel.Text = sceneSupported
                ? BoulderCaptureNative.Status
                : "Space scan needs a LiDAR iPhone or iPad running iOS 18 or later.";
            var glbPath = BoulderCaptureNative.GlbPath;
            if (File.Exists(glbPath) && glbPath != lastAnnouncedGlbPath)
            {
#if DEBUG
                var scanId = Path.GetFileName(Path.GetDirectoryName(glbPath));
                if (!string.IsNullOrWhiteSpace(scanId) &&
                    Path.GetFileName(glbPath) == "space.glb")
                    global::Ansight.Runtime.Event("boulder.scan.glb.ready",
                        global::Ansight.Telemetry.Events.AppEventType.Info, scanId);
#endif
                lastAnnouncedGlbPath = glbPath;
                lastCompletedGlbPath = glbPath;
                Preferences.Default.Set("LastCompletedGlbPath", glbPath);
                SpikeDiagnostics.Record($"Scan GLB ready for Ansight; path={glbPath}");
            }
            shareGlbButton.IsEnabled = File.Exists(lastCompletedGlbPath);
            viewGlbButton.IsEnabled = shareGlbButton.IsEnabled;
            shareUsdzButton.IsEnabled = File.Exists(BoulderCaptureNative.UsdzPath);
        }
        catch (Exception error)
        {
            SpikeDiagnostics.Record(error, "Refresh scan status");
            statusTimer.Stop();
            statusLabel.Text = $"Scan status failed: {error.Message}";
        }
    }

    private async Task ShareModelAsync(string filePath)
    {
        if (!File.Exists(filePath))
        {
            return;
        }

        try
        {
            await Share.Default.RequestAsync(new ShareFileRequest
            {
                Title = Path.GetFileName(filePath),
                File = new ShareFile(filePath),
            });
        }
        catch (Exception error)
        {
            SpikeDiagnostics.Record(error, "Share model");
            statusLabel.Text = $"Could not share model: {error.Message}";
        }
    }

    private static string FindLatestExport()
    {
        var root = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments),
            "BoulderScans");
        if (!Directory.Exists(root)) return string.Empty;
        try
        {
            return Directory.EnumerateFiles(root, "*.glb", SearchOption.AllDirectories)
                .Where(path => Path.GetFileName(path) is "space.glb" or "boulder.glb")
                .OrderByDescending(File.GetLastWriteTimeUtc)
                .FirstOrDefault() ?? string.Empty;
        }
        catch (Exception error)
        {
            SpikeDiagnostics.Record(error, "Find last GLB export");
            return string.Empty;
        }
    }

    private async Task ShareDiagnosticsAsync()
    {
        try
        {
            SpikeDiagnostics.Record("Diagnostics share requested");
            var paths = new[] { BoulderCaptureNative.DiagnosticsPath, SpikeDiagnostics.DotNetLogPath }
                .Where(File.Exists)
                .Select(path => new ShareFile(path))
                .ToList();
            await Share.Default.RequestAsync(new ShareMultipleFilesRequest
            {
                Title = "Boulder Capture diagnostics",
                Files = paths,
            });
        }
        catch (Exception error)
        {
            SpikeDiagnostics.Record(error, "Share diagnostics");
            statusLabel.Text = $"Could not share diagnostics: {error.Message}";
        }
    }
}
