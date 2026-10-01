namespace BoulderCaptureSpike;

internal static class SpikeDiagnostics
{
    public static string DotNetLogPath => Path.Combine(FileSystem.AppDataDirectory, "dotnet-diagnostics.log");

    public static void Record(string message)
    {
        try
        {
            File.AppendAllText(DotNetLogPath, $"{DateTimeOffset.UtcNow:O} {message}{Environment.NewLine}");
        }
        catch
        {
            // Diagnostics must never cause a second failure during error handling.
        }
    }

    public static void Record(Exception error, string operation) => Record($"{operation}: {error}");
}
