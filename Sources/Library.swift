import Foundation
import SwiftUI

/// Extensions lues par le lecteur vidéo de l'iPhone
let videoExtensions: Set<String> = ["mp4", "m4v", "mov", "3gp"]

struct VideoItem: Identifiable, Hashable {
    let path: String            // chemin relatif au dossier choisi
    var id: String { path }
    var name: String { ((path as NSString).lastPathComponent as NSString).deletingPathExtension }
    var folder: String { (path as NSString).deletingLastPathComponent }
}

/// Liste des vidéos du dossier choisi : mémorisée, puis vérifiée en arrière-plan
@MainActor
final class Library: ObservableObject {
    @Published private(set) var rootURL: URL?
    @Published private(set) var items: [VideoItem] = []
    @Published private(set) var scanning = false
    @Published private(set) var rebuildToken = 0
    @Published var errorMessage: String?
    @Published var current: String?
    @Published var shuffle: Bool {
        didSet { UserDefaults.standard.set(shuffle, forKey: "shuffle") }
    }

    private var allPaths: [String] = []
    private var scanTask: Task<Void, Never>?

    init() {
        shuffle = UserDefaults.standard.bool(forKey: "shuffle")
        restore()
    }

    func url(for item: VideoItem) -> URL? {
        rootURL?.appendingPathComponent(item.path)
    }

    var currentIndex: Int {
        guard let c = current else { return -1 }
        return items.firstIndex(where: { $0.id == c }) ?? -1
    }

    // MARK: Dossier

    func setRoot(_ url: URL) {
        guard url.startAccessingSecurityScopedResource() else {
            errorMessage = "L'accès au dossier a été refusé. Vérifie que le coffre est déverrouillé."
            return
        }
        if let old = rootURL, old != url { old.stopAccessingSecurityScopedResource() }
        if let data = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
            UserDefaults.standard.set(data, forKey: "rootBookmark")
        }
        errorMessage = nil
        rootURL = url
        allPaths = []
        items = []
        current = nil
        saveCache([])
        rebuildToken += 1
        rescan(known: nil)
    }

    private func restore() {
        guard let data = UserDefaults.standard.data(forKey: "rootBookmark") else { return }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale),
              url.startAccessingSecurityScopedResource() else { return }
        if stale, let fresh = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
            UserDefaults.standard.set(fresh, forKey: "rootBookmark")
        }
        rootURL = url
        let cached = loadCache()
        allPaths = cached
        var list = cached.map(VideoItem.init(path:))
        if shuffle { list.shuffle() }
        items = list
        rescan(known: Set(cached))
    }

    // MARK: Analyse

    func rescan(known: Set<String>?) {
        scanTask?.cancel()
        guard let root = rootURL else { return }
        scanning = true
        scanTask = Task { [weak self] in
            var found: [String] = []
            var batch: [String] = []
            var last = Date()
            for await path in scanFolder(root) {
                if Task.isCancelled { return }
                found.append(path)
                if known?.contains(path) != true { batch.append(path) }
                let firstOnes = self?.items.isEmpty ?? false
                if !batch.isEmpty && (firstOnes || Date().timeIntervalSince(last) > 0.4) {
                    self?.append(batch)
                    batch = []
                    last = Date()
                }
            }
            guard let self, !Task.isCancelled else { return }
            if !batch.isEmpty { self.append(batch) }
            // Retire les vidéos qui n'existent plus
            let foundSet = Set(found)
            let cur = self.current
            self.items.removeAll { !foundSet.contains($0.id) && $0.id != cur }
            self.allPaths = found
            self.saveCache(found)
            self.scanning = false
        }
    }

    private func append(_ paths: [String]) {
        allPaths += paths
        let fresh = paths.map(VideoItem.init(path:))
        if shuffle {
            if items.isEmpty {
                items = fresh.shuffled()
            } else {
                for item in fresh {
                    let pos = Int.random(in: (currentIndex + 1)...items.count)
                    items.insert(item, at: pos)
                }
            }
        } else {
            items += fresh
        }
    }

    func setShuffle(_ on: Bool) {
        shuffle = on
        var list = allPaths.map(VideoItem.init(path:))
        if on {
            list.shuffle()
            if let c = current, let i = list.firstIndex(where: { $0.id == c }) {
                list.insert(list.remove(at: i), at: 0)
            }
        }
        items = list
        rebuildToken += 1
    }

    // MARK: Cache (protégé par le chiffrement de l'iPhone)

    private var cacheURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("index.json")
    }

    private func saveCache(_ paths: [String]) {
        try? FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(paths).write(to: cacheURL, options: [.atomic, .completeFileProtection])
    }

    private func loadCache() -> [String] {
        guard let data = try? Data(contentsOf: cacheURL) else { return [] }
        return (try? JSONDecoder().decode([String].self, from: data)) ?? []
    }
}

// MARK: Parcours du dossier, hors du fil principal

func scanFolder(_ root: URL) -> AsyncStream<String> {
    AsyncStream { continuation in
        let task = Task.detached(priority: .userInitiated) {
            walkFolder(root, prefix: "", continuation: continuation)
            continuation.finish()
        }
        continuation.onTermination = { _ in task.cancel() }
    }
}

private func walkFolder(_ dir: URL, prefix: String, continuation: AsyncStream<String>.Continuation) {
    if Task.isCancelled { return }
    let fm = FileManager.default
    guard let entries = try? fm.contentsOfDirectory(at: dir,
                                                     includingPropertiesForKeys: [.isDirectoryKey],
                                                     options: [.skipsHiddenFiles]) else { return }
    var files: [String] = []
    var dirs: [URL] = []
    for entry in entries {
        let isDir = (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
        if isDir {
            dirs.append(entry)
        } else if videoExtensions.contains(entry.pathExtension.lowercased()) {
            files.append(entry.lastPathComponent)
        }
    }
    files.sort { $0.localizedStandardCompare($1) == .orderedAscending }
    dirs.sort { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    for f in files { continuation.yield(prefix + f) }
    for d in dirs { walkFolder(d, prefix: prefix + d.lastPathComponent + "/", continuation: continuation) }
}
