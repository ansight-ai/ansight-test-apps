using System.Diagnostics;
using System.Runtime.InteropServices;
using Ansight.AudioHarness.Services;
using AVFoundation;
using AudioToolbox;
using Foundation;
using Microsoft.Maui.ApplicationModel;
using Speech;
using UIKit;

namespace Ansight.AudioHarness;

/// <summary>Transcribes the actual microphone stream, including a Simulator's routed host input.</summary>
public sealed class PlatformSpeechCaptureService : ISpeechCaptureService
{
    private CaptureRun? activeRun;

    public event EventHandler<SpeechCaptureUpdate>? Updated;

    public Task StartAsync(SpeechCaptureRequest request) => MainThread.InvokeOnMainThreadAsync(async () =>
    {
        CancelCurrentRun();
        var run = new CaptureRun(request);
        activeRun = run;

        try
        {
            var microphonePermission = await Permissions.RequestAsync<Permissions.Microphone>();
            if (!IsCurrent(run))
                return;
            if (microphonePermission != PermissionStatus.Granted)
                throw new InvalidOperationException("Microphone permission is required. Enable it in Settings and retry.");

            if (!request.CaptureOnly)
            {
                var speechPermission = await Permissions.RequestAsync<Permissions.Speech>();
                if (!IsCurrent(run))
                    return;
                if (speechPermission != PermissionStatus.Granted)
                    throw new InvalidOperationException("Speech recognition permission is required. Enable it in Settings and retry.");

                using var locale = new NSLocale(request.Language);
                run.Recognizer = new SFSpeechRecognizer(locale);
                var availabilityWait = Stopwatch.StartNew();
                while (!run.Recognizer.Available && availabilityWait.Elapsed < TimeSpan.FromSeconds(10))
                {
                    // Yield so Apple's availability callbacks can run while its service initializes.
                    await Task.Delay(TimeSpan.FromMilliseconds(250));
                    if (!IsCurrent(run))
                        return;
                }

                if (!run.Recognizer.Available)
                    throw new InvalidOperationException($"Apple speech recognition is still unavailable for {request.Language} after 10 seconds. Check connectivity and the system's dictation language, then retry.");
            }

            var audioSession = AVAudioSession.SharedInstance();
            if (!audioSession.SetCategory(AVAudioSessionCategory.Record.GetConstant()!, out var categoryError))
                throw new InvalidOperationException(categoryError?.LocalizedDescription ?? "Unable to configure microphone capture.");
            if (!audioSession.SetMode(AVAudioSessionMode.Measurement.GetConstant()!, out var modeError))
                throw new InvalidOperationException(modeError?.LocalizedDescription ?? "Unable to configure the audio measurement mode.");
            if (!audioSession.SetActive(true, out var activationError))
                throw new InvalidOperationException(activationError?.LocalizedDescription ?? "Unable to activate the microphone.");
            run.AudioSessionActive = true;

            run.Engine = new AVAudioEngine();
            run.InputNode = run.Engine.InputNode;
            using var inputFormat = run.InputNode.GetBusOutputFormat(0);
            if (inputFormat.SampleRate <= 0 || inputFormat.ChannelCount == 0)
                throw new InvalidOperationException("No microphone input is available. Select an audio input in Simulator and retry.");

            // Save the same live buffers used for recognition, so a terminal transcript can retain its microphone evidence.
            {
                var capturesDirectory = Path.Combine(FileSystem.AppDataDirectory, "audio-captures");
                Directory.CreateDirectory(capturesDirectory);
                if (!Guid.TryParseExact(request.RunId, "N", out var captureId))
                    throw new InvalidOperationException("A capture run requires a valid unique run ID.");
                run.CaptureFilePath = Path.Combine(capturesDirectory, $"{captureId:N}.wav");
                using var captureUrl = NSUrl.FromFilename(run.CaptureFilePath);
                var settings = new AudioSettings
                {
                    Format = AudioFormatType.LinearPCM,
                    SampleRate = inputFormat.SampleRate,
                    NumberChannels = checked((int)inputFormat.ChannelCount),
                    LinearPcmBitDepth = 16,
                    LinearPcmBigEndian = false,
                    LinearPcmFloat = false,
                    LinearPcmNonInterleaved = false
                };
                run.CaptureWriter = new AVAudioFile(captureUrl, settings, inputFormat.CommonFormat,
                    inputFormat.Interleaved, out var fileError);
                if (fileError is not null)
                    throw new InvalidOperationException($"Could not create the microphone recording: {fileError.LocalizedDescription}");
            }
            if (!request.CaptureOnly)
            {
                run.AudioRequest = new SFSpeechAudioBufferRecognitionRequest
                {
                    ShouldReportPartialResults = true,
                    TaskHint = SFSpeechRecognitionTaskHint.Dictation
                };
                run.RecognitionTask = run.Recognizer!.GetRecognitionTask(run.AudioRequest, (result, error) =>
                {
                    // Copy native callback values before handing them to the UI thread.
                    var transcript = result?.BestTranscription.FormattedString;
                    var isFinal = result?.Final == true;
                    var errorMessage = error?.LocalizedDescription;
                    MainThread.BeginInvokeOnMainThread(() => HandleRecognition(run, transcript, isFinal, errorMessage));
                });
            }

            run.BackgroundObserver = UIApplication.Notifications.ObserveDidEnterBackground((sender, args) =>
                MainThread.BeginInvokeOnMainThread(() => Fail(run, "Capture stopped because the app entered the background. Start a new run.")));
            run.InterruptionObserver = AVAudioSession.Notifications.ObserveInterruption((sender, args) =>
                MainThread.BeginInvokeOnMainThread(() => Fail(run, "The audio session was interrupted. Start a new run.")));

            run.AcceptAudio = true;
            run.InputNode.InstallTapOnBus(0, 1024, inputFormat, (buffer, time) => ReceiveAudio(run, buffer));
            run.TapInstalled = true;
            run.Engine.Prepare();
            if (!run.Engine.StartAndReturnError(out var startError))
                throw new InvalidOperationException(startError?.LocalizedDescription ?? "The audio engine could not start.");

            run.Ready = true;
            Publish(run, SpeechCapturePhase.Listening, message: $"Microphone ready · {inputFormat.SampleRate:0} Hz · {inputFormat.ChannelCount} channel(s)");
        }
        catch (Exception exception)
        {
            Fail(run, exception.Message);
        }
    });

