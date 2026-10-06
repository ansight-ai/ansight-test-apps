using System.Buffers.Binary;
using System.Security.Cryptography;
using Ansight.AudioHarness.Core;

namespace Ansight.AudioHarness.Services;

internal sealed record NormalizedMicrophoneWave(byte[] Bytes, string SourceSha256, string Sha256);

/// <summary>Converts the entire real microphone recording to canonical mono 16 kHz PCM16.</summary>
internal static class MicrophoneWaveNormalizer
{
    public const int SampleRate = 16000;
    private const int PhaseCount = 1024;
    private const long MaximumBytes = 32 * 1024 * 1024;

    public static async Task<NormalizedMicrophoneWave> ReadAsync(string path, CancellationToken cancellationToken)
    {
        var fullPath = Path.GetFullPath(path);
        var captureRoot = Path.Combine(FileSystem.AppDataDirectory, "audio-captures") + Path.DirectorySeparatorChar;
        if (!fullPath.StartsWith(captureRoot, StringComparison.Ordinal)
            || !Guid.TryParseExact(Path.GetFileNameWithoutExtension(fullPath), "N", out _))
            throw new InvalidDataException("Transcription requires this run's actual microphone recording.");
        var length = new FileInfo(fullPath).Length;
        if (length is < 44 or > MaximumBytes) throw new InvalidDataException("The microphone WAV has an invalid size.");
        var bytes = await File.ReadAllBytesAsync(fullPath, cancellationToken).ConfigureAwait(false);
        if (bytes.LongLength != length) throw new InvalidDataException("The microphone recording changed before transcription.");
        return await Task.Run(() => Normalize(bytes, cancellationToken), cancellationToken).ConfigureAwait(false);
    }

    private static NormalizedMicrophoneWave Normalize(byte[] source, CancellationToken cancellationToken)
    {
        // The shared inspector validates RIFF size, padded chunks, PCM16 format and frame alignment.
        var info = MicrophoneWaveInspector.Inspect(source);
        if (info.DurationSeconds > 35) throw new InvalidDataException("The microphone recording exceeds the 30-second harness limit plus stop latency.");
        if (info.NonSilentFrameCount == 0) throw new InvalidDataException("No audible microphone samples were recorded for transcription.");
        cancellationToken.ThrowIfCancellationRequested();
        var pcm = FindPcm(source);
        var mono = new double[checked((int)info.FrameCount)];
        for (var frame = 0; frame < mono.Length; frame++)
        {
            if ((frame & 4095) == 0) cancellationToken.ThrowIfCancellationRequested();
            double sum = 0;
            for (var channel = 0; channel < info.Channels; channel++)
                sum += BinaryPrimitives.ReadInt16LittleEndian(pcm[((frame * info.Channels + channel) * 2)..]);
            mono[frame] = sum / (32768d * info.Channels);
        }

        var samples = info.SampleRate == SampleRate ? mono : Resample(mono, info.SampleRate, cancellationToken);
        if (samples.Length == 0) throw new InvalidDataException("The microphone recording is too short to transcribe.");
        var output = WriteWave(samples, cancellationToken);
        return new(output, info.Sha256!, Convert.ToHexString(SHA256.HashData(output)).ToLowerInvariant());
    }

    private static ReadOnlySpan<byte> FindPcm(ReadOnlySpan<byte> wave)
    {
        for (var offset = 12; offset < wave.Length;)
        {
            var length = checked((int)BinaryPrimitives.ReadUInt32LittleEndian(wave[(offset + 4)..]));
            if (wave.Slice(offset, 4).SequenceEqual("data"u8)) return wave.Slice(offset + 8, length);
            offset = checked(offset + 8 + length + (length & 1));
        }
        throw new InvalidDataException("The microphone WAV has no PCM data chunk.");
    }

    private static double[] Resample(double[] input, int sourceRate, CancellationToken cancellationToken)
    {
        var ratio = Math.Min(1d, (double)SampleRate / sourceRate);
        var halfWidth = (int)Math.Ceiling(16 / ratio);
        var cutoff = 0.47 * ratio;
        // A Blackman-windowed sinc suppresses frequencies above the destination Nyquist limit.
        // Phase quantization is <1/1024 of an input sample; kernels are reused for long recordings.
        var kernels = new double[PhaseCount][];
        var output = new double[checked((int)((long)input.Length * SampleRate / sourceRate))];
        for (var frame = 0; frame < output.Length; frame++)
        {
            if ((frame & 1023) == 0) cancellationToken.ThrowIfCancellationRequested();
            var positionNumerator = (long)frame * sourceRate;
            var center = (int)(positionNumerator / SampleRate);
            var phase = (int)((positionNumerator % SampleRate) * PhaseCount / SampleRate);
            var kernel = kernels[phase] ??= CreateKernel(halfWidth, cutoff, (double)phase / PhaseCount);
            double sample = 0;
            for (var index = 0; index < kernel.Length; index++)
            {
                var inputIndex = center + index - halfWidth;
                if (inputIndex >= 0 && inputIndex < input.Length) sample += input[inputIndex] * kernel[index];
            }
            output[frame] = sample;
        }
        return output;
    }

    private static double[] CreateKernel(int halfWidth, double cutoff, double phase)
    {
        var kernel = new double[halfWidth * 2 + 1];
        double total = 0;
        for (var index = 0; index < kernel.Length; index++)
        {
            var distance = index - halfWidth - phase;
            var normalizedDistance = distance / halfWidth;
            if (Math.Abs(normalizedDistance) >= 1) continue;
            var sinc = Math.Abs(distance) < 1e-12 ? 2 * cutoff : Math.Sin(2 * Math.PI * cutoff * distance) / (Math.PI * distance);
            var window = 0.42 + 0.5 * Math.Cos(Math.PI * normalizedDistance) + 0.08 * Math.Cos(2 * Math.PI * normalizedDistance);
            kernel[index] = sinc * window;
            total += kernel[index];
        }
        for (var index = 0; index < kernel.Length; index++) kernel[index] /= total;
        return kernel;
    }

    private static byte[] WriteWave(double[] samples, CancellationToken cancellationToken)
    {
        using var output = new MemoryStream(checked(44 + samples.Length * 2));
        using var writer = new BinaryWriter(output, System.Text.Encoding.ASCII, leaveOpen: true);
        writer.Write("RIFF"u8);
        writer.Write(checked(36 + samples.Length * 2));
        writer.Write("WAVEfmt "u8);
        writer.Write(16);
        writer.Write((short)1);
        writer.Write((short)1);
        writer.Write(SampleRate);
        writer.Write(SampleRate * 2);
        writer.Write((short)2);
        writer.Write((short)16);
        writer.Write("data"u8);
        writer.Write(checked(samples.Length * 2));
        for (var index = 0; index < samples.Length; index++)
        {
            if ((index & 4095) == 0) cancellationToken.ThrowIfCancellationRequested();
            writer.Write((short)Math.Clamp(Math.Round(samples[index] * 32768), short.MinValue, short.MaxValue));
        }
        writer.Flush();
        return output.ToArray();
    }
}
