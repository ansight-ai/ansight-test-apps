package ai.ansight.backgroundtranscription

import ai.ansight.runtime.AnsightNetworkHeader
import ai.ansight.runtime.AnsightNetworkRequest
import ai.ansight.runtime.AnsightRuntime
import java.net.HttpURLConnection
import java.net.URL
import java.time.Instant
import java.util.concurrent.Executors

object CaptureValidationNetworkProbe {
    private const val ENDPOINT = "https://www.ansight.ai/"
    private val executor = Executors.newSingleThreadExecutor()

    fun run(runId: String) {
        executor.execute {
            val startedAt = Instant.now()
            val startedNanos = System.nanoTime()
            var connection: HttpURLConnection? = null
            var statusCode: Int? = null
            var reasonPhrase: String? = null
            var responseHeaders = emptyList<AnsightNetworkHeader>()
            var errorType: String? = null
            var errorMessage: String? = null

            try {
                connection = (URL(ENDPOINT).openConnection() as HttpURLConnection).apply {
                    requestMethod = "HEAD"
                    connectTimeout = 15_000
                    readTimeout = 15_000
                    setRequestProperty("User-Agent", "background-transcription/1.0")
                    setRequestProperty("X-Ansight-Run-Id", runId)
                    connect()
                }
                statusCode = connection.responseCode
                reasonPhrase = connection.responseMessage
                responseHeaders = connection.headerFields
                    .filterKeys { it != null }
                    .flatMap { (name, values) ->
                        values.orEmpty().map { value -> AnsightNetworkHeader(name.orEmpty(), value) }
                    }
            } catch (error: Exception) {
                errorType = error.javaClass.simpleName
                errorMessage = error.message
            } finally {
                connection?.disconnect()
            }

            val completedAt = Instant.now()
            AnsightRuntime.recordNetworkRequest(
                AnsightNetworkRequest(
                    id = "capture-probe-$runId",
                    source = "background-transcription.capture-validation",
                    startedAtUtc = startedAt.toString(),
                    completedAtUtc = completedAt.toString(),
                    durationMilliseconds = (System.nanoTime() - startedNanos) / 1_000_000.0,
                    method = "HEAD",
                    url = ENDPOINT,
                    protocol = "https",
                    requestHeaders = listOf(
                        AnsightNetworkHeader("User-Agent", "background-transcription/1.0"),
                        AnsightNetworkHeader("X-Ansight-Run-Id", runId),
                    ),
                    statusCode = statusCode,
                    reasonPhrase = reasonPhrase,
                    responseHeaders = responseHeaders,
                    errorType = errorType,
                    errorMessage = errorMessage,
                ),
            )
        }
    }
}
