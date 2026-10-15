//
//  AgentHookScript.swift
//  Notchly
//
//  Shared hook script and file protocol for agent approvals and alerts.
//
//  Protocol (all files live under ~/Library/Application Support/Notchly, mode 0700):
//  - The hook appends one JSON line per event to agent-events.jsonl.
//  - For a permission request it also saves the hook's stdin to requests/<id>.json
//    and polls decisions/<id>.json until Notchly writes a decision, the wait window
//    ends, or the agent kills the hook. A decision file is either the agent's
//    hookSpecificOutput JSON, which the hook prints to stdout, or {"release":true},
//    which makes the hook exit silently so the agent shows its own prompt.
//  - For a completed task it saves stdin to requests/<id>.json so Notchly can read
//    the transcript path or last message and show a one-line summary.
//

import Foundation

enum AgentHookPaths {
    static var baseDirectoryURL: URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("BetterNotch", isDirectory: true)
    }

    /// Where hooks lived before the app was renamed from Notchly.
    static var legacyBinDirectoryURL: URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Notchly", isDirectory: true)
            .appendingPathComponent("bin", isDirectory: true)
    }

    static var binDirectoryURL: URL {
        baseDirectoryURL.appendingPathComponent("bin", isDirectory: true)
    }

    static var requestsDirectoryURL: URL {
        baseDirectoryURL.appendingPathComponent("requests", isDirectory: true)
    }

    static var decisionsDirectoryURL: URL {
        baseDirectoryURL.appendingPathComponent("decisions", isDirectory: true)
    }

    /// Plain-text number of seconds a hook waits for a decision. 0 disables notch approvals.
    static var approvalWaitFileURL: URL {
        baseDirectoryURL.appendingPathComponent("approval-wait-seconds")
    }

    static func requestURL(for id: String) -> URL {
        requestsDirectoryURL.appendingPathComponent("\(id).json")
    }

    static func decisionURL(for id: String) -> URL {
        decisionsDirectoryURL.appendingPathComponent("\(id).json")
    }

    static func ensureDirectories() throws {
        let fileManager = FileManager.default
        for url in [baseDirectoryURL, requestsDirectoryURL, decisionsDirectoryURL] {
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
            try? fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        }
    }

    static func writeApprovalWaitSeconds(_ seconds: Int) {
        try? ensureDirectories()
        let clamped = max(0, min(seconds, 300))
        try? "\(clamped)\n".write(to: approvalWaitFileURL, atomically: true, encoding: .utf8)
    }

    /// Hook timeout given to the agent for the PermissionRequest handler.
    /// It has to outlast the longest wait window the settings allow.
    static let permissionHookTimeoutSeconds = 150
}

enum AgentHookScript {
    static let version = 4
    static let versionMarker = "# betternotch-hook-version: \(version)"