    public Task StopAsync() => MainThread.InvokeOnMainThreadAsync(() =>
    {
        var run = activeRun;
        if (run is null || run.Stopping)
            return;

        // Stop can also cancel a pending permission request before native capture is ready.
        if (!run.Ready)
        {
            CancelCurrentRun();
            return;
        }

        try
        {
            run.Stopping = true;
            StopInput(run);
            if (run.Request.CaptureOnly)
            {
                lock (run.AudioGate)
                {
                    if (run.CaptureError is not null)
                        throw new InvalidOperationException(run.CaptureError);
                    run.CaptureWriter?.Dispose();
                    run.CaptureWriter = null;
                    if (run.CapturedFrames == 0 || !File.Exists(run.CaptureFilePath))
                        throw new InvalidOperationException("The microphone did not produce any audio buffers.");
                    run.CaptureFinalized = true;
                }
                activeRun = null;
                Release(run);
                Publish(run, SpeechCapturePhase.Captured, message: "Microphone audio saved. Transcription was not requested.",
                    captureFilePath: run.CaptureFilePath);
                return;
            }
            run.AudioRequest?.EndAudio();
            Publish(run, SpeechCapturePhase.Processing, message: "Microphone stopped. Waiting for Apple's final transcript…");
            _ = WatchFinalizationAsync(run);
        }
        catch (Exception exception)
        {
            Fail(run, exception.Message);
        }
    });

