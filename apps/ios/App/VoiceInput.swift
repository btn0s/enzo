import AVFoundation
import Foundation
import Observation
import Speech

@MainActor
@Observable
final class VoiceInput {
    var transcript = ""
    var isListening = false
    var errorMessage: String?

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    init() {
#if DEBUG
        isListening = ProcessInfo.processInfo.environment["ENZO_PREVIEW_LISTENING"] == "1"
#endif
    }

    func start() async {
        guard !isListening else { return }
        let authorized = await requestPermissions()
        guard authorized else {
            errorMessage = "Microphone or speech recognition permission was denied."
            return
        }

        transcript = ""
        errorMessage = nil
        task?.cancel()
        request = SFSpeechAudioBufferRecognitionRequest()
        guard let request, let recognizer else { return }
        request.shouldReportPartialResults = true
        request.contextualStrings = ["Enzo", "poop", "pee", "formula", "breast milk", "milliliters"]
        request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            errorMessage = "No microphone input is available."
            return
        }
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            engine.prepare()
            try engine.start()
            isListening = true
            task = recognizer.recognitionTask(with: request) { [weak self] result, error in
                Task { @MainActor in
                    if let result { self?.transcript = result.bestTranscription.formattedString }
                    if let error { self?.errorMessage = error.localizedDescription }
                }
            }
        } catch {
            errorMessage = error.localizedDescription
            input.removeTap(onBus: 0)
        }
    }

    func stop() async -> String {
        guard isListening else { return transcript }
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        try? await Task.sleep(for: .milliseconds(350))
        task?.finish()
        isListening = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        return transcript
    }

    func cancel() async {
        _ = await stop()
        transcript = ""
        errorMessage = nil
    }

    private func requestPermissions() async -> Bool {
        let speech = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        let microphone = await AVAudioApplication.requestRecordPermission()
        return speech == .authorized && microphone
    }
}
