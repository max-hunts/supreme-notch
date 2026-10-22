//
//  DictationModel.swift
//  BetterNotch
//
//  Dictation for the Ask field, with two engines (Settings > General > Dictation):
//  - ChatGPT: records while you talk, then ChatGPT's transcription turns it into text.
//    Most accurate; the audio goes to OpenAI, like the question itself.
//  - On this Mac: Apple's on-device speech recognition, with text appearing as you talk.
//    On macOS 26 and later that is the newer SpeechAnalyzer; audio never leaves the Mac.
//

import AVFoundation
import Combine
import Speech

nonisolated enum DictationEngine: String, CaseIterable, Identifiable, Sendable {
    case chatGPT, onDevice

    var id: String { rawValue }

    var title: String {
        switch self {
        case .chatGPT: return "ChatGPT"
        case .onDevice: return "On this Mac"
        }
    }

    var detail: String {
        switch self {
        case .chatGPT: return "Most accurate. Audio goes to OpenAI on your ChatGPT subscription; text appears when you stop."
        case .onDevice: return "Private: Apple's recognition on this Mac. Text appears as you talk."
        }
    }
}

@MainActor
final class DictationModel: ObservableObject {
    enum State: Equatable {
        case idle
        case starting
        case listening
        /// ChatGPT is turning the recording into text.
        case transcribing
        case failed(String)
    }

    @Published private(set) var state: State = .idle

    var isActive: Bool { state == .starting || state == .listening || state == .transcribing }

    /// A ChatGPT recording in progress has no text yet; stopping it is what produces some.
    var isRecordingForChatGPT: Bool { engineInUse == .chatGPT && state == .listening }

    private var engineInUse: DictationEngine?
    /// Bumped on every start, stop and cancel, so late results from an old session are dropped.
    private var session = 0
    private var onText: ((String) -> Void)?
    private var onFailure: ((String) -> Void)?

    // On this Mac
    /// Made only while dictating: touching an engine's input makes Core Audio add a
    /// "CADefaultDeviceAggregate" device, which shows in the Sound menu until the engine goes.
    private var audioEngine: AVAudioEngine?
    private var legacyRequest: SFSpeechAudioBufferRecognitionRequest?
    private var legacyTask: SFSpeechRecognitionTask?
    /// Ends the analyzer's audio input (macOS 26 types can't be stored on older systems).
    private var endAnalyzerInput: (() -> Void)?
    private var analyzerFinish: (() async -> Void)?
    private var resultsTask: Task<Void, Never>?

    // ChatGPT
    private var recorder: AVAudioRecorder?
    private var recordingURL: URL?

