using System.Diagnostics;
using System.Text.Json;
using Ansight.AudioHarness.Core;
using Ansight.AudioHarness.Services;
using PropertyChanged;

namespace Ansight.AudioHarness.ViewModels;

[AddINotifyPropertyChangedInterface]
public sealed class HarnessViewModel
{
    private const string DefaultPhrase = "The quick brown fox jumps over the lazy dog.";
    private readonly ISpeechCaptureService speech;
    private readonly AudioRunStore runs;
    private readonly Stopwatch stopwatch = new();
    private readonly IDispatcherTimer timer;
    private readonly SemaphoreSlim resultWriteGate = new(1, 1);
    private string? activeRunId;
    private string? resultRunId;
    private string runExpectedPhrase = "";
    private bool runCaptureOnly;
    private DateTimeOffset startedUtc;
    private CancellationTokenSource? durationLimit;
    private string? resultJson;
    private bool finishingRun;

    public HarnessViewModel(ISpeechCaptureService speech, AudioRunStore runs)
    {
        this.speech = speech;
        this.runs = runs;
        speech.Updated += OnSpeechUpdated;
        StartCommand = new Command(async () => await StartAsync());
        StopCommand = new Command(async () => await StopAsync());
        ResetCommand = new Command(Reset);
        CopyResultCommand = new Command(async () => await CopyResultAsync());
        timer = Dispatcher.GetForCurrentThread()!.CreateTimer();
        timer.Interval = TimeSpan.FromMilliseconds(100);
        timer.Tick += (_, _) => Elapsed = stopwatch.Elapsed.ToString(@"mm\:ss");
    }

    public Command StartCommand { get; }
    public Command StopCommand { get; }
    public Command ResetCommand { get; }
    public Command CopyResultCommand { get; }
    public string ExpectedPhrase { get; set; } = DefaultPhrase;
    public bool CaptureOnly { get; set; }
    public bool SupportsCaptureOnly => true;
    public string RunId { get; private set; } = "";
    public string ResultSaved { get; private set; } = "Not saved";
    public string ArtifactStatus { get; private set; } = "Awaiting a terminal run";
    public long CapturedFrameCount { get; private set; }
    [DependsOn(nameof(CaptureOnly))]
    public string CaptureMode => CaptureOnly ? "Capture only" : "Transcription";
    public string? CaptureFilePath { get; private set; }
    public string Transcript { get; private set; } = "";
    public string Phase { get; private set; } = "Ready";
    public string StatusMessage { get; private set; } = "Start listening, then inject the speech track.";
    public string Elapsed { get; private set; } = "00:00";
    public double InputLevel { get; private set; }
    public bool IsBusy { get; private set; }
    public bool IsFinal { get; private set; }
    public bool HasResult { get; private set; }
    public string ValidationLabel { get; private set; } = "Not run";
    public string ValidationMessage { get; private set; } = "Only a matching final transcript passes.";
    public Color ValidationColor { get; private set; } = Color.FromArgb("#52647E");

    [DependsOn(nameof(IsBusy))]
    public bool CanStart => !IsBusy;

    [DependsOn(nameof(IsBusy), nameof(Phase))]
    public bool CanStop => IsBusy && Phase == "Listening";

    [DependsOn(nameof(CaptureOnly))]
    public bool UsesSpeechRecognition => !SupportsCaptureOnly || !CaptureOnly;

    [DependsOn(nameof(CaptureOnly))]
    public string InputRouteDescription => UsesSpeechRecognition
        ? "Synthetic track → microphone → transcript"
        : "Synthetic track → microphone → saved audio";

    [DependsOn(nameof(Transcript), nameof(CaptureFilePath), nameof(CaptureOnly))]
    public string TranscriptDisplay => runCaptureOnly && CaptureFilePath is not null
        ? $"Saved microphone audio: {Path.GetFileName(CaptureFilePath)}"
        : string.IsNullOrWhiteSpace(Transcript) ? UsesSpeechRecognition ? "Waiting for speech…" : "Waiting for microphone audio…" : Transcript;

    [DependsOn(nameof(IsFinal), nameof(Transcript), nameof(Phase))]
    public string TranscriptKind => Phase == "Captured" ? "CAPTURED" : IsFinal ? "FINAL" : Transcript.Length > 0 ? "PARTIAL" : "";

