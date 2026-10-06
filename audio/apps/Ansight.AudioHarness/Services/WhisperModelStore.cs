using System.Security.Cryptography;

namespace Ansight.AudioHarness.Services;

/// <summary>Materializes the prepared package asset without making network requests.</summary>
internal sealed class WhisperModelStore
{
    public const string ModelName = "base.en";
    public const string FileName = "ggml-base.en.bin";
    public const string Sha256 = "a03779c86df3323075f5e796cb2ce5029f00ec8869eee3fdfb897afe36c6d002";
    public const long SizeBytes = 147964211;

    public async Task<string> PrepareAsync(CancellationToken cancellationToken)
    {
        var directory = Path.Combine(FileSystem.AppDataDirectory, "whisper-models", Sha256);
        Directory.CreateDirectory(directory);
        var path = Path.Combine(directory, FileName);
        if (await IsValidAsync(path, cancellationToken).ConfigureAwait(false)) return path;

        var temporaryPath = path + ".partial";
        try
        {
            await using (var source = await FileSystem.OpenAppPackageFileAsync($"models/{FileName}").ConfigureAwait(false))
            await using (var destination = new FileStream(temporaryPath, FileMode.Create, FileAccess.Write, FileShare.None, 131072, useAsync: true))
            {
                var buffer = new byte[131072];
                long copied = 0;
                int read;
                while ((read = await source.ReadAsync(buffer, cancellationToken).ConfigureAwait(false)) > 0)
                {
                    copied += read;
                    if (copied > SizeBytes) throw new InvalidDataException("The bundled Whisper model exceeds its pinned size.");
                    await destination.WriteAsync(buffer.AsMemory(0, read), cancellationToken).ConfigureAwait(false);
                }
            }
            if (!await IsValidAsync(temporaryPath, cancellationToken).ConfigureAwait(false))
                throw new InvalidDataException("The bundled Whisper model does not match the pinned SHA-256. Run scripts/prepare-whisper-model.py and rebuild the app.");
            cancellationToken.ThrowIfCancellationRequested();
            File.Move(temporaryPath, path, overwrite: true);
            return path;
        }
        catch (FileNotFoundException error)
        {
            throw new InvalidOperationException("The offline Whisper model is missing from the app. Run scripts/prepare-whisper-model.py before building.", error);
        }
        finally
        {
            if (File.Exists(temporaryPath)) File.Delete(temporaryPath);
        }
    }

    private static async Task<bool> IsValidAsync(string path, CancellationToken cancellationToken)
    {
        if (!File.Exists(path) || new FileInfo(path).Length != SizeBytes) return false;
        await using var file = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read, 131072, useAsync: true);
        var hash = await SHA256.HashDataAsync(file, cancellationToken).ConfigureAwait(false);
        return Convert.ToHexString(hash).Equals(Sha256, StringComparison.OrdinalIgnoreCase);
    }
}
