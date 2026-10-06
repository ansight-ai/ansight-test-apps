namespace Ansight.AudioHarness.Services;

public enum SpeechCapturePhase
{
    Preparing,
    Listening,
    Processing,
    Completed,
    Error,
    Captured
}

public enum TranscriptionProvider
{
    Native,
    Whisper
}

public sealed record SpeechCaptureRequest(
    string RunId, string Language, bool CaptureOnly = false,
    TranscriptionProvider Provider = TranscriptionProvider.Native);

public sealed record SpeechCaptureUpdate(
    string RunId,
    SpeechCapturePhase Phase,
    string Transcript = "",
    double? InputLevel = null,
    string? Message = null,
    string? CaptureFilePath = null,
    AudioTranscriptionInfo? Transcription = null);

public interface ISpeechCaptureService
{
    event EventHandler<SpeechCaptureUpdate>? Updated;

    Task StartAsync(SpeechCaptureRequest request);

    Task StopAsync();

    Task CancelAsync();
}
