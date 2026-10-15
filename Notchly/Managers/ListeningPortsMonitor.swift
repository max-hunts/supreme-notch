//
//  ListeningPortsMonitor.swift
//  Notchly
//
//  Lists TCP ports your own processes are listening on (dev servers, databases)
//  and stops them on request. Uses lsof, which only sees this user's processes.
//

import AppKit
import Combine
import Darwin
import Foundation

nonisolated struct ListeningPort: Identifiable, Hashable {
    var id: String { "\(pid)-\(port)" }
    let pid: pid_t
    let port: Int
    let command: String
    /// Last component of the process's working folder, when it says something useful.
    let project: String?
    /// Docker container publishing this port, when the listener is Docker's backend.
    var dockerContainer: String? = nil
    /// Compose service and project labels, when the container came from docker compose.
    var dockerService: String? = nil
    var dockerProject: String? = nil
    /// A regular desktop app (Spotify, Figma) rather than a server you started.
    var isDesktopApp = false

    var localURL: URL? { URL(string: "http://localhost:\(port)") }

    var isDockerBackend: Bool { command.lowercased().hasPrefix("com.docker") }

    /// Stopping is safe for ordinary processes and for mapped containers. Killing Docker's
    /// backend would take every container down, so unmapped Docker ports cannot be stopped.
    var canStop: Bool { !isDockerBackend || dockerContainer != nil }

    /// Short name for the notch row: compose service, container, or command.
    var displayName: String {
        dockerService ?? dockerContainer ?? (isDockerBackend ? "Docker" : command)
    }

    /// Dim context next to the name: the project folder for local processes.
    var context: String? {
        dockerContainer == nil && !isDockerBackend ? project : nil
    }

    var label: String {
        if let dockerContainer {
            let service = dockerService.map { "\($0) · " } ?? ""
            return "\(service)\(dockerProject ?? dockerContainer) (Docker)"
        }
        if isDockerBackend {
            return "Docker"
        }
        return project.map { "\(command) · \($0)" } ?? command
    }
}

@MainActor
final class ListeningPortsMonitor: ObservableObject {
    @Published private(set) var ports: [ListeningPort] = []
    /// Row waiting for a second click to confirm the kill.
    @Published private(set) var pendingKillID: String?

    private var liveTask: Task<Void, Never>?
    private var backgroundTask: Task<Void, Never>?
    private var liveClients = 0
    private var confirmTask: Task<Void, Never>?
    private var terminated = Set<pid_t>()

