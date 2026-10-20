import Foundation
import SwiftUI

/// Extensions lues par le lecteur vidéo de l'iPhone
let videoExtensions: Set<String> = ["mp4", "m4v", "mov", "3gp"]

struct VideoItem: Identifiable, Hashable {
    let path: String            // dossier : chemin relatif ; fichiers : identifiant unique
    let label: String           // nom du fichier
    var id: String { path }
    var name: String { (label as NSString).deletingPathExtension }
    var folder: String { (path as NSString).deletingLastPathComponent.hasPrefix("§") ? "" : (path as NSString).deletingLastPathComponent }

    init(path: String) { self.path = path; self.label = (path as NSString).lastPathComponent }
    init(fileId: String, label: String) { self.path = fileId; self.label = label }
}

/// Deux façons d'ajouter des vidéos :
/// - un dossier (emplacements Apple : Sur mon iPhone, iCloud Drive), sous-dossiers inclus ;
/// - des fichiers choisis un par un (Cryptomator, OneDrive… qui ne permettent pas de choisir un dossier).
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

    private var allItems: [VideoItem] = []
    private var fileURLs: [String: URL] = [:]       // vidéos choisies une par une
    private var fileBookmarks: [String: Data] = [:]
    private var scanTask: Task<Void, Never>?

    var hasSource: Bool { rootURL != nil || !fileURLs.isEmpty }

    init() {
        shuffle = UserDefaults.standard.bool(forKey: "shuffle")
        restore()
    }

    func url(for item: VideoItem) -> URL? {
        if let u = fileURLs[item.id] { return u }
        return rootURL?.appendingPathComponent(item.path)
    }

    var currentIndex: Int {
        guard let c = current else { return -1 }
        return items.firstIndex(where: { $0.id == c }) ?? -1
    }

    // MARK: Mode dossier

    func setRoot(_ url: URL) {
        guard url.startAccessingSecurityScopedResource() else {
            errorMessage = "L'accès au dossier a été refusé."
            return
        }
        clearAll()
        if let data = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
            UserDefaults.standard.set(data, forKey: "rootBookmark")
        }
        rootURL = url
        rebuildToken += 1
        rescan(known: nil)
    }

    // MARK: Mode fichiers

    /// Ajoute des vidéos choisies dans le sélecteur. replace = true remplace la sélection actuelle.
    func addFiles(_ urls: [URL], replace: Bool) {
        if replace { clearAll() }
        var fresh: [VideoItem] = []
        let known = Set(fileBookmarks.values)
        for url in urls {
            let ok = url.startAccessingSecurityScopedResource()
            defer { if ok { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil),
                  !known.contains(data) else { continue }
            let id = "§" + UUID().uuidString + "/" + url.lastPathComponent
            fileBookmarks[id] = data
            fileURLs[id] = url
            fresh.append(VideoItem(fileId: id, label: url.lastPathComponent))
        }
        fresh.sort { $0.label.localizedStandardCompare($1.label) == .orderedAscending }
        saveBookmarks()
        if fresh.isEmpty && !replace { return }
        errorMessage = nil
        if items.isEmpty || replace {
            allItems = fresh
            items = shuffle ? fresh.shuffled() : fresh
            rebuildToken += 1
        } else {
            append(fresh)
        }
    }

    private func clearAll() {
        scanTask?.cancel()
        scanning = false
        rootURL?.stopAccessingSecurityScopedResource()
        rootURL = nil
        UserDefaults.standard.removeObject(forKey: "rootBookmark")
        fileURLs = [:]
        fileBookmarks = [:]
        saveBookmarks()
        allItems = []
        items = []
        current = nil
        saveCache([])
    }

    func forget() {
        clearAll()
        rebuildToken += 1
    }

    // MARK: Restauration au lancement

    private func restore() {
        // Fichiers choisis un par un
        if let data = try? Data(contentsOf: bookmarksURL),
           let saved = try? JSONDecoder().decode([String: Data].self, from: data), !saved.isEmpty {
            var list: [VideoItem] = []
            for (id, bm) in saved {
                var stale = false
                guard let url = try? URL(resolvingBookmarkData: bm, options: [], relativeTo: nil, bookmarkDataIsStale: &stale) else { continue }
                fileURLs[id] = url
                fileBookmarks[id] = bm
                list.append(VideoItem(fileId: id, label: url.lastPathComponent))
            }
            list.sort { $0.label.localizedStandardCompare($1.label) == .orderedAscending }
            allItems = list
            items = shuffle ? list.shuffled() : list
            return
        }
        // Dossier
        guard let data = UserDefaults.standard.data(forKey: "rootBookmark") else { return }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale),
              url.startAccessingSecurityScopedResource() else { return }
        if stale, let fresh = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
            UserDefaults.standard.set(fresh, forKey: "rootBookmark")
        }
        rootURL = url
        let cached = loadCache()
        allItems = cached.map(VideoItem.init(path:))
        items = shuffle ? allItems.shuffled() : allItems
        rescan(known: Set(cached))
    }

    // MARK: Analyse du dossier

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
                    self?.append(batch.map(VideoItem.init(path:)))
                    batch = []
                    last = Date()
                }
            }
            guard let self, !Task.isCancelled else { return }
            if !batch.isEmpty { self.append(batch.map(VideoItem.init(path:))) }
            let foundSet = Set(found)
            let cur = self.current
            self.items.removeAll { !foundSet.contains($0.id) && $0.id != cur }
            self.allItems = found.map(VideoItem.init(path:))
            self.saveCache(found)
            self.scanning = false
        }
    }

    private func append(_ incoming: [VideoItem]) {
        let existing = Set(allItems.map(\.id))
        let fresh = incoming.filter { !existing.contains($0.id) }
        allItems += fresh
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
        var list = allItems
        if on {
            list.shuffle()
            if let c = current, let i = list.firstIndex(where: { $0.id == c }) {
                list.insert(list.remove(at: i), at: 0)
            }
        }
        items = list
        rebuildToken += 1
    }

    // MARK: Stockage (protégé par le chiffrement de l'iPhone)

    private var supportDir: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    }
    private var cacheURL: URL { supportDir.appendingPathComponent("index.json") }
    private var bookmarksURL: URL { supportDir.appendingPathComponent("files.json") }

    private func write(_ data: Data?, to url: URL) {
        try? FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)
        try? data?.write(to: url, options: [.atomic, .completeFileProtection])
    }

    private func saveCache(_ paths: [String]) { write(try? JSONEncoder().encode(paths), to: cacheURL) }

    private func loadCache() -> [String] {
        guard let data = try? Data(contentsOf: cacheURL) else { return [] }
        return (try? JSONDecoder().decode([String].self, from: data)) ?? []
    }

    private func saveBookmarks() {
        if fileBookmarks.isEmpty { try? FileManager.default.removeItem(at: bookmarksURL); return }
        write(try? JSONEncoder().encode(fileBookmarks), to: bookmarksURL)
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
