//
//  DictationCheck.swift
//  SupremeNotch
//
//  Debug builds only: `SupremeNotch -dictationCheck <audio file> <report>` transcribes a
//  recording with ChatGPT and with the on-device engine, writes both and quits. The live
//  path needs a real microphone, so this checks each engine's model and service instead.
//

#if DEBUG
import AVFoundation
import Speech

@MainActor
enum DictationCheck {
    static var arguments: (audio: URL, report: URL)? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-dictationCheck"), index + 2 < arguments.count else { return nil }
        return (URL(fileURLWithPath: arguments[index + 1]), URL(fileURLWithPath: arguments[index + 2]))
    }

    static func run(audio: URL, report: URL) {
        Task { @MainActor in
            var lines: [String] = []
            let started = Date()
            do {
                let data = try Data(contentsOf: audio)
                let text = try await ChatGPTTranscriber.transcribe(data, filename: "dictation.m4a", contentType: "audio/mp4")
                lines.append(String(format: "chatgpt (%.1fs): %@", Date().timeIntervalSince(started), text))
            } catch {
                lines.append("chatgpt FAILED: \(error.localizedDescription)")
            }
            if #available(macOS 26, *) {
                lines.append(await onDevice(audio))
            }
            try? lines.joined(separator: "\n").appending("\n").write(to: report, atomically: true, encoding: .utf8)
            exit(0)
        }
    }

    @available(macOS 26, *)
    private static func onDevice(_ audio: URL) async -> String {
        let started = Date()
        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale.current) else {
            return "on-device FAILED: no locale for \(Locale.current.identifier)"
        }
        let transcriber = SpeechTranscriber(locale: locale, preset: .progressiveTranscription)
        do {
            if let download = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                try await download.downloadAndInstall()
            }
            let file = try AVAudioFile(forReading: audio)
            let analyzer = SpeechAnalyzer(modules: [transcriber])
            let collect = Task {
                var text = ""
                for try await result in transcriber.results where result.isFinal {
                    text += String(result.text.characters)
                }
                return text
            }
            try await analyzer.start(inputAudioFile: file, finishAfterFile: true)
            let text = try await collect.value.trimmingCharacters(in: .whitespaces)
            return String(format: "on-device %@ (%.1fs): %@", locale.identifier, Date().timeIntervalSince(started), text)
        } catch {
            return "on-device FAILED: \(error.localizedDescription)"
        }
    }
}
#endif
