using Android.Content;
using Android.OS;
using Android.Speech;
using Microsoft.Maui.ApplicationModel;

namespace Ansight.AudioHarness.Services;

/// <summary>Exercises Android's microphone speech path through the installed recognition provider.</summary>
public sealed class PlatformSpeechCaptureService : ISpeechCaptureService
{
    private readonly AndroidPcmCaptureService microphoneCapture = new();
    private bool captureOnlyActive;
    private SpeechRecognizer? recognizer;
    private RecognitionListener? recognitionListener;
    private SpeechCaptureRequest? activeRequest;
    private CancellationTokenSource? deadlineCancellation;
    private int generation;
    private string transcript = "";
    private bool listening;
    private bool processing;

    public event EventHandler<SpeechCaptureUpdate>? Updated;

    public PlatformSpeechCaptureService()
    {
        microphoneCapture.Updated += (_, update) => Updated?.Invoke(this, update);
    }

    public Task StartAsync(SpeechCaptureRequest request) =>
        MainThread.InvokeOnMainThreadAsync(() => StartOnMainThreadAsync(request));

    public Task StopAsync() => MainThread.InvokeOnMainThreadAsync(async () =>
    {
        if (captureOnlyActive)
        {
            await microphoneCapture.StopAsync();
            return;
        }
        if (activeRequest is null || processing)
        {
            return;
        }

        int captureGeneration = generation;
        if (recognizer is null)
        {
            Finish(captureGeneration, SpeechCapturePhase.Error, "Capture stopped before the microphone was ready.");
            return;
        }

        try
        {
            BeginProcessing(captureGeneration);
            recognizer.StopListening();
        }
        catch (Exception exception)
        {
            Finish(captureGeneration, SpeechCapturePhase.Error, $"Unable to stop speech capture: {exception.Message}");
        }
    });

    public Task CancelAsync() => MainThread.InvokeOnMainThreadAsync(async () =>
    {
        ReleaseCapture();
        await microphoneCapture.CancelAsync();
        captureOnlyActive = false;
    });

    private async Task StartOnMainThreadAsync(SpeechCaptureRequest request)
    {
        ReleaseCapture();
        await microphoneCapture.CancelAsync();
        captureOnlyActive = request.CaptureOnly;
        if (request.CaptureOnly)
        {
            await microphoneCapture.StartAsync(request);
            return;
        }
        int captureGeneration = generation;
        activeRequest = request;
        transcript = "";

        try
        {
            PermissionStatus permission = await Permissions.RequestAsync<Permissions.Microphone>();
            if (!IsCurrent(captureGeneration))
            {
                return;
            }

            if (permission != PermissionStatus.Granted)
            {
                Finish(captureGeneration, SpeechCapturePhase.Error,
                    "Microphone permission was denied. Enable it in Android Settings and try again.");
                return;
            }

            Context context = global::Android.App.Application.Context;
            if (!SpeechRecognizer.IsRecognitionAvailable(context))
            {
                Finish(captureGeneration, SpeechCapturePhase.Error,
                    "No Android speech recognition service is installed. Use a Google Play emulator with a working speech provider, or install one.");
                return;
            }

            recognizer = SpeechRecognizer.CreateSpeechRecognizer(context)
                ?? throw new InvalidOperationException("Android could not create a speech recognizer.");
            recognitionListener = new RecognitionListener(this, captureGeneration);
            recognizer.SetRecognitionListener(recognitionListener);

            using var intent = new Intent(RecognizerIntent.ActionRecognizeSpeech);
            intent.PutExtra(RecognizerIntent.ExtraLanguageModel, RecognizerIntent.LanguageModelFreeForm);
            intent.PutExtra(RecognizerIntent.ExtraLanguage, request.Language);
            intent.PutExtra(RecognizerIntent.ExtraPartialResults, true);
            intent.PutExtra(RecognizerIntent.ExtraMaxResults, 1);
            // No audio-source or phrase-bias extras: the provider must hear the real microphone input.
            ScheduleDeadline(captureGeneration, TimeSpan.FromSeconds(15),
                "The Android speech provider did not become ready within 15 seconds. Check its setup, language models and network connection.");
            recognizer.StartListening(intent);
        }
        catch (Exception exception)
        {
            Finish(captureGeneration, SpeechCapturePhase.Error, $"Unable to start speech capture: {exception.Message}");
        }
    }