    [DependsOn(nameof(CaptureOnly))]
    public string LanguageDescription => UsesSpeechRecognition
        ? "English (US) · stops after 30 seconds or provider silence detection"
        : "Microphone recording · stops automatically after 30 seconds";
    [DependsOn(nameof(CaptureOnly))]
    public string PlatformDescription => DeviceInfo.Platform == DevicePlatform.iOS
        ? UsesSpeechRecognition
            ? "Apple Speech · audio level is measured from microphone samples. Recognition may use Apple servers."
            : "Microphone samples are saved locally as WAV. Speech recognition is not used. Compare the recording with the injected fixture to verify input."
        : UsesSpeechRecognition
            ? "Android Speech · level is the recognizer’s activity estimate. Requires a speech provider; network may be needed."
            : "Android AudioRecord · actual microphone PCM is saved as WAV. Compare the recording with the injected fixture to verify input.";

    public async Task StartAsync()
    {
        if (IsBusy)
            return;

        if (UsesSpeechRecognition && string.IsNullOrWhiteSpace(ExpectedPhrase))
        {
            ValidationLabel = "Enter an expected phrase";
            ValidationMessage = "A blank expectation cannot validate audio input.";
            return;
        }

        Reset();
        activeRunId = Guid.NewGuid().ToString("N");
        RunId = activeRunId;
        ResultSaved = "Pending";
        ArtifactStatus = "Capture in progress";
        resultRunId = activeRunId;
        var runId = activeRunId;
        runExpectedPhrase = ExpectedPhrase;
        runCaptureOnly = !UsesSpeechRecognition;
        startedUtc = DateTimeOffset.UtcNow;
        IsBusy = true;
        Phase = "Starting";
        StatusMessage = runCaptureOnly ? "Checking microphone permission…" : "Checking microphone and speech permissions…";
        ValidationLabel = runCaptureOnly ? "Awaiting audio capture" : "Awaiting final transcript";
        stopwatch.Restart();
        timer.Start();
        durationLimit = new CancellationTokenSource();
        var token = durationLimit.Token;
        try
        {
            await speech.StartAsync(new SpeechCaptureRequest(runId, "en-US", runCaptureOnly));
            if (activeRunId == runId && IsBusy)
                _ = StopAtLimitAsync(runId, token);
        }
        catch (Exception error)
        {
            if (activeRunId == runId && IsBusy)
            {
                await speech.CancelAsync();
                await FinishAsync("Error", error.Message, false);
            }
        }
    }

    public async Task StopAsync()
    {
        if (!IsBusy || Phase != "Listening")
            return;
        Phase = "Processing";
        InputLevel = 0;
        StatusMessage = runCaptureOnly ? "Finalizing the microphone recording…" : "Microphone stopped. Waiting for the final transcript…";
        try
        {
            await speech.StopAsync();
        }
        catch (Exception error)
        {
            await speech.CancelAsync();
            await FinishAsync("Error", error.Message, false);
        }
    }

    public async Task CancelAsync()
    {
        if (!IsBusy)
            return;
        // Invalidate callbacks before native cancellation so an old final cannot pass.
        activeRunId = null;
        await speech.CancelAsync();
        await FinishAsync("Cancelled", "Capture stopped because the app left the foreground.", false);
    }

    private async Task StopAtLimitAsync(string runId, CancellationToken cancellationToken)
    {
        try
        {
            await Task.Delay(TimeSpan.FromSeconds(30), cancellationToken);
            await MainThread.InvokeOnMainThreadAsync(async () =>
            {
                if (activeRunId != runId || !IsBusy)
                    return;
                if (Phase == "Listening")
                    await StopAsync();
                else if (Phase == "Starting")
                {
                    await speech.CancelAsync();
                    await FinishAsync("Error", "The speech recognizer did not become ready.", false);
                }
            });
        }
        catch (OperationCanceledException)
        {
            // The run completed or was reset before the listening limit.
        }
    }

    private void OnSpeechUpdated(object? sender, SpeechCaptureUpdate update)
    {
        MainThread.BeginInvokeOnMainThread(async () =>
        {
            if (!IsBusy || update.RunId != activeRunId)
                return;
            if (update.InputLevel.HasValue)
                InputLevel = Math.Clamp(update.InputLevel.Value, 0, 1);
            if (!string.IsNullOrEmpty(update.Transcript) || update.Phase == SpeechCapturePhase.Completed)
                Transcript = update.Transcript;

            switch (update.Phase)
            {
                case SpeechCapturePhase.Listening:
                    if (Phase == "Starting")
                    {
                        Phase = "Listening";
                        StatusMessage = "Microphone ready. Inject the speech track now.";
                    }
                    break;
                case SpeechCapturePhase.Processing:
                    Phase = "Processing";
                    InputLevel = 0;
                    StatusMessage = update.Message ?? "Waiting for the final transcript…";
                    break;
                case SpeechCapturePhase.Completed:
                    await FinishAsync("Completed", "Speech recognition finished.", true, update.CaptureFilePath);
                    break;
                case SpeechCapturePhase.Captured:
                    if (!runCaptureOnly || string.IsNullOrWhiteSpace(update.CaptureFilePath))
                        await FinishAsync("Error", "The capture service did not provide a valid recording path.", false);
                    else
                        await FinishAsync("Captured", update.Message ?? "Microphone audio saved.", false, update.CaptureFilePath);
                    break;
                case SpeechCapturePhase.Error:
                    await FinishAsync("Error", update.Message ?? "Speech recognition failed.", false, update.CaptureFilePath);
                    break;
            }
        });
    }

