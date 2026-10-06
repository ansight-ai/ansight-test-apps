using System.Diagnostics;
using System.Text;
using Whisper.net;
using Whisper.net.LibraryLoader;

namespace Ansight.AudioHarness.Services;

/// <summary>Offline CPU transcription of finalized microphone files using the bundled base.en model.</summary>
public sealed class WhisperAudioTranscriber : IAudioTranscriber, IAsyncDisposable
{
    private readonly SemaphoreSlim operationGate = new(1, 1);
    private readonly WhisperModelStore modelStore = new();
    private WhisperFactory? factory;
    private bool disposed;

    public async Task PrepareAsync(CancellationToken cancellationToken)
    {
        await operationGate.WaitAsync(cancellationToken).ConfigureAwait(false);
        try { await PrepareCoreAsync(cancellationToken).ConfigureAwait(false); }
        finally { operationGate.Release(); }
    }

    public async Task<AudioTranscriptionResult> TranscribeAsync(string microphoneWavePath, string language, CancellationToken cancellationToken)
    {
        if (!language.Equals("en", StringComparison.OrdinalIgnoreCase) && !language.StartsWith("en-", StringComparison.OrdinalIgnoreCase))
            throw new NotSupportedException("The bundled base.en model supports English transcription only.");
        await operationGate.WaitAsync(cancellationToken).ConfigureAwait(false);
        try
        {
            await PrepareCoreAsync(cancellationToken).ConfigureAwait(false);
            using var deadline = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
            deadline.CancelAfter(TimeSpan.FromSeconds(60));
            try
            {
                return await Task.Run(async () =>
                {
                    var clock = Stopwatch.StartNew();
                    var audio = await MicrophoneWaveNormalizer.ReadAsync(microphoneWavePath, deadline.Token).ConfigureAwait(false);
                    // A fresh processor and no-context mode prevent prior runs from influencing this result.
                    await using var processor = factory!.CreateBuilder()
                        .WithLanguage("en")
                        .WithThreads(Math.Clamp(Environment.ProcessorCount, 1, 4))
                        .WithNoContext()
                        .WithTemperature(0)
                        .WithTemperatureInc(0)
                        .Build();
                    using var wave = new MemoryStream(audio.Bytes, writable: false);
                    var transcript = new StringBuilder();
                    await foreach (var segment in processor.ProcessAsync(wave, deadline.Token).ConfigureAwait(false))
                    {
                        var text = segment.Text.Trim();
                        if (text.Length == 0) continue;
                        if (transcript.Length > 0) transcript.Append(' ');
                        transcript.Append(text);
                        if (transcript.Length > 32768) throw new InvalidDataException("Whisper returned more text than a bounded harness recording can contain.");
                    }
                    deadline.Token.ThrowIfCancellationRequested();
                    if (transcript.Length == 0) throw new InvalidOperationException("Whisper did not recognize speech in the microphone recording.");
                    clock.Stop();
                    return new AudioTranscriptionResult(transcript.ToString(), new AudioTranscriptionInfo(
                        "whisper.net", WhisperModelStore.ModelName, WhisperModelStore.Sha256,
                        audio.SourceSha256, audio.Sha256, MicrophoneWaveNormalizer.SampleRate, 1, clock.Elapsed.TotalMilliseconds));
                }, deadline.Token).ConfigureAwait(false);
            }
            catch (OperationCanceledException error) when (!cancellationToken.IsCancellationRequested && deadline.IsCancellationRequested)
            {
                throw new TimeoutException("Offline Whisper transcription exceeded its 60-second processing limit.", error);
            }
        }
        finally { operationGate.Release(); }
    }

    private async Task PrepareCoreAsync(CancellationToken cancellationToken)
    {
        ObjectDisposedException.ThrowIf(disposed, this);
        cancellationToken.ThrowIfCancellationRequested();
        if (factory is not null) return;
        var modelPath = await modelStore.PrepareAsync(cancellationToken).ConfigureAwait(false);
        // Model initialization is native and synchronous. Keep it off the UI thread and
        // await its completion before accepting cancellation or releasing the shared factory.
        var prepared = await Task.Run(() =>
        {
            RuntimeOptions.RuntimeLibraryOrder = [RuntimeLibrary.Cpu];
            var loaded = WhisperFactory.FromPath(modelPath, new WhisperFactoryOptions { UseGpu = false, DelayInitialization = false });
            try
            {
                _ = loaded.CreateBuilder(); // Validate the native context before opening the microphone.
                return loaded;
            }
            catch
            {
                loaded.Dispose();
                throw;
            }
        }, cancellationToken).ConfigureAwait(false);
        if (cancellationToken.IsCancellationRequested)
        {
            prepared.Dispose();
            cancellationToken.ThrowIfCancellationRequested();
        }
        factory = prepared;
    }

    public async ValueTask DisposeAsync()
    {
        await operationGate.WaitAsync().ConfigureAwait(false);
        try
        {
            if (disposed) return;
            disposed = true;
            factory?.Dispose();
            factory = null;
        }
        finally { operationGate.Release(); }
    }
}
