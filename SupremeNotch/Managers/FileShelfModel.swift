//
//  FileShelfModel.swift
//  SupremeNotch
//
//  Files parked on the notch. The shelf keeps references to the files where they are;
//  nothing is copied, moved or deleted. Removing an item only takes it off the shelf.
//

import AppKit
import Combine
import Foundation

nonisolated struct ShelfItem: Identifiable, Equatable {
    var id: String { url.path }
    let url: URL
}

@MainActor
final class FileShelfModel: ObservableObject {
    @Published private(set) var items: [ShelfItem] = []

    static let maxItems = 10
    private static let defaultsKey = "fileShelfPaths"

    init() {
        let paths = UserDefaults.standard.stringArray(forKey: Self.defaultsKey) ?? []
        items = paths
            .filter { FileManager.default.fileExists(atPath: $0) }
            .map { ShelfItem(url: URL(fileURLWithPath: $0)) }
    }

    func add(_ urls: [URL]) {
        var next = items
        for url in urls where url.isFileURL {
            let item = ShelfItem(url: url.standardizedFileURL)
            next.removeAll { $0 == item }
            next.append(item)
        }
        // Newest stay; the oldest drop off past the limit.
        items = Array(next.suffix(Self.maxItems))
        save()
    }

    func remove(_ item: ShelfItem) {
        items.removeAll { $0 == item }
        save()
    }

    func clear() {
        items = []
        save()
    }

    /// Drops items whose files were moved or deleted since they were added.
    func pruneMissing() {
        let kept = items.filter { FileManager.default.fileExists(atPath: $0.url.path) }
        if kept != items {
            items = kept
            save()
        }
    }

    private func save() {
        UserDefaults.standard.set(items.map(\.url.path), forKey: Self.defaultsKey)
    }

    #if DEBUG
    /// Sample data for README images; not saved.
    func previewLoad(_ urls: [URL]) { items = urls.map(ShelfItem.init(url:)) }
    #endif
}