    /// Keeps the list fresh in the background so the panel opens at its final height.
    func startBackgroundRefresh() {
        guard backgroundTask == nil else { return }
        backgroundTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: .seconds(20))
            }
        }
    }

    func stopBackgroundRefresh() {
        backgroundTask?.cancel()
        backgroundTask = nil
    }

    func startLive() {
        liveClients += 1
        guard liveTask == nil else { return }
        liveTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }

    func stopLive() {
        liveClients = max(0, liveClients - 1)
        guard liveClients == 0 else { return }
        liveTask?.cancel()
        liveTask = nil
        pendingKillID = nil
    }

    func refresh() async {
        let snapshot = await Task.detached(priority: .userInitiated) {
            Self.snapshot()
        }.value
        if snapshot != ports {
            ports = snapshot
        }
    }

    /// First click arms, second click within 3 seconds stops the process.
    func requestKill(_ port: ListeningPort) {
        guard pendingKillID == port.id else {
            pendingKillID = port.id
            confirmTask?.cancel()
            confirmTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(3))
                guard !Task.isCancelled else { return }
                self?.pendingKillID = nil
            }
            return
        }

        pendingKillID = nil
        confirmTask?.cancel()
        guard port.canStop else { return }

        if let container = port.dockerContainer {
            Task.detached(priority: .userInitiated) {
                Self.stopContainer(container)
            }
        } else {
            // A process that ignored SIGTERM gets SIGKILL on the next confirmed click.
            let force = terminated.contains(port.pid)
            Self.terminate(pid: port.pid, force: force)
            terminated.insert(port.pid)
        }

        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(port.dockerContainer == nil ? 900 : 2500))
            await self?.refresh()
        }
    }

    nonisolated static func terminate(pid: pid_t, force: Bool) {
        guard pid > 1, pid != getpid() else { return }
        kill(pid, force ? SIGKILL : SIGTERM)
    }

    /// Stops one container; Docker keeps running.
    nonisolated static func stopContainer(_ name: String) {
        guard let docker = dockerExecutable else { return }
        _ = run(docker, ["stop", name], timeout: 30)
    }

    nonisolated private static var dockerExecutable: URL? {
        ["/usr/local/bin/docker", "/opt/homebrew/bin/docker", "/Applications/Docker.app/Contents/Resources/bin/docker"]
            .map(URL.init(fileURLWithPath:))
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    nonisolated struct DockerContainer: Equatable {
        let name: String
        let service: String?
        let project: String?
    }

    /// Host port to container, from `docker ps`. Empty when Docker is not running.
    nonisolated static func dockerPortMap() -> [Int: DockerContainer] {
        guard let docker = dockerExecutable,
              let output = run(docker, [
                "ps", "--format",
                "{{.Names}}\t{{.Ports}}\t{{.Label \"com.docker.compose.service\"}}\t{{.Label \"com.docker.compose.project\"}}"
              ], timeout: 3) else { return [:] }
        return parseDockerPorts(output)
    }

    nonisolated static func parseDockerPorts(_ output: String) -> [Int: DockerContainer] {
        var map: [Int: DockerContainer] = [:]
        let pattern = try? NSRegularExpression(pattern: #":(\d+)->"#)
        for line in output.split(separator: "\n") {
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard fields.count >= 2 else { continue }
            let container = DockerContainer(
                name: fields[0],
                service: fields.count > 2 && !fields[2].isEmpty ? fields[2] : nil,
                project: fields.count > 3 && !fields[3].isEmpty ? fields[3] : nil
            )
            let ports = fields[1]
            let range = NSRange(ports.startIndex..., in: ports)
            pattern?.enumerateMatches(in: ports, range: range) { match, _, _ in
                guard let match, let portRange = Range(match.range(at: 1), in: ports), let port = Int(ports[portRange]) else { return }
                map[port] = container
            }
        }
        return map
    }

    nonisolated private static func run(_ executable: URL, _ arguments: [String], timeout: TimeInterval) -> String? {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        if process.isRunning {
            process.terminate()
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)
    }

    // MARK: - Snapshot

    /// Processes that listen on ports but are part of macOS, not your work.
    nonisolated private static let ignoredCommands: [String] = [
        "controlce", "rapportd", "sharingd", "airplayxpchelper", "identityservicesd", "launchd",
        "notchly", "remoted", "wifiagent", "usereventagent", "mdnsresponder", "cupsd", "screensharingd"
    ]

    nonisolated static func snapshot() -> [ListeningPort] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        process.arguments = ["-nP", "-iTCP", "-sTCP:LISTEN", "+c", "0", "-F", "pcn"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return []
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard let text = String(data: data, encoding: .utf8) else { return [] }
        var ports = parse(lsofOutput: text)

        if ports.contains(where: \.isDockerBackend) {
            let containers = dockerPortMap()
            for index in ports.indices where ports[index].isDockerBackend {
                let container = containers[ports[index].port]
                ports[index].dockerContainer = container?.name
                ports[index].dockerService = container?.service
                ports[index].dockerProject = container?.project
            }
        }

        for index in ports.indices {
            ports[index].isDesktopApp = NSRunningApplication(processIdentifier: ports[index].pid)?.activationPolicy == .regular
        }
        return ports
    }

    nonisolated static func parse(lsofOutput text: String) -> [ListeningPort] {
        var results: [ListeningPort] = []
        var seen = Set<String>()
        var pid: pid_t = 0
        var command = ""
        var projectCache: [pid_t: String?] = [:]

        for line in text.split(separator: "\n") {
            guard let tag = line.first else { continue }
            let value = String(line.dropFirst())

            switch tag {
            case "p":
                pid = pid_t(value) ?? 0
            case "c":
                command = value
            case "n":
                guard let colon = value.lastIndex(of: ":"),
                      let port = Int(value[value.index(after: colon)...]),
                      port < 49152 else { continue }

                let lower = command.lowercased()
                guard !ignoredCommands.contains(where: { lower.hasPrefix($0) }) else { continue }

                let key = "\(pid)-\(port)"
                guard seen.insert(key).inserted else { continue }

                if projectCache[pid] == nil {
                    projectCache[pid] = projectName(for: pid)
                }
                results.append(ListeningPort(pid: pid, port: port, command: command, project: projectCache[pid] ?? nil))
            default:
                continue
            }
        }

        return results.sorted { $0.port < $1.port }
    }

    /// The process's current working folder, if it is a project rather than / or home.
    nonisolated private static func projectName(for pid: pid_t) -> String? {
        var info = proc_vnodepathinfo()
        let size = Int32(MemoryLayout<proc_vnodepathinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, size) == size else { return nil }

        let path = withUnsafePointer(to: &info.pvi_cdir.vip_path) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) { String(cString: $0) }
        }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        guard !path.isEmpty, path != "/", path != home else { return nil }
        return URL(fileURLWithPath: path).lastPathComponent
    }

    #if DEBUG
    /// Sample data for README images.
    func previewLoad(_ ports: [ListeningPort]) { self.ports = ports }
    #endif
}
