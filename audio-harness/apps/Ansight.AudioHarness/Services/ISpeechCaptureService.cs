namespace Ansight.AudioHarness.Services;

public enum SpeechCapturePhase
{
    Listening,
    Processing,
    Completed,
    Error,
    Captured
}

public sealed record SpeechCaptureRequest(string RunId, string Language, bool CaptureOnly = false);

public sealed record SpeechCaptureUpdate(
    string RunId,
    SpeechCapturePhase Phase,
    string Transcript = "",
    double? InputLevel = null,
    string? Message = null,
    string? CaptureFilePath = null);

public interface ISpeechCaptureService
{
    event EventHandler<SpeechCaptureUpdate>? Updated;

    Task StartAsync(SpeechCaptureRequest request);

    Task StopAsync();

    Task CancelAsync();
}
