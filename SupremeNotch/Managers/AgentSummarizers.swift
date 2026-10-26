//
//  AgentSummarizers.swift
//  SupremeNotch
//
//  Turns raw hook payloads into one readable line for the notch.
//

import Foundation

nonisolated enum AgentToolSummarizer {
    struct Description: Equatable {
        /// Short tool label, for example "Run command" or "Edit file".
        let label: String
        /// The main line, for example the command or the file name.
        let summary: String
        /// Optional context, for example the agent's own description or the folder.
        let detail: String?
    }

    static func describe(toolName: String, input: [String: Any]) -> Description {
        let lower = toolName.lowercased()
        let agentDescription = string(input["description"])

        if let command = commandText(from: input) {
            return Description(label: "Run command", summary: oneLine(command, limit: 160), detail: agentDescription.map { oneLine($0, limit: 90) })
        }

        if let path = string(input["file_path"]) ?? string(input["notebook_path"]) ?? string(input["path"]) {
            let url = URL(fileURLWithPath: path)
            let label: String
            switch lower {
            case "read": label = "Read file"
            case "write": label = "Write file"
            case "edit", "multiedit", "notebookedit": label = "Edit file"
            default: label = toolName
            }
            let folder = url.deletingLastPathComponent().lastPathComponent
            return Description(label: label, summary: url.lastPathComponent, detail: folder.isEmpty ? nil : "in \(folder)")
        }

        if lower == "webfetch", let raw = string(input["url"]) {
            let url = URL(string: raw)
            let host = url?.host ?? raw
            let path = url?.path ?? ""
            return Description(label: "Fetch page", summary: oneLine(host + path, limit: 120), detail: nil)
        }

        if lower == "websearch", let query = string(input["query"]) {
            return Description(label: "Web search", summary: oneLine(query, limit: 120), detail: nil)
        }

        if lower.hasPrefix("mcp__") {
            let parts = toolName.components(separatedBy: "__").filter { !$0.isEmpty }
            let server = parts.count > 1 ? parts[1] : "MCP"
            let action = parts.count > 2 ? parts[2...].joined(separator: " ") : toolName
            let firstValue = input.values.compactMap(string).first.map { oneLine($0, limit: 120) }
            return Description(label: "\(server) tool", summary: action.replacingOccurrences(of: "_", with: " "), detail: firstValue)
        }

        if lower == "agent" || lower == "task", let agentDescription {
            return Description(label: "Start subagent", summary: oneLine(agentDescription, limit: 120), detail: nil)
        }

        if let patch = string(input["patch"]) ?? string(input["input"]),
           let file = firstPatchedFile(in: patch) {
            return Description(label: "Apply patch", summary: file, detail: nil)
        }

        let fallback = agentDescription ?? input.values.compactMap(string).first
        return Description(label: toolName, summary: oneLine(fallback ?? toolName, limit: 120), detail: nil)
    }

    private static func commandText(from input: [String: Any]) -> String? {
        if let command = string(input["command"]) {
            return command
        }
        if let parts = input["command"] as? [String], !parts.isEmpty {
            // Codex sometimes sends ["bash", "-lc", "real command"].
            if parts.count >= 3, ["bash", "zsh", "sh"].contains(URL(fileURLWithPath: parts[0]).lastPathComponent), parts[1].hasPrefix("-") {
                return parts[2...].joined(separator: " ")
            }
            return parts.joined(separator: " ")
        }
        if let cmd = string(input["cmd"]) {
            return cmd
        }
        return nil
    }

    private static func firstPatchedFile(in patch: String) -> String? {
        for line in patch.components(separatedBy: "\n") {
            for prefix in ["*** Update File: ", "*** Add File: ", "*** Delete File: ", "+++ b/"] where line.hasPrefix(prefix) {
                return URL(fileURLWithPath: String(line.dropFirst(prefix.count))).lastPathComponent
            }
        }
        return nil
    }

    static func string(_ value: Any?) -> String? {
        guard let text = value as? String else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func oneLine(_ text: String, limit: Int) -> String {
        let firstLine = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first(where: { !$0.isEmpty }) ?? text
        let collapsed = firstLine.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        let extraLines = text.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.count > 1
        return truncate(collapsed, limit: limit, forceEllipsis: extraLines)
    }

    static func truncate(_ text: String, limit: Int, forceEllipsis: Bool = false) -> String {
        guard text.count > limit else {
            return forceEllipsis ? text + " …" : text
        }
        let cut = text.prefix(limit)
        if let space = cut.lastIndex(of: " "), cut.distance(from: cut.startIndex, to: space) > limit / 2 {
            return String(cut[..<space]) + "…"
        }
        return String(cut) + "…"
    }
}

nonisolated enum AgentTranscriptSummarizer {
    /// Finds the agent's final message for a Stop hook payload and condenses it to one line.
    static func summary(fromHookPayload payload: [String: Any]) -> String? {
        for key in ["last_assistant_message", "last_agent_message"] {
            if let text = AgentToolSummarizer.string(payload[key]) {
                return condense(text)
            }
        }

        guard let path = AgentToolSummarizer.string(payload["transcript_path"]) else { return nil }
        let expanded = (path as NSString).expandingTildeInPath
        guard let text = lastAssistantText(inTranscriptAt: URL(fileURLWithPath: expanded)) else { return nil }
        return condense(text)
    }

    static func lastAssistantText(inTranscriptAt url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        let tailBytes: UInt64 = 768 * 1024
        let size = (try? handle.seekToEnd()) ?? 0
        try? handle.seek(toOffset: size > tailBytes ? size - tailBytes : 0)
        guard let data = try? handle.readToEnd(), let text = String(data: data, encoding: .utf8) else { return nil }

        for line in text.split(separator: "\n").reversed() {
            guard let lineData = line.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] else { continue }

            if let found = claudeAssistantText(object) ?? codexAssistantText(object) {
                return found
            }
        }
        return nil
    }

    /// Claude Code: {"type":"assistant","message":{"content":[{"type":"text","text":"..."}]}}
    private static func claudeAssistantText(_ object: [String: Any]) -> String? {
        guard object["type"] as? String == "assistant",
              object["isSidechain"] as? Bool != true,
              let message = object["message"] as? [String: Any],
              let content = message["content"] as? [[String: Any]] else { return nil }

        let texts = content.compactMap { block -> String? in
            guard block["type"] as? String == "text" else { return nil }
            return AgentToolSummarizer.string(block["text"])
        }
        return texts.isEmpty ? nil : texts.joined(separator: "\n")
    }

    /// Codex rollout: task_complete.last_agent_message, agent_message, or an assistant response_item.
    private static func codexAssistantText(_ object: [String: Any]) -> String? {
        guard let payload = object["payload"] as? [String: Any] else { return nil }
        let type = object["type"] as? String
        let payloadType = payload["type"] as? String

        if type == "event_msg", payloadType == "task_complete" {
            return AgentToolSummarizer.string(payload["last_agent_message"])
        }
        if type == "event_msg", payloadType == "agent_message" {
            return AgentToolSummarizer.string(payload["message"])
        }
        if type == "response_item", payloadType == "message", payload["role"] as? String == "assistant",
           let content = payload["content"] as? [[String: Any]] {
            let texts = content.compactMap { AgentToolSummarizer.string($0["text"]) }
            return texts.isEmpty ? nil : texts.joined(separator: "\n")
        }
        return nil
    }

    /// First meaningful sentence or line, without Markdown decoration.
    static func condense(_ text: String) -> String? {
        var insideFence = false
        var lines: [String] = []

        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("```") {
                insideFence.toggle()
                continue
            }
            guard !insideFence, !line.isEmpty, !line.hasPrefix("|"), !line.hasPrefix("---") else { continue }
            lines.append(line)
        }

        // Skip headings and short lead-ins such as "Here's what changed:" when real content follows.
        let meaningful = lines.first { line in
            let isHeading = line.hasPrefix("#")
            let isLeadIn = line.hasSuffix(":") && line.count < 60
            return !isHeading && !isLeadIn
        }
        guard var first = meaningful ?? lines.first else { return nil }

        while let prefix = ["#", "-", "*", ">", "•"].first(where: { first.hasPrefix($0) }) {
            first = String(first.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
        }
        first = first
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "__", with: "")
            .replacingOccurrences(of: "`", with: "")
        first = first.replacingOccurrences(of: #"\[([^\]]+)\]\([^)]+\)"#, with: "$1", options: .regularExpression)

        // Prefer a complete first sentence when it is reasonably long.
        if let range = first.range(of: #"[.!?](\s|$)"#, options: .regularExpression),
           first.distance(from: first.startIndex, to: range.lowerBound) >= 24 {
            first = String(first[..<range.upperBound]).trimmingCharacters(in: .whitespaces)
        }

        let condensed = AgentToolSummarizer.truncate(first, limit: 140)
        return condensed.isEmpty ? nil : condensed
    }
}
