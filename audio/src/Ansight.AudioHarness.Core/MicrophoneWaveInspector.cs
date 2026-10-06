using System.Buffers.Binary;
using System.Security.Cryptography;

namespace Ansight.AudioHarness.Core;

/// <summary>Measures the actual finalized microphone file, without using the injected fixture or expected words.</summary>
public static class MicrophoneWaveInspector
{
    public static MicrophoneCaptureInfo Inspect(byte[] bytes)
    {
        ReadOnlySpan<byte> wave = bytes;
        if (wave.Length < 44 || !wave[..4].SequenceEqual("RIFF"u8) || !wave.Slice(8, 4).SequenceEqual("WAVE"u8)
            || BinaryPrimitives.ReadUInt32LittleEndian(wave[4..]) + 8L != wave.Length)
            throw new InvalidDataException("The microphone recording is not a complete RIFF/WAVE file.");
        int channels = 0, rate = 0;
        ReadOnlySpan<byte> pcm = default;
        for (int offset = 12; offset < wave.Length;)
        {
            if (wave.Length - offset < 8) throw new InvalidDataException("Incomplete microphone WAV chunk.");
            var kind = wave.Slice(offset, 4);
            var length = BinaryPrimitives.ReadUInt32LittleEndian(wave[(offset + 4)..]);
            var end = offset + 8L + length;
            var paddedEnd = end + (length & 1);
            if (paddedEnd > wave.Length) throw new InvalidDataException("Truncated microphone WAV data.");
            var chunk = wave.Slice(offset + 8, checked((int)length));
            if (kind.SequenceEqual("fmt "u8))
            {
                if (channels != 0 || chunk.Length < 16 || BinaryPrimitives.ReadUInt16LittleEndian(chunk) != 1
                    || BinaryPrimitives.ReadUInt16LittleEndian(chunk[14..]) != 16)
                    throw new InvalidDataException("Microphone recordings must use signed PCM16.");
                channels = BinaryPrimitives.ReadUInt16LittleEndian(chunk[2..]);
                rate = checked((int)BinaryPrimitives.ReadUInt32LittleEndian(chunk[4..]));
                if (channels is < 1 or > 8 || rate is < 8000 or > 192000
                    || BinaryPrimitives.ReadUInt16LittleEndian(chunk[12..]) != channels * 2)
                    throw new InvalidDataException("Invalid microphone WAV format.");
            }
            else if (kind.SequenceEqual("data"u8))
            {
                if (!pcm.IsEmpty || chunk.IsEmpty) throw new InvalidDataException("Expected one nonempty microphone audio chunk.");
                pcm = chunk;
            }
            offset = checked((int)paddedEnd);
        }
        if (channels == 0 || pcm.IsEmpty || pcm.Length % (channels * 2) != 0)
            throw new InvalidDataException("The microphone recording contains no complete PCM frames.");
        var frames = pcm.Length / (channels * 2);
        double peak = 0, squares = 0;
        long nonSilent = 0;
        for (var frame = 0; frame < frames; frame++)
        {
            var audible = false;
            for (var channel = 0; channel < channels; channel++)
            {
                var sample = BinaryPrimitives.ReadInt16LittleEndian(pcm[((frame * channels + channel) * 2)..]) / 32768d;
                peak = Math.Max(peak, Math.Abs(sample));
                squares += sample * sample;
                audible |= Math.Abs(sample) >= 0.001; // -60 dBFS: above the emulator's observed quiet input floor.
            }
            if (audible) nonSilent++;
        }
        return new(true, Sha256: Convert.ToHexString(SHA256.HashData(bytes)).ToLowerInvariant(), FileBytes: bytes.Length,
            SampleRate: rate, Channels: channels, BitsPerSample: 16, FrameCount: frames,
            DurationSeconds: frames / (double)rate, PeakAmplitude: peak,
            RmsAmplitude: Math.Sqrt(squares / (frames * (double)channels)), NonSilentFrameCount: nonSilent);
    }
}