    public Task CancelAsync() => MainThread.InvokeOnMainThreadAsync(CancelCurrentRun);

    private bool IsCurrent(CaptureRun run) => ReferenceEquals(activeRun, run);

    private void ReceiveAudio(CaptureRun run, AVAudioPcmBuffer buffer)
    {
        try
        {
            lock (run.AudioGate)
            {
                if (!run.AcceptAudio)
                    return;

                // Only live microphone PCM is supplied; test assertions never enter this request.
                run.AudioRequest?.Append(buffer);
                if (run.CaptureWriter is not null)
                {
                    if (!run.CaptureWriter.WriteFromBuffer(buffer, out var writeError))
                        throw new InvalidOperationException(writeError?.LocalizedDescription ?? "Could not write microphone samples.");
                    run.CapturedFrames += buffer.FrameLength;
                }

                var now = Stopwatch.GetTimestamp();
                if (Stopwatch.GetElapsedTime(run.LastLevelTimestamp, now).TotalMilliseconds < 100)
                    return;

                run.LastLevelTimestamp = now;
                var level = MeasureInputLevel(buffer);
                MainThread.BeginInvokeOnMainThread(() =>
                {
                    if (IsCurrent(run) && run.Ready && !run.Stopping)
                        Publish(run, SpeechCapturePhase.Listening, level);
                });
            }
        }
        catch (Exception exception)
        {
            lock (run.AudioGate)
            {
                run.CaptureError = exception.Message;
                run.AcceptAudio = false;
            }
            MainThread.BeginInvokeOnMainThread(() => Fail(run, $"Audio capture failed: {exception.Message}"));
        }
    }

    private static double? MeasureInputLevel(AVAudioPcmBuffer buffer)
    {
        if (buffer.FloatChannelData == IntPtr.Zero || buffer.FrameLength == 0)
            return null;

        var channel = Marshal.ReadIntPtr(buffer.FloatChannelData);
        if (channel == IntPtr.Zero)
            return null;

        double squares = 0;
        var frameCount = checked((int)buffer.FrameLength);
        var stride = checked((int)buffer.Stride);
        for (var frame = 0; frame < frameCount; frame++)
        {
            var sampleBits = Marshal.ReadInt32(channel, checked(frame * stride * sizeof(float)));
            var sample = BitConverter.Int32BitsToSingle(sampleBits);
            squares += sample * sample;
        }

        return Math.Clamp(Math.Sqrt(squares / frameCount), 0, 1);
    }

    private void HandleRecognition(CaptureRun run, string? transcript, bool isFinal, string? errorMessage)
    {
        if (!IsCurrent(run))
            return;

        if (transcript is not null)
            run.Transcript = transcript;

        if (isFinal)
        {
            var capturePath = FinalizeRecording(run);
            activeRun = null;
            Release(run);
            Publish(run, SpeechCapturePhase.Completed, message: "Apple returned the final transcript.", captureFilePath: capturePath);
        }
        else if (errorMessage is not null)
        {
            Fail(run, $"Speech recognition failed: {errorMessage}");
        }
        else if (transcript is not null && run.Ready)
        {
            Publish(run, run.Stopping ? SpeechCapturePhase.Processing : SpeechCapturePhase.Listening);
        }
    }

    private async Task WatchFinalizationAsync(CaptureRun run)
    {
        try
        {
            await Task.Delay(TimeSpan.FromSeconds(10), run.FinalizationCancellation.Token);
            await MainThread.InvokeOnMainThreadAsync(() => Fail(run,
                "Apple did not return a final transcript within 10 seconds. Check speech service availability and retry."));
        }
        catch (OperationCanceledException)
        {
            // A final result, cancellation, or a new run already released this session.
        }
    }

    private void Fail(CaptureRun run, string message)
    {
        if (!IsCurrent(run))
            return;

        var capturePath = FinalizeRecording(run);
        activeRun = null;
        Release(run);
        Publish(run, SpeechCapturePhase.Error, message: message, captureFilePath: capturePath);
    }

