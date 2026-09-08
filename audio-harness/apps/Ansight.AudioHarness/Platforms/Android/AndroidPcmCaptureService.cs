using System.Diagnostics;
using Android.Media;

namespace Ansight.AudioHarness.Services;

/// <summary>Records the real Android microphone independently of the installed speech provider.</summary>
internal sealed class AndroidPcmCaptureService : ISpeechCaptureService
{
    private const int SampleRate = 16000;
    private CaptureRun? activeRun;
    public event EventHandler<SpeechCaptureUpdate>? Updated;

    public async Task StartAsync(SpeechCaptureRequest request)
    {
        await CancelAsync();
        var run = new CaptureRun(request);
        activeRun = run;
        try
        {
            if (await Permissions.RequestAsync<Permissions.Microphone>() != PermissionStatus.Granted)
                throw new InvalidOperationException("Microphone permission was denied. Enable it in Android Settings and retry.");
            if (!ReferenceEquals(activeRun, run)) return;
            if (!Guid.TryParseExact(request.RunId, "N", out var id)) throw new InvalidOperationException("A recording requires a unique run ID.");
            var directory = Path.Combine(FileSystem.AppDataDirectory, "audio-captures");
            Directory.CreateDirectory(directory);
            run.Path = Path.Combine(directory, $"{id:N}.wav");
            var minimum = AudioRecord.GetMinBufferSize(SampleRate, ChannelIn.Mono, Encoding.Pcm16bit);
            if (minimum <= 0) throw new InvalidOperationException("The Android microphone does not support 16 kHz mono PCM.");
            using var formatBuilder = new AudioFormat.Builder();
            formatBuilder.SetSampleRate(SampleRate);
            // Android accepts an integer input mask here; the .NET binding labels it ChannelOut.
            formatBuilder.SetChannelMask((ChannelOut)(int)ChannelIn.Mono);
            formatBuilder.SetEncoding(Encoding.Pcm16bit);
            using var format = formatBuilder.Build() ?? throw new InvalidOperationException("Android could not create the microphone format.");
            using var recorderBuilder = new AudioRecord.Builder();
            recorderBuilder.SetAudioSource(AudioSource.VoiceRecognition);
            recorderBuilder.SetAudioFormat(format);
            recorderBuilder.SetBufferSizeInBytes(Math.Max(minimum * 2, 4096));
            run.Recorder = recorderBuilder.Build() ?? throw new InvalidOperationException("Android could not create microphone recording.");
            if (run.Recorder.State != State.Initialized) throw new InvalidOperationException("Android could not initialize microphone recording.");
            run.Recorder.StartRecording();
            if (run.Recorder.RecordingState != RecordState.Recording) throw new InvalidOperationException("Android did not start the microphone.");
            run.Pump = Task.Run(() => RecordAsync(run));
            Updated?.Invoke(this, new(request.RunId, SpeechCapturePhase.Listening, Message: "Microphone ready · 16000 Hz · mono PCM16"));
        }
        catch (Exception error)
        {
            if (!ReferenceEquals(activeRun, run)) return;
            activeRun = null;
            ReleaseRecorder(run.Recorder);
            run.Cancellation.Dispose();
            Updated?.Invoke(this, new(request.RunId, SpeechCapturePhase.Error, Message: error.Message));
        }
    }

    public async Task StopAsync()
    {
        var run = activeRun;
        if (run is null) return;
        run.Cancellation.Cancel();
        if (run.Pump is not null) await run.Pump;
    }

    public async Task CancelAsync()
    {
        var run = activeRun;
        activeRun = null;
        if (run is null) return;
        run.Cancellation.Cancel();
        if (run.Pump is not null) await run.Pump;
        else run.Cancellation.Dispose();
    }

