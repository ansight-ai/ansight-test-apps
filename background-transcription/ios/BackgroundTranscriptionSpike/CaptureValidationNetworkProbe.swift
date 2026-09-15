import Foundation

enum CaptureValidationNetworkProbe {
    private static let endpoint = URL(string: "https://www.ansight.ai/")!

    static func run(runId: String) {
        Task {
            var request = URLRequest(url: endpoint)
            request.httpMethod = "HEAD"
            request.timeoutInterval = 15
            request.setValue("background-transcription/1.0", forHTTPHeaderField: "User-Agent")
            request.setValue(runId, forHTTPHeaderField: "X-Ansight-Run-Id")
            _ = try? await URLSession.shared.data(for: request)
        }
    }
}
