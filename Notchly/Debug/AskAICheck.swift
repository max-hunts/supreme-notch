//
//  AskAICheck.swift
//  BetterNotch
//
//  Debug builds only: `BetterNotch -askAICheck <file>` asks a question and a follow-up
//  through the Ask tab's model, writes the conversation to the file and quits.
//

#if DEBUG
import AppKit

@MainActor
enum AskAICheck {
    static var outputFile: URL? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-askAICheck"), index + 1 < arguments.count else { return nil }
        return URL(fileURLWithPath: arguments[index + 1])
    }

    static func run(to file: URL) {
        let model = AskAIModel()
        Task { @MainActor in
            var lines: [String] = []
            for question in ["What is the tallest mountain in Africa?", "How long does it usually take to climb it?"] {
                let started = Date()
                model.draft = question
                model.send()
                var firstText: TimeInterval?
                var updates = 0
                var lastLength = 0
                while model.isRunning {
                    let length = model.messages.last?.text.count ?? 0
                    if length > lastLength {
                        updates += 1
                        lastLength = length
                        if firstText == nil { firstText = Date().timeIntervalSince(started) }
                    }
                    try? await Task.sleep(for: .milliseconds(50))
                }
                lines.append(String(format: "[first text %.1fs, done %.1fs, %d visible updates] Q: %@",
                                    firstText ?? -1, Date().timeIntervalSince(started), updates, question))
                if let error = model.errorText {
                    lines.append("ERROR: \(error)")
                    break
                }
                lines.append("A: \(model.lastAnswer ?? "(none)")")
            }
            try? lines.joined(separator: "\n").appending("\n").write(to: file, atomically: true, encoding: .utf8)
            exit(0)
        }
    }
}
#endif
