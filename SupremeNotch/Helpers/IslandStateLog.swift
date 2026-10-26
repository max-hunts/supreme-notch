//
//  IslandStateLog.swift
//  SupremeNotch
//
//  TEMPORARY: records island state changes to find the empty notch after wake.
//  Remove once that is fixed.
//

import Foundation

enum IslandStateLog {
    private static let url = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/SupremeNotch/island-state.log")
    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()

    static func record(_ line: String) {
        let text = "\(formatter.string(from: Date())) \(line)\n"
        guard let data = text.data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: url)
        }
    }
}
