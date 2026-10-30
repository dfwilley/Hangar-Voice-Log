import Foundation
import Speech

/// Converts a recorded voice note to text using Apple's speech recognition,
/// kept on the phone whenever the phone supports it.
enum Transcriber {

    enum TranscriberError: LocalizedError {
        case notAllowed
        case unavailable
        case noSpeech

        var errorDescription: String? {
            switch self {
            case .notAllowed:
                return "Speech recognition is off. Turn it on in Settings › Hangar Log."
            case .unavailable:
                return "Speech recognition isn't available right now. You can type the description instead."
            case .noSpeech:
                return "No words were recognized in the recording."
            }
        }
    }

    /// Words the recognizer should expect around an airplane.
    static let aviationTerms = [
        "tach", "Hobbs", "condition inspection", "annual", "oil change", "oil filter",
        "spark plugs", "magneto", "safety wire", "torque", "torque seal", "cowling",
        "service bulletin", "airworthiness directive", "squawk", "Van's", "RV-14",
        "Lycoming", "propeller", "spinner", "brake pads", "tire pressure", "ELT"
    ]

    static func requestAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    static func transcribe(url: URL) async throws -> String {
        guard await requestAuthorization() else { throw TranscriberError.notAllowed }
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US")),
              recognizer.isAvailable else {
            throw TranscriberError.unavailable
        }

        let request = SFSpeechURLRecognitionRequest(url: url)
        request.shouldReportPartialResults = false
        request.addsPunctuation = true
        request.contextualStrings = aviationTerms
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }

        return try await withCheckedThrowingContinuation { continuation in
            var finished = false
            let lock = NSLock()
            func finish(_ result: Result<String, Error>) {
                lock.lock()
                defer { lock.unlock() }
                guard !finished else { return }
                finished = true
                continuation.resume(with: result)
            }

            recognizer.recognitionTask(with: request) { result, error in
                // Keep the recognizer alive until it reports back.
                withExtendedLifetime(recognizer) {}
                if let result, result.isFinal {
                    let text = result.bestTranscription.formattedString
                    if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        finish(.failure(TranscriberError.noSpeech))
                    } else {
                        finish(.success(text))
                    }
                } else if let error {
                    finish(.failure(error))
                }
            }
        }
    }
}