    private async Task FinishAsync(string phase, string message, bool isFinal, string? captureFilePath = null)
    {
        if (!IsBusy || finishingRun)
            return;
        finishingRun = true;
        activeRunId = null;
        Phase = phase;
        StatusMessage = message;
        IsFinal = isFinal;
        CaptureFilePath = captureFilePath;
        InputLevel = 0;
        timer.Stop();
        stopwatch.Stop();
        durationLimit?.Cancel();
        durationLimit?.Dispose();
        durationLimit = null;
        var validation = TranscriptValidator.Validate(runExpectedPhrase, Transcript, isFinal);
        bool passed = !runCaptureOnly && isFinal && validation.State == TranscriptValidationState.Passed;
        bool captured = phase == "Captured" && captureFilePath is not null;
        ValidationLabel = captured ? "Audio captured" : passed ? "PASS — phrase matched" : isFinal ? "FAIL — phrase not matched" : "NOT PASSED — " + phase.ToLowerInvariant();
        ValidationMessage = captured ? "Recording saved. Compare it with the injected fixture to verify microphone input." : isFinal ? validation.Reason : message;
        ValidationColor = Color.FromArgb(captured ? "#1262ED" : passed ? "#16804A" : "#B24030");
        var completedRunId = resultRunId;
        var completedAt = DateTimeOffset.UtcNow;
        var durationSeconds = stopwatch.Elapsed.TotalSeconds;
        string CreateJson(MicrophoneCaptureInfo capture) => JsonSerializer.Serialize(new
        {
            schema = "ansight.audio-harness-result/v1",
            runId = completedRunId,
            platform = DeviceInfo.Platform.ToString(),
            osVersion = DeviceInfo.VersionString,
            startedUtc,
            completedUtc = completedAt,
            durationSeconds,
            phase,
            language = "en-US",
            expected = runExpectedPhrase,
            transcript = Transcript,
            isFinal,
            passed,
            captureOnly = runCaptureOnly,
            captureFilePath,
            capture = JsonSerializer.SerializeToElement(capture, new JsonSerializerOptions(JsonSerializerDefaults.Web)),
            validation.NormalizedExpected,
            validation.NormalizedActual,
            message
        }, new JsonSerializerOptions { WriteIndented = true });
        await resultWriteGate.WaitAsync();
        try
        {
            var saved = await runs.SaveAsync(completedRunId!, captureFilePath, CreateJson);
            resultJson = saved.Json;
            CapturedFrameCount = saved.Capture.FrameCount;
            HasResult = true;
            ResultSaved = "Saved";
            ArtifactStatus = "Ready for snapshot";
            if (captureFilePath is not null && !saved.Capture.Available)
                StatusMessage += " " + saved.Capture.Reason;
            AudioRunStore.AnnounceTerminalRun(saved, phase, runCaptureOnly);
        }
        catch (Exception error)
        {
            ResultSaved = "Not saved";
            ArtifactStatus = "Snapshot unavailable";
            StatusMessage += " Result could not be saved: " + error.Message;
        }
        finally
        {
            resultWriteGate.Release();
            finishingRun = false;
            IsBusy = false;
        }
    }

    private void Reset()
    {
        if (IsBusy)
            return;
        activeRunId = null;
        resultRunId = null;
        RunId = "";
        ResultSaved = "Not saved";
        ArtifactStatus = "Awaiting a terminal run";
        CapturedFrameCount = 0;
        Transcript = "";
        CaptureFilePath = null;
        Phase = "Ready";
        StatusMessage = "Start listening, then inject the speech track.";
        InputLevel = 0;
        Elapsed = "00:00";
        IsFinal = false;
        HasResult = false;
        resultJson = null;
        ValidationLabel = "Not run";
        ValidationMessage = "Only a matching final transcript passes.";
        ValidationColor = Color.FromArgb("#52647E");
    }

    private async Task CopyResultAsync()
    {
        if (resultJson is null)
            return;
        try
        {
            await Clipboard.SetTextAsync(resultJson);
            StatusMessage = "Result JSON copied.";
        }
        catch (Exception error)
        {
            StatusMessage = "Could not copy the result: " + error.Message;
        }
    }
}
