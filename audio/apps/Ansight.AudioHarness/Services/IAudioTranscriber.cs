namespace Ansight.AudioHarness.Services;

public sealed record AudioTranscriptionInfo(
    string Provider,
    string Model,
    string ModelSha256,
    string SourceAudioSha256,
    string TranscriptionAudioSha256,
    int SampleRate,
    int Channels,
    double ProcessingMilliseconds);

public sealed record AudioTranscriptionResult(string Text, AudioTranscriptionInfo Info);

public interface IAudioTranscriber
{
    Task PrepareAsync(CancellationToken cancellationToken);

    Task<AudioTranscriptionResult> TranscribeAsync(
        string microphoneWavePath, string language, CancellationToken cancellationToken);
}