    private bool IsCurrent(int captureGeneration) =>
        generation == captureGeneration && activeRequest is not null;

    private void OnReady(int captureGeneration)
    {
        if (!IsCurrent(captureGeneration) || processing)
        {
            return;
        }

        listening = true;
        CancelDeadline();
        ScheduleDeadline(captureGeneration, TimeSpan.FromSeconds(60),
            "The Android speech provider did not finish within 60 seconds. Reset the test and try again.");
        Publish(SpeechCapturePhase.Listening,
            message: "Microphone ready. Play the fixture now. Android may finish automatically after silence; input level is a provider RMS proxy.");
    }

    private void BeginProcessing(int captureGeneration)
    {
        if (!IsCurrent(captureGeneration) || processing)
        {
            return;
        }

        listening = false;
        processing = true;
        ScheduleDeadline(captureGeneration, TimeSpan.FromSeconds(10),
            "Android did not return a final transcript within 10 seconds after recording stopped.");
        Publish(SpeechCapturePhase.Processing, message: "Microphone stopped. Waiting for the final Android transcript.");
    }

    private void OnTranscript(int captureGeneration, Bundle? results, bool isFinal)
    {
        if (!IsCurrent(captureGeneration))
        {
            return;
        }

        string value = results?.GetStringArrayList(SpeechRecognizer.ResultsRecognition)?.FirstOrDefault() ?? "";
        if (isFinal)
        {
            // A partial result is never promoted to a successful final result.
            transcript = value;
            Finish(captureGeneration,
                string.IsNullOrWhiteSpace(value) ? SpeechCapturePhase.Error : SpeechCapturePhase.Completed,
                string.IsNullOrWhiteSpace(value) ? "Android returned an empty final transcript." : "Final transcript received from Android.");
            return;
        }

        if (!string.IsNullOrWhiteSpace(value))
        {
            transcript = value;
        }

        if (listening || processing)
        {
            Publish(processing ? SpeechCapturePhase.Processing : SpeechCapturePhase.Listening);
        }
    }

    private void OnLevel(int captureGeneration, float rmsDb)
    {
        if (!IsCurrent(captureGeneration) || !listening || !float.IsFinite(rmsDb))
        {
            return;
        }

        // Providers choose their own RMS range. This is a visual activity proxy, not dBFS.
        double inputLevel = Math.Clamp((rmsDb + 2.0) / 12.0, 0.0, 1.0);
        Publish(SpeechCapturePhase.Listening, inputLevel);
    }

    private void OnRecognitionError(int captureGeneration, SpeechRecognizerError error)
    {
        string message = error switch
        {
            SpeechRecognizerError.Audio => "Android could not record audio. Check microphone routing and other apps using the input.",
            SpeechRecognizerError.InsufficientPermissions => "The speech provider does not have microphone permission. Check the app and provider permissions.",
            SpeechRecognizerError.NoMatch => "Android heard no recognizable speech. Check the fixture, microphone routing and recognition language.",
            SpeechRecognizerError.SpeechTimeout => "Android timed out waiting for speech. Start fixture playback as soon as the harness says Listening.",
            SpeechRecognizerError.Network or SpeechRecognizerError.NetworkTimeout => "The Android speech provider could not reach its recognition service. Check the emulator network connection.",
            SpeechRecognizerError.RecognizerBusy => "The Android speech provider is busy. Wait briefly, then reset and try again.",
            SpeechRecognizerError.Server => "The Android speech provider failed or disconnected. Check that it is installed and configured.",
            _ => "The Android speech provider failed. Check its installation, permissions and network connection."
        };

        if (OperatingSystem.IsAndroidVersionAtLeast(31))
        {
            message = error switch
            {
                SpeechRecognizerError.LanguageNotSupported => "The Android speech provider does not support the selected language.",
                SpeechRecognizerError.LanguageUnavailable => "The selected speech language is not available. Download its model in the speech provider settings.",
                SpeechRecognizerError.ServerDisconnected => "The Android speech provider disconnected. Check that it is installed and configured.",
                SpeechRecognizerError.TooManyRequests => "The Android speech provider rejected too many requests. Wait before starting another run.",
                _ => message
            };
        }

        Finish(captureGeneration, SpeechCapturePhase.Error, $"{message} ({error}, code {(int)error})");
    }