    private static string? FinalizeRecording(CaptureRun run)
    {
        StopInput(run);
        lock (run.AudioGate)
        {
            run.CaptureWriter?.Dispose();
            run.CaptureWriter = null;
            if (run.CaptureError is not null || run.CapturedFrames == 0 || !File.Exists(run.CaptureFilePath)) return null;
            run.CaptureFinalized = true;
            return run.CaptureFilePath;
        }
    }

    private void CancelCurrentRun()
    {
        var run = activeRun;
        activeRun = null;
        if (run is not null)
            Release(run);
    }

    private static void StopInput(CaptureRun run)
    {
        // Do not hold AudioGate while stopping the engine: its render callback also takes it.
        lock (run.AudioGate)
            run.AcceptAudio = false;

        run.Engine?.Stop();
        if (run.TapInstalled)
        {
            run.InputNode?.RemoveTapOnBus(0);
            run.TapInstalled = false;
        }

        if (run.AudioSessionActive)
        {
            AVAudioSession.SharedInstance().SetActive(false, AVAudioSessionSetActiveOptions.NotifyOthersOnDeactivation, out var error);
            error?.Dispose();
            run.AudioSessionActive = false;
        }
    }

    private static void Release(CaptureRun run)
    {
        run.FinalizationCancellation.Cancel();
        run.BackgroundObserver?.Dispose();
        run.BackgroundObserver = null;
        run.InterruptionObserver?.Dispose();
        run.InterruptionObserver = null;
        StopInput(run);
        lock (run.AudioGate)
        {
            run.CaptureWriter?.Dispose();
            run.CaptureWriter = null;
        }
        if (!run.CaptureFinalized && run.CaptureFilePath is not null)
        {
            try { File.Delete(run.CaptureFilePath); }
            catch (Exception exception) { Debug.WriteLine($"Could not remove incomplete microphone recording: {exception.Message}"); }
        }
        run.RecognitionTask?.Cancel();
        run.RecognitionTask?.Dispose();
        run.RecognitionTask = null;
        run.AudioRequest?.Dispose();
        run.AudioRequest = null;
        run.InputNode?.Dispose();
        run.InputNode = null;
        run.Engine?.Dispose();
        run.Engine = null;
        run.Recognizer?.Dispose();
        run.Recognizer = null;
        run.FinalizationCancellation.Dispose();
    }

    private void Publish(CaptureRun run, SpeechCapturePhase phase, double? level = null, string? message = null,
        string? captureFilePath = null) =>
        Updated?.Invoke(this, new SpeechCaptureUpdate(run.Request.RunId, phase, run.Transcript, level, message, captureFilePath));

    private sealed class CaptureRun(SpeechCaptureRequest request)
    {
        public SpeechCaptureRequest Request { get; } = request;
        public object AudioGate { get; } = new();
        public CancellationTokenSource FinalizationCancellation { get; } = new();
        public SFSpeechRecognizer? Recognizer { get; set; }
        public SFSpeechAudioBufferRecognitionRequest? AudioRequest { get; set; }
        public SFSpeechRecognitionTask? RecognitionTask { get; set; }
        public AVAudioFile? CaptureWriter { get; set; }
        public string? CaptureFilePath { get; set; }
        public string? CaptureError { get; set; }
        public long CapturedFrames { get; set; }
        public bool CaptureFinalized { get; set; }
        public AVAudioEngine? Engine { get; set; }
        public AVAudioInputNode? InputNode { get; set; }
        public NSObject? BackgroundObserver { get; set; }
        public NSObject? InterruptionObserver { get; set; }
        public string Transcript { get; set; } = "";
        public bool AudioSessionActive { get; set; }
        public bool TapInstalled { get; set; }
        public bool AcceptAudio { get; set; }
        public bool Ready { get; set; }
        public bool Stopping { get; set; }
        public long LastLevelTimestamp { get; set; }
    }
}
