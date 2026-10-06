namespace Ansight.AudioHarness.Core;

public sealed record MicrophoneCaptureInfo(
    bool Available,
    string? Reason = null,
    string? Sha256 = null,
    long FileBytes = 0,
    int SampleRate = 0,
    int Channels = 0,
    int BitsPerSample = 0,
    long FrameCount = 0,
    double DurationSeconds = 0,
    double PeakAmplitude = 0,
    double RmsAmplitude = 0,
    long NonSilentFrameCount = 0);