    /// Starts listening. `onText` gets the whole transcript so far each time it changes;
    /// `onFailure` gets a short reason when dictation can't start or finish.
    func start(
        engine: DictationEngine,
        onText: @escaping (String) -> Void,
        onFailure: @escaping (String) -> Void
    ) {
        guard !isActive else { return }
        session += 1
        let current = session
        engineInUse = engine
        self.onText = onText
        self.onFailure = onFailure
        state = .starting
        Task { @MainActor in
            guard await Self.authorize(speech: engine == .onDevice) else {
                let needs = engine == .onDevice ? "Microphone and Speech Recognition" : "Microphone"
                fail("Allow \(needs) for BetterNotch in System Settings → Privacy & Security.")
                return
            }
            guard session == current, state == .starting else { return }
            switch engine {
            case .chatGPT:
                beginRecording()
            case .onDevice:
                if #available(macOS 26, *) {
                    await beginAnalyzer(session: current)
                } else {
                    beginLegacy(session: current)
                }
            }
        }
    }

    /// Stops listening. On this Mac the text so far stays; a ChatGPT recording is sent off
    /// and its text arrives shortly.
    func stop() {
        switch state {
        case .failed:
            state = .idle
            return
        case .idle, .transcribing:
            return
        case .starting:
            cancel()
            return
        case .listening:
            break
        }
        if engineInUse == .chatGPT {
            finishRecording()
        } else {
            tearDownOnDevice(finalize: true)
            state = .idle
        }
    }

    /// Stops and throws away anything not yet transcribed.
    func cancel() {
        session += 1
        tearDownOnDevice(finalize: false)
        recorder?.stop()
        recorder = nil
        removeRecording()
        state = .idle
    }

    private func fail(_ message: String) {
        state = .failed(message)
        onFailure?(message)
    }

    // MARK: ChatGPT

    private func beginRecording() {
        let url = AskAIModel.workingDirectory.appendingPathComponent("dictation-\(UUID().uuidString).m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 24_000,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        guard let recorder = try? AVAudioRecorder(url: url, settings: settings),
              recorder.record(forDuration: 300) else {
            fail("The microphone couldn't start.")
            return
        }
        self.recorder = recorder
        recordingURL = url
        state = .listening
    }

    private func finishRecording() {
        recorder?.stop()
        recorder = nil
        guard let url = recordingURL, let audio = try? Data(contentsOf: url), audio.count > 2_000 else {
            removeRecording()
            state = .idle
            return
        }
        removeRecording()
        session += 1
        let current = session
        state = .transcribing
        Task { @MainActor in
            do {
                let text = try await ChatGPTTranscriber.transcribe(audio, filename: "dictation.m4a", contentType: "audio/mp4")
                guard session == current else { return }
                state = .idle
                if !text.isEmpty { onText?(text) }
            } catch {
                guard session == current else { return }
                fail(error.localizedDescription)
            }
        }
    }

    private func removeRecording() {
        if let recordingURL { try? FileManager.default.removeItem(at: recordingURL) }
        recordingURL = nil
    }

    // MARK: On this Mac, macOS 26 and later

    @available(macOS 26, *)
    private func beginAnalyzer(session current: Int) async {
        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale.current) else {
            fail("On-device dictation doesn't support \(Locale.current.identifier) yet.")
            return
        }
        let transcriber = SpeechTranscriber(locale: locale, preset: .progressiveTranscription)
        do {
            if let download = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                try await download.downloadAndInstall()
            }
        } catch {
            fail("The speech model for \(locale.identifier) couldn't download.")
            return
        }
        guard session == current,
              let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
            if session == current { fail("On-device dictation isn't available right now.") }
            return
        }

        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let (stream, input) = AsyncStream.makeStream(of: AnalyzerInput.self)
        endAnalyzerInput = { input.finish() }
        analyzerFinish = { try? await analyzer.finalizeAndFinishThroughEndOfInput() }
        resultsTask = Task { @MainActor [weak self] in
            var finalized = ""
            do {
                for try await result in transcriber.results {
                    guard let self, self.session == current else { break }
                    let text = String(result.text.characters)
                    if result.isFinal { finalized += text }
                    let shown = (result.isFinal ? finalized : finalized + text)
                        .trimmingCharacters(in: .whitespaces)
                    self.onText?(shown)
                }
            } catch {}
        }
        let engine = AVAudioEngine()
        audioEngine = engine
        do {
            try await analyzer.start(inputSequence: stream)
            Self.feed(engine.inputNode, converting: format, into: input)
            engine.prepare()
            try engine.start()
        } catch {
            tearDownOnDevice(finalize: false)
            fail("The microphone couldn't start.")
            return
        }
        guard session == current else {
            tearDownOnDevice(finalize: false)
            return
        }
        state = .listening
    }

    // MARK: On this Mac, before macOS 26

    private func beginLegacy(session current: Int) {
        guard let recognizer = SFSpeechRecognizer(), recognizer.isAvailable,
              recognizer.supportsOnDeviceRecognition else {
            fail("On-device dictation isn't available right now.")
            return
        }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true
        request.addsPunctuation = true
        legacyRequest = request

        let engine = AVAudioEngine()
        audioEngine = engine
        Self.feed(engine.inputNode, into: request)
        engine.prepare()
        do {
            try engine.start()
        } catch {
            tearDownOnDevice(finalize: false)
            fail("The microphone couldn't start.")
            return
        }
        legacyTask = recognizer.recognitionTask(with: request, resultHandler: Self.legacyHandler { [weak self] text, finished in
            guard let self, self.session == current else { return }
            if let text { self.onText?(text) }
            if finished {
                self.tearDownOnDevice(finalize: false)
                self.state = .idle
            }
        })
        state = .listening
    }

    /// `finalize` lets the last words still in flight come through before the session ends.
    private func tearDownOnDevice(finalize: Bool) {
        if let audioEngine {
            if audioEngine.isRunning { audioEngine.stop() }
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        audioEngine = nil
        legacyRequest?.endAudio()
        legacyRequest = nil
        legacyTask?.finish()
        legacyTask = nil
        endAnalyzerInput?()
        endAnalyzerInput = nil
        if let analyzerFinish {
            Task { await analyzerFinish() }
        }
        analyzerFinish = nil
        if !finalize {
            resultsTask?.cancel()
        }
        resultsTask = nil
    }

    // The audio tap and the recognizer call back on their own threads, so their closures
    // are made outside the main actor and hop back to it.

    @available(macOS 26, *)
    nonisolated private static func feed(
        _ input: AVAudioInputNode,
        converting format: AVAudioFormat,
        into stream: AsyncStream<AnalyzerInput>.Continuation
    ) {
        let inputFormat = input.outputFormat(forBus: 0)
        let converter = inputFormat == format ? nil : AVAudioConverter(from: inputFormat, to: format)
        input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { buffer, _ in
            guard let converter else {
                stream.yield(AnalyzerInput(buffer: buffer))
                return
            }
            let ratio = format.sampleRate / inputFormat.sampleRate
            let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 16
            guard let converted = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return }
            var supplied = false
            var error: NSError?
            converter.convert(to: converted, error: &error) { _, status in
                if supplied {
                    status.pointee = .noDataNow
                    return nil
                }
                supplied = true
                status.pointee = .haveData
                return buffer
            }
            if error == nil, converted.frameLength > 0 {
                stream.yield(AnalyzerInput(buffer: converted))
            }
        }
    }

    nonisolated private static func feed(_ input: AVAudioInputNode, into request: SFSpeechAudioBufferRecognitionRequest) {
        let format = input.outputFormat(forBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }
    }

    nonisolated private static func legacyHandler(
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

    nonisolated private static func authorize(speech: Bool) async -> Bool {
        if speech {
            let allowed: Bool = await withCheckedContinuation { continuation in
                switch SFSpeechRecognizer.authorizationStatus() {
                case .authorized:
                    continuation.resume(returning: true)
                case .notDetermined:
                    SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0 == .authorized) }
                default:
                    continuation.resume(returning: false)
                }
            }
            guard allowed else { return false }
        }
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