    /// - Parameters:
    ///   - source: "claude" or "codex", written into every event.
    ///   - displayName: used in fallback alert text.
    static func script(source: String, displayName: String) -> String {
        """
#!/bin/sh
\(versionMarker)
# Managed by BetterNotch. Reinstall from Settings > AI Agents instead of editing.
# Local only: writes small files under ~/Library/Application Support/BetterNotch.
umask 077

source_name="\(source)"
event_type="${1:-completed}"
base="$HOME/Library/Application Support/BetterNotch"
events_file="$base/agent-events.jsonl"
requests_dir="$base/requests"
decisions_dir="$base/decisions"
mkdir -p "$requests_dir" "$decisions_dir"

clean() { printf '%s' "$1" | tr -cd 'A-Za-z0-9._:-'; }

field() { printf '%s' "$payload" | /usr/bin/plutil -extract "$1" raw -o - - 2>/dev/null; }

emit() {
  # emit TYPE TITLE MESSAGE [REQUEST_ID] [PAYLOAD_ID]
  printf '{"source":"%s","type":"%s","title":"%s","message":"%s","request_id":"%s","payload_id":"%s","session_id":"%s","tool_name":"%s","hook_event":"%s","cwd":"%s","step":"%s","pid":%s,"ttl":3}\\n' \\
    "$source_name" "$1" "$2" "$3" "${4:-}" "${5:-}" "${sid:-}" "${tool:-}" "${hook_event:-}" "${cwd:-}" "${step:-}" "${PPID:-0}" >> "$events_file"
}

notchly_running() { /usr/bin/pgrep -qx BetterNotch; }

payload=$(cat)
sid=$(clean "$(field session_id)")
tool=$(clean "$(field tool_name)")
hook_event=$(clean "$(field hook_event_name)")
# Strip characters that would break the JSON line; only the folder name is shown.
cwd=$(field cwd | tr -d '\\042\\134\\000-\\037')

# A short hint for the Agents tab: a file name, or a command's first two words.
# Anything after "=" is dropped, so values such as TOKEN=... are never written.
step=""
if [ "$hook_event" = "PreToolUse" ]; then
  file=$(field tool_input.file_path)
  [ -z "$file" ] && file=$(field tool_input.notebook_path)
  if [ -n "$file" ]; then
    step="file:${file##*/}"
  else
    cmd=$(field tool_input.command | head -n 1)
    if [ -n "$cmd" ]; then
      step="cmd:$(printf '%s' "$cmd" | awk '{ s = 1; if ($1 == "cd" && $3 == "&&") s = 4; out = ""; for (i = s; i < s + 2 && i <= NF; i++) { w = $i; if (w ~ /^(&&|[|][|]|[|]|;)$/) break; sub(/=.*/, "", w); out = out (out == "" ? "" : " ") w } print out }')"
    fi
  fi
  step=$(printf '%s' "$step" | tr -d '\\042\\134\\000-\\037' | cut -c1-80)
fi

# Older configs pass "approval" for Notification events too. Only a real
# PermissionRequest may block, so trust the payload's own event name.
if [ "$event_type" = "approval" ] && [ -n "$hook_event" ] && [ "$hook_event" != "PermissionRequest" ]; then
  event_type="notify"
fi

case "$event_type" in
  approval|permission_request)
    wait_seconds=$(tr -cd '0-9' < "$base/approval-wait-seconds" 2>/dev/null)
    wait_seconds=${wait_seconds:-0}
    if [ "$wait_seconds" -le 0 ] || ! notchly_running; then
      emit access_request "Need approval" "\(displayName) needs approval"
      exit 0
    fi
    id=$(/usr/bin/uuidgen | tr 'A-Z' 'a-z')
    request_file="$requests_dir/$id.json"
    decision_file="$decisions_dir/$id.json"
    printf '%s' "$payload" > "$request_file"
    trap 'rm -f "$request_file" "$decision_file"; emit clear "" "" "$id"; exit 0' HUP INT TERM
    emit access_request "Need approval" "\(displayName) needs approval" "$id"
    ticks=$((wait_seconds * 5))
    i=0
    while [ "$i" -lt "$ticks" ]; do
      if [ -f "$decision_file" ]; then
        if ! grep -q '"release"' "$decision_file"; then
          cat "$decision_file"
        fi
        rm -f "$request_file" "$decision_file"
        # Tell BetterNotch the request is settled, whoever wrote the decision.
        emit clear "" "" "$id"
        exit 0
      fi
      sleep 0.2
      i=$((i + 1))
    done
    rm -f "$request_file"
    emit clear "" "" "$id"
    exit 0
    ;;
  notify|notification|permission_prompt)
    emit access_request "Need approval" "\(displayName) needs approval"
    ;;
  waiting|idle_prompt)
    emit waiting "Waiting for input" "\(displayName) is waiting"
    ;;
  completed|stop)
    if notchly_running; then
      id=$(/usr/bin/uuidgen | tr 'A-Z' 'a-z')
      printf '%s' "$payload" > "$requests_dir/stop-$id.json"
      emit completed "Task completed" "\(displayName) finished" "" "stop-$id"
    else
      emit completed "Task completed" "\(displayName) finished"
    fi
    ;;
  failed|stop_failure)
    emit failed "Task failed" "\(displayName) failed"
    ;;
  *)
    # clear, approved, pre_tool_use, post_tool_use, user_prompt_submit, session_end, permission_denied
    emit clear "" ""
    ;;
esac

exit 0
"""
    }
}

/// Reads, edits and writes a JSON hooks file shaped like {"hooks": {"Event": [{matcher?, hooks:[{type, command, timeout?}]}]}}.
/// Used for ~/.claude/settings.json and ~/.codex/hooks.json. Unknown keys and other tools' handlers are preserved.
struct AgentHookJSONConfig {
    enum EditError: LocalizedError {
        case invalidRootObject(String)
        case invalidHooksObject(String)
        case invalidEvent(String)

