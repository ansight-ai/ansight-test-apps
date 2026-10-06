namespace Ansight.AudioHarness.Core;

public enum TranscriptValidationState
{
    Pending,
    Passed,
    Failed
}

public sealed record TranscriptValidation(
    TranscriptValidationState State,
    string NormalizedExpected,
    string NormalizedActual,
    string Reason);
