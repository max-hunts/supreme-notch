//
//  DictationModel.swift
//  BetterNotch
//
//  Dictation for the Ask field. Speech is transcribed on this Mac only (Apple's on-device
//  speech recognition); audio is never sent anywhere. Text streams in while you talk.
//

import AVFoundation
import Combine
import Speech

@MainActor
final class DictationModel: ObservableObject {
    enum State: Equatable {
        case idle
        case starting
        case listening
        case failed(String)
    }

    @Published private(set) var state: State = .idle

    var isActive: Bool { state == .starting || state == .listening }

    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    /// Bumped on every start and stop, so late results from an old session are dropped.
    private var session = 0
    private var onFailure: ((String) -> Void)?

    /// Starts listening. `onText` gets the whole transcript so far each time it changes;
    /// `onFailure` gets a short reason when dictation can't start.
    func start(onText: @escaping (String) -> Void, onFailure: @escaping (String) -> Void) {
        guard !isActive else { return }
        self.onFailure = onFailure
        session += 1
        let current = session
        state = .starting
        Task { @MainActor in
            guard await Self.authorize() else {
                fail("Allow Microphone and Speech Recognition for BetterNotch in System Settings → Privacy & Security.")
                return
            }
            guard session == current, state == .starting else { return }
            begin(session: current, onText: onText)
        }
    }

    /// Stops listening; the text so far stays in the field.
    func stop() {
        guard isActive || task != nil else {
            if case .failed = state { state = .idle }
            return
        }
        session += 1
        tearDown()
        state = .idle
    }

    private func begin(session current: Int, onText: @escaping (String) -> Void) {
        guard let recognizer = SFSpeechRecognizer(), recognizer.isAvailable else {
            fail("Dictation isn't available right now.")
            return
        }
        guard recognizer.supportsOnDeviceRecognition else {
            fail("On-device dictation isn't available for \(recognizer.locale.identifier).")
            return
        }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true
        request.addsPunctuation = true
        self.request = request

        Self.feed(engine.inputNode, into: request)
        engine.prepare()
        do {
            try engine.start()
        } catch {
            tearDown()
            fail("The microphone couldn't start.")
            return
        }

        task = recognizer.recognitionTask(with: request, resultHandler: Self.handler { [weak self] text, finished in
            guard let self, self.session == current else { return }
            if let text { onText(text) }
            if finished {
                self.tearDown()
                self.state = .idle
            }
        })
        state = .listening
    }

    private func tearDown() {
        if engine.isRunning { engine.stop() }
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        request = nil
        task?.finish()
        task = nil
    }

    private func fail(_ message: String) {
        state = .failed(message)
        onFailure?(message)
    }

    // The audio tap and the recognizer call back on their own threads, so their closures
    // are made outside the main actor and hop back to it.

    nonisolated private static func feed(_ input: AVAudioInputNode, into request: SFSpeechAudioBufferRecognitionRequest) {
        let format = input.outputFormat(forBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }
    }

    nonisolated private static func handler(
        _ update: @escaping @MainActor (String?, Bool) -> Void
    ) -> (SFSpeechRecognitionResult?, Error?) -> Void {
        { result, error in
            let text = result?.bestTranscription.formattedString
            let finished = error != nil || result?.isFinal == true
            DispatchQueue.main.async {
                MainActor.assumeIsolated { update(text, finished) }
            }
        }
    }

    nonisolated private static func authorize() async -> Bool {
        let speech: Bool = await withCheckedContinuation { continuation in
            switch SFSpeechRecognizer.authorizationStatus() {
            case .authorized:
                continuation.resume(returning: true)
            case .notDetermined:
                SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0 == .authorized) }
            default:
                continuation.resume(returning: false)
            }
        }
        guard speech else { return false }
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .audio)
        default:
            return false
        }
    }
}
