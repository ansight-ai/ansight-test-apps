namespace Ansight.AudioHarness.Services;

/// <summary>Transcribes the finalized microphone recording while keeping native capture and run identity intact.</summary>
public sealed class TranscribingSpeechCaptureService : ISpeechCaptureService
{
    private readonly PlatformSpeechCaptureService platform;
    private readonly IAudioTranscriber transcriber;
    private CaptureRun? activeRun;

    public TranscribingSpeechCaptureService(PlatformSpeechCaptureService platform, IAudioTranscriber transcriber)
    {
        this.platform = platform;
        this.transcriber = transcriber;
        platform.Updated += OnPlatformUpdated;
    }

    public event EventHandler<SpeechCaptureUpdate>? Updated;

    public async Task StartAsync(SpeechCaptureRequest request)
    {
        await CancelAsync();
        var run = new CaptureRun(request);
        activeRun = run;
        try
        {
            if (run.UsesWhisper)
            {
                Updated?.Invoke(this, new(request.RunId, SpeechCapturePhase.Preparing,
                    Message: "Preparing the offline Whisper model…"));
                using var preparation = CancellationTokenSource.CreateLinkedTokenSource(run.Cancellation.Token);
                preparation.CancelAfter(TimeSpan.FromSeconds(30));
                await transcriber.PrepareAsync(preparation.Token);
            }
            if (!ReferenceEquals(activeRun, run)) return;
            await platform.StartAsync(request with { CaptureOnly = request.CaptureOnly || run.UsesWhisper });
        }
        catch (Exception error)
        {
            if (ReferenceEquals(activeRun, run))
                Finish(run, new(request.RunId, SpeechCapturePhase.Error,
                    Message: error is OperationCanceledException ? "Whisper model preparation timed out." : error.Message));
        }
    }

    public Task StopAsync() => platform.StopAsync();

    public async Task CancelAsync()
    {
        var run = activeRun;
        activeRun = null;
        if (run is not null) await run.Cancellation.CancelAsync();
        await platform.CancelAsync();
        if (run is not null)
        {
            // The processor observes cancellation before its context can be reused by a later run.
            if (run.TranscriptionTask is not null) await run.TranscriptionTask;
            run.Cancellation.Dispose();
        }
    }

    private void OnPlatformUpdated(object? sender, SpeechCaptureUpdate update)
    {
        MainThread.BeginInvokeOnMainThread(() =>
        {
            var run = activeRun;
            if (run is null || run.Request.RunId != update.RunId) return;
            if (run.UsesWhisper && update.Phase == SpeechCapturePhase.Captured)
            {
                if (run.TranscriptionTask is not null) return;
                run.TranscriptionTask = TranscribeAsync(run, update.CaptureFilePath);
            }
            else if (update.Phase is SpeechCapturePhase.Completed or SpeechCapturePhase.Captured or SpeechCapturePhase.Error)
            {
                Finish(run, update);
            }
            else
            {
                Updated?.Invoke(this, update);
            }
        });
    }

    private async Task TranscribeAsync(CaptureRun run, string? capturePath)
    {
        try
        {
            if (string.IsNullOrWhiteSpace(capturePath))
                throw new InvalidDataException("The microphone did not provide a finalized recording for Whisper.");
            Updated?.Invoke(this, new(run.Request.RunId, SpeechCapturePhase.Processing,
                Message: "Microphone stopped. Transcribing locally with Whisper…", CaptureFilePath: capturePath));
            using var processing = CancellationTokenSource.CreateLinkedTokenSource(run.Cancellation.Token);
            processing.CancelAfter(TimeSpan.FromSeconds(60));
            var result = await transcriber.TranscribeAsync(capturePath, run.Request.Language, processing.Token);
            if (!ReferenceEquals(activeRun, run)) return;
            if (string.IsNullOrWhiteSpace(result.Text))
                throw new InvalidDataException("Whisper returned no recognizable speech.");
            Finish(run, new(run.Request.RunId, SpeechCapturePhase.Completed, result.Text,
                Message: "Whisper transcribed the recorded microphone audio locally.", CaptureFilePath: capturePath,
                Transcription: result.Info));
        }
        catch (Exception error)
        {
            if (!ReferenceEquals(activeRun, run)) return;
            Finish(run, new(run.Request.RunId, SpeechCapturePhase.Error,
                Message: error is OperationCanceledException ? "Whisper transcription timed out." : $"Whisper transcription failed: {error.Message}",
                CaptureFilePath: capturePath));
        }
    }

    private void Finish(CaptureRun run, SpeechCaptureUpdate update)
    {
        if (!ReferenceEquals(activeRun, run)) return;
        activeRun = null;
        run.Cancellation.Dispose();
        Updated?.Invoke(this, update);
    }

    private sealed class CaptureRun(SpeechCaptureRequest request)
    {
        public SpeechCaptureRequest Request { get; } = request;
        public bool UsesWhisper => !Request.CaptureOnly && Request.Provider == TranscriptionProvider.Whisper;
        public CancellationTokenSource Cancellation { get; } = new();
        public Task? TranscriptionTask { get; set; }
    }
}
