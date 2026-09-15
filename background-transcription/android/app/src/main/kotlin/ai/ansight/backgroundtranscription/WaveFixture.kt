package ai.ansight.backgroundtranscription

import android.content.Context
import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder

data class PcmAudio(
    val file: File,
    val sampleRate: Int,
    val channelCount: Int,
    val encoding: Int,
)

object WaveFixture {
    fun extractPcm(context: Context, fixtureFileName: String): PcmAudio {
        val bytes = context.assets.open(fixtureFileName).use { it.readBytes() }
        require(bytes.size >= 44 && ascii(bytes, 0, 4) == "RIFF" && ascii(bytes, 8, 4) == "WAVE") {
            "$fixtureFileName is not a RIFF/WAVE file."
        }

        var offset = 12
        var sampleRate = 0
        var channels = 0
        var bitsPerSample = 0
        var pcmStart = -1
        var pcmLength = 0
        while (offset + 8 <= bytes.size) {
            val chunkId = ascii(bytes, offset, 4)
            val chunkLength = littleEndianInt(bytes, offset + 4)
            val payloadStart = offset + 8
            require(chunkLength >= 0 && payloadStart + chunkLength <= bytes.size) { "Invalid WAV chunk $chunkId." }
            if (chunkId == "fmt ") {
                require(chunkLength >= 16) { "Invalid WAV format chunk." }
                val format = littleEndianShort(bytes, payloadStart)
                require(format == 1) { "Only PCM WAV fixtures are supported (format=$format)." }
                channels = littleEndianShort(bytes, payloadStart + 2)
                sampleRate = littleEndianInt(bytes, payloadStart + 4)
                bitsPerSample = littleEndianShort(bytes, payloadStart + 14)
            } else if (chunkId == "data") {
                pcmStart = payloadStart
                pcmLength = chunkLength
                break
            }
            offset = payloadStart + chunkLength + (chunkLength % 2)
        }

        require(pcmStart >= 0 && sampleRate > 0 && channels > 0) { "WAV format or data chunk is missing." }
        require(bitsPerSample == 16) { "Only 16-bit PCM fixtures are supported (bits=$bitsPerSample)." }
        val pcmFile = File(context.cacheDir, "background-transcription/${fixtureFileName.removeSuffix(".wav")}.pcm")
        pcmFile.parentFile?.mkdirs()
        pcmFile.outputStream().use { it.write(bytes, pcmStart, pcmLength) }
        return PcmAudio(
            file = pcmFile,
            sampleRate = sampleRate,
            channelCount = channels,
            encoding = android.media.AudioFormat.ENCODING_PCM_16BIT,
        )
    }

    private fun ascii(bytes: ByteArray, start: Int, length: Int): String =
        bytes.copyOfRange(start, start + length).toString(Charsets.US_ASCII)

    private fun littleEndianInt(bytes: ByteArray, offset: Int): Int =
        ByteBuffer.wrap(bytes, offset, 4).order(ByteOrder.LITTLE_ENDIAN).int

    private fun littleEndianShort(bytes: ByteArray, offset: Int): Int =
        ByteBuffer.wrap(bytes, offset, 2).order(ByteOrder.LITTLE_ENDIAN).short.toInt() and 0xffff
}