    private async Task RecordAsync(CaptureRun run)
    {
        string? errorMessage = null;
        long frames = 0;
        try
        {
            using var output = new FileStream(run.Path!, FileMode.CreateNew, FileAccess.ReadWrite, FileShare.None);
            WriteHeader(output, 0);
            var samples = new short[1024];
            var bytes = new byte[samples.Length * 2];
            var levelClock = Stopwatch.StartNew();
            while (!run.Cancellation.IsCancellationRequested && frames < SampleRate * 30L)
            {
                var read = run.Recorder!.Read(samples, 0, (int)Math.Min(samples.Length, SampleRate * 30L - frames), (int)AudioRecordReadOptions.NonBlocking);
                if (read < 0) throw new IOException($"Android microphone read failed with code {read}.");
                if (read == 0)
                {
                    await Task.Delay(5, run.Cancellation.Token);
                    continue;
                }
                Buffer.BlockCopy(samples, 0, bytes, 0, read * 2);
                output.Write(bytes, 0, read * 2);
                frames += read;
                if (levelClock.ElapsedMilliseconds >= 100)
                {
                    double squares = 0;
                    for (var index = 0; index < read; index++) squares += Math.Pow(samples[index] / 32768d, 2);
                    var level = Math.Sqrt(squares / read);
                    MainThread.BeginInvokeOnMainThread(() =>
                    {
                        if (ReferenceEquals(activeRun, run)) Updated?.Invoke(this, new(run.Request.RunId, SpeechCapturePhase.Listening, InputLevel: level));
                    });
                    levelClock.Restart();
                }
            }
            WriteHeader(output, frames * 2);
        }
        catch (OperationCanceledException) when (run.Cancellation.IsCancellationRequested)
        {
            // Nonblocking capture stops promptly; finalize the already-written PCM below.
            try
            {
                if (frames > 0 && File.Exists(run.Path))
                {
                    using var output = new FileStream(run.Path, FileMode.Open, FileAccess.Write, FileShare.None);
                    WriteHeader(output, frames * 2);
                }
            }
            catch (Exception error) { errorMessage = error.Message; }
        }
        catch (Exception error) { errorMessage = error.Message; }
        finally
        {
            var cleanupError = ReleaseRecorder(run.Recorder);
            errorMessage ??= cleanupError;
        }
        await MainThread.InvokeOnMainThreadAsync(() =>
        {
            run.Cancellation.Dispose();
            if (!ReferenceEquals(activeRun, run))
            {
                DeleteIncompleteCapture(run.Path);
                return;
            }
            activeRun = null;
            if (errorMessage is not null || frames == 0)
            {
                DeleteIncompleteCapture(run.Path);
                Updated?.Invoke(this, new(run.Request.RunId, SpeechCapturePhase.Error, Message: errorMessage ?? "The microphone produced no PCM frames."));
            }
            else
            {
                Updated?.Invoke(this, new(run.Request.RunId, SpeechCapturePhase.Captured,
                    Message: "Microphone audio saved. Transcription was not requested.", CaptureFilePath: run.Path));
            }
        });
    }

    private static string? ReleaseRecorder(AudioRecord? recorder)
    {
        if (recorder is null) return null;
        string? message = null;
        try { recorder.Stop(); }
        catch (Exception error) { message = error.Message; }
        try { recorder.Release(); }
        catch (Exception error) { message ??= error.Message; }
        try { recorder.Dispose(); }
        catch (Exception error) { message ??= error.Message; }
        return message;
    }

    private static void DeleteIncompleteCapture(string? path)
    {
        if (path is null) return;
        try { File.Delete(path); }
        catch (IOException) { /* Incomplete files are never exposed as run artifacts. */ }
        catch (UnauthorizedAccessException) { /* Keep native cleanup failures from suppressing the terminal result. */ }
    }

    private static void WriteHeader(System.IO.Stream output, long pcmBytes)
    {
        output.Position = 0;
        using var writer = new BinaryWriter(output, System.Text.Encoding.ASCII, leaveOpen: true);
        writer.Write("RIFF"u8);
        writer.Write(checked((int)pcmBytes + 36));
        writer.Write("WAVEfmt "u8);
        writer.Write(16);
        writer.Write((short)1);
        writer.Write((short)1);
        writer.Write(SampleRate);
        writer.Write(SampleRate * 2);
        writer.Write((short)2);
        writer.Write((short)16);
        writer.Write("data"u8);
        writer.Write(checked((int)pcmBytes));
    }

    private sealed class CaptureRun(SpeechCaptureRequest request)
    {
        public SpeechCaptureRequest Request { get; } = request;
        public CancellationTokenSource Cancellation { get; } = new();
        public AudioRecord? Recorder { get; set; }
        public string? Path { get; set; }
        public Task? Pump { get; set; }
    }
}