    private void Publish(SpeechCapturePhase phase, double? inputLevel = null, string? message = null)
    {
        if (activeRequest is not null)
        {
            Updated?.Invoke(this, new SpeechCaptureUpdate(activeRequest.RunId, phase, transcript, inputLevel, message));
        }
    }

    private void Finish(int captureGeneration, SpeechCapturePhase phase, string message)
    {
        if (!IsCurrent(captureGeneration))
        {
            return;
        }

        var update = new SpeechCaptureUpdate(activeRequest!.RunId, phase, transcript, Message: message);
        ReleaseCapture();
        Updated?.Invoke(this, update);
    }

    private void ScheduleDeadline(int captureGeneration, TimeSpan delay, string message)
    {
        CancelDeadline();
        deadlineCancellation = new CancellationTokenSource();
        _ = WaitForDeadlineAsync(captureGeneration, delay, message, deadlineCancellation.Token);
    }

    private async Task WaitForDeadlineAsync(int captureGeneration, TimeSpan delay, string message, CancellationToken cancellationToken)
    {
        try
        {
            await Task.Delay(delay, cancellationToken);
            await MainThread.InvokeOnMainThreadAsync(() =>
            {
                if (!cancellationToken.IsCancellationRequested)
                {
                    Finish(captureGeneration, SpeechCapturePhase.Error, message);
                }
            });
        }
        catch (System.OperationCanceledException)
        {
            // Replaced, completed and cancelled runs all invalidate their deadlines.
        }
    }

    private void CancelDeadline()
    {
        deadlineCancellation?.Cancel();
        deadlineCancellation?.Dispose();
        deadlineCancellation = null;
    }

    private void ReleaseCapture()
    {
        // Invalidate callbacks before cancelling the native provider, which may dispatch an error.
        generation++;
        activeRequest = null;
        listening = false;
        processing = false;
        CancelDeadline();

        SpeechRecognizer? previousRecognizer = recognizer;
        RecognitionListener? previousListener = recognitionListener;
        recognizer = null;
        recognitionListener = null;
        try
        {
            previousRecognizer?.Cancel();
        }
        catch (Exception exception)
        {
            System.Diagnostics.Debug.WriteLine($"Speech recognizer cancellation failed: {exception.Message}");
        }

        try
        {
            previousRecognizer?.Destroy();
        }
        catch (Exception exception)
        {
            System.Diagnostics.Debug.WriteLine($"Speech recognizer cleanup failed: {exception.Message}");
        }
        finally
        {
            previousRecognizer?.Dispose();
            previousListener?.Dispose();
        }
    }

    private sealed class RecognitionListener : Java.Lang.Object, IRecognitionListener
    {
        private readonly PlatformSpeechCaptureService service;
        private readonly int captureGeneration;

        public RecognitionListener(PlatformSpeechCaptureService service, int captureGeneration)
        {
            this.service = service;
            this.captureGeneration = captureGeneration;
        }

        public void OnReadyForSpeech(Bundle? parameters) => service.OnReady(captureGeneration);
        public void OnRmsChanged(float rmsdB) => service.OnLevel(captureGeneration, rmsdB);
        public void OnPartialResults(Bundle? partialResults) => service.OnTranscript(captureGeneration, partialResults, false);
        public void OnResults(Bundle? results) => service.OnTranscript(captureGeneration, results, true);
        public void OnError(SpeechRecognizerError error) => service.OnRecognitionError(captureGeneration, error);
        public void OnEndOfSpeech() => service.BeginProcessing(captureGeneration);
        public void OnBeginningOfSpeech() { }
        public void OnBufferReceived(byte[]? buffer) { }
        public void OnEvent(int eventType, Bundle? parameters) { }
    }
}