        var errorDescription: String? {
            switch self {
            case let .invalidRootObject(path):
                return "\(path) must contain a JSON object."
            case let .invalidHooksObject(path):
                return "The hooks value in \(path) must be a JSON object."
            case let .invalidEvent(event):
                return "The \(event) hook entry has an unexpected shape."
            }
        }
    }

    struct Handler {
        let event: String
        let matcher: String?
        let command: String
        let timeout: Int?
    }

    let fileURL: URL
    private let fileManager = FileManager.default

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    /// Replaces every handler whose command mentions `managedMarker` with `handlers`.
    func install(handlers: [Handler], managedMarker: String) throws {
        try fileManager.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        var root = try load()
        var hooks = try hooksObject(from: root)
        hooks = try removing(marker: managedMarker, from: hooks)

        for handler in handlers {
            var groups = (hooks[handler.event] as? [[String: Any]]) ?? []
            var entry: [String: Any] = ["type": "command", "command": handler.command]
            if let timeout = handler.timeout {
                entry["timeout"] = timeout
            }
            var group: [String: Any] = ["hooks": [entry]]
            if let matcher = handler.matcher {
                group["matcher"] = matcher
            }
            groups.append(group)
            hooks[handler.event] = groups
        }

        root["hooks"] = hooks
        try write(root)
    }

    func uninstall(managedMarker: String) throws {
        guard fileManager.fileExists(atPath: fileURL.path) else { return }
        var root = try load()
        let hooks = try removing(marker: managedMarker, from: try hooksObject(from: root))
        if hooks.isEmpty {
            root.removeValue(forKey: "hooks")
        } else {
            root["hooks"] = hooks
        }
        try write(root)
    }

    /// True when any handler command in the file mentions `marker`.
    func mentions(_ marker: String) -> Bool {
        guard let data = try? Data(contentsOf: fileURL),
              let text = String(data: data, encoding: .utf8) else { return false }
        return text.contains(marker)
    }

    func contains(_ handler: Handler) -> Bool {
        guard let root = try? load(),
              let hooks = root["hooks"] as? [String: Any],
              let groups = hooks[handler.event] as? [[String: Any]] else {
            return false
        }

        return groups.contains { group in
            if let matcher = handler.matcher, group["matcher"] as? String != matcher {
                return false
            }
            guard let entries = group["hooks"] as? [[String: Any]] else { return false }
            return entries.contains { $0["command"] as? String == handler.command }
        }
    }

    private func load() throws -> [String: Any] {
        guard fileManager.fileExists(atPath: fileURL.path) else { return [:] }
        let data = try Data(contentsOf: fileURL)
        guard !data.isEmpty else { return [:] }
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw EditError.invalidRootObject(fileURL.path)
        }
        return root
    }

    private func hooksObject(from root: [String: Any]) throws -> [String: Any] {
        guard let value = root["hooks"] else { return [:] }
        guard let hooks = value as? [String: Any] else {
            throw EditError.invalidHooksObject(fileURL.path)
        }
        return hooks
    }

    private func removing(marker: String, from hooks: [String: Any]) throws -> [String: Any] {
        var updated: [String: Any] = [:]

        for (event, value) in hooks {
            guard let groups = value as? [[String: Any]] else {
                throw EditError.invalidEvent(event)
            }

            let kept = groups.compactMap { group -> [String: Any]? in
                guard let entries = group["hooks"] as? [[String: Any]] else { return group }
                let keptEntries = entries.filter { entry in
                    guard let command = entry["command"] as? String else { return true }
                    return !command.contains(marker)
                }
                guard !keptEntries.isEmpty else { return nil }
                var copy = group
                copy["hooks"] = keptEntries
                return copy
            }

            if !kept.isEmpty {
                updated[event] = kept
            }
        }

        return updated
    }

    private func write(_ root: [String: Any]) throws {
        if fileManager.fileExists(atPath: fileURL.path) {
            let backupURL = fileURL.appendingPathExtension("betternotch-backup")
            try? fileManager.removeItem(at: backupURL)
            try? fileManager.copyItem(at: fileURL, to: backupURL)
        }

        let data = try JSONSerialization.data(
            withJSONObject: root,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
        try data.write(to: fileURL, options: .atomic)
    }
}
