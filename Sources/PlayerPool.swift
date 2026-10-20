import Foundation
import AVFoundation
import SwiftUI

/// Garde en mémoire seulement la vidéo affichée et ses deux voisines
@MainActor
final class PlayerPool: ObservableObject {
    @Published private(set) var players: [String: AVPlayer] = [:]
    @Published private(set) var failed: [String: String] = [:]
    @Published var time: Double = 0
    @Published var duration: Double = 0
    @Published var isPaused = false
    @Published var flash: String?
    @Published var muted: Bool {
        didSet {
            UserDefaults.standard.set(muted, forKey: "muted")
            players.values.forEach { $0.isMuted = muted }
        }
    }
    @Published var rate: Float = 1 {
        didSet { if let p = currentPlayer, !isPaused { p.rate = rate } }
    }
    var scrubbing = false

    private var loading: Set<String> = []
    private var scoped: [String: URL] = [:]
    private var wanted: Set<String> = []
    private var currentId: String?
    private var endObservers: [String: NSObjectProtocol] = [:]
    private var statusObservers: [String: NSKeyValueObservation] = [:]
    private var timeObserver: Any?
    private weak var observedPlayer: AVPlayer?
    private var flashTask: Task<Void, Never>?

    init() {
        muted = UserDefaults.standard.bool(forKey: "muted")
    }

    var currentPlayer: AVPlayer? { currentId.flatMap { players[$0] } }

    // MARK: Mise au point sur la vidéo affichée

    func focus(on index: Int, in items: [VideoItem], urlFor: (VideoItem) -> URL?) {
        guard items.indices.contains(index) else { return }
        let cur = items[index]
        currentId = cur.id
        let near = Array(items[max(0, index - 1)...min(items.count - 1, index + 1)])
        wanted = Set(near.map(\.id))

        for id in players.keys where !wanted.contains(id) { release(id) }
        for item in near {
            if let url = urlFor(item) { prepare(item.id, url: url) }
        }
        for (id, p) in players {
            if id == cur.id {
                p.isMuted = muted
                p.playImmediately(atRate: rate)
                isPaused = false
            } else {
                p.pause()
            }
        }
        observe(players[cur.id])
    }

    private func prepare(_ id: String, url: URL) {
        guard players[id] == nil, !loading.contains(id), failed[id] == nil else { return }
        loading.insert(id)
        // Accès au fichier choisi (sans effet pour un fichier du dossier déjà ouvert)
        if url.startAccessingSecurityScopedResource() { scoped[id] = url }
        Task.detached(priority: .userInitiated) { [weak self] in
            // Demande au coffre de déchiffrer le fichier s'il ne l'est pas encore
            var coordError: NSError?
            var readable = false
            NSFileCoordinator().coordinate(readingItemAt: url, options: [.withoutChanges], error: &coordError) { u in
                readable = FileManager.default.isReadableFile(atPath: u.path)
            }
            let ok = readable && coordError == nil
            await MainActor.run { self?.finish(id, url: url, ok: ok) }
        }
    }

    private func finish(_ id: String, url: URL, ok: Bool) {
        loading.remove(id)
        guard wanted.contains(id), players[id] == nil else { stopScope(id); return }
        guard ok else {
            stopScope(id)
            failed[id] = "Fichier inaccessible. Le coffre est-il déverrouillé ?"
            return
        }
        let p = AVPlayer(url: url)
        p.isMuted = muted
        p.actionAtItemEnd = .none
        endObservers[id] = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: p.currentItem, queue: .main
        ) { [weak p] _ in
            p?.seek(to: .zero)
            p?.play()
        }
        statusObservers[id] = p.currentItem?.observe(\.status, options: [.new]) { [weak self] item, _ in
            if item.status == .failed {
                Task { @MainActor in self?.markFailed(id) }
            }
        }
        players[id] = p
        if id == currentId {
            p.playImmediately(atRate: rate)
            isPaused = false
            observe(p)
        }
    }

    private func markFailed(_ id: String) {
        release(id)
        failed[id] = "Format non lu par l'iPhone."
    }

    private func release(_ id: String) {
        guard let p = players[id] else { return }
        if observedPlayer === p { observe(nil) }
        p.pause()
        p.replaceCurrentItem(with: nil)
        if let o = endObservers.removeValue(forKey: id) { NotificationCenter.default.removeObserver(o) }
        statusObservers.removeValue(forKey: id)?.invalidate()
        players[id] = nil
        stopScope(id)
    }

    private func stopScope(_ id: String) {
        scoped.removeValue(forKey: id)?.stopAccessingSecurityScopedResource()
    }

    func reset() {
        for id in players.keys { release(id) }
        for id in scoped.keys { stopScope(id) }
        failed = [:]
        loading = []
        wanted = []
        currentId = nil
    }

    // MARK: Progression

    private func observe(_ p: AVPlayer?) {
        if let o = timeObserver, let op = observedPlayer { op.removeTimeObserver(o) }
        timeObserver = nil
        observedPlayer = p
        guard let p else { time = 0; duration = 0; return }
        timeObserver = p.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.25, preferredTimescale: 600), queue: .main
        ) { [weak self, weak p] t in
            MainActor.assumeIsolated {
                guard let self, let p, !self.scrubbing else { return }
                self.time = t.seconds.isFinite ? t.seconds : 0
                let d = p.currentItem?.duration.seconds ?? 0
                self.duration = d.isFinite ? d : 0
            }
        }
    }

    // MARK: Commandes

    func togglePlay() {
        guard let p = currentPlayer else { return }
        if p.timeControlStatus == .paused {
            p.playImmediately(atRate: rate)
            isPaused = false
            showFlash("▶")
        } else {
            p.pause()
            isPaused = true
            showFlash("❚❚")
        }
    }

    func seek(by seconds: Double) {
        guard let p = currentPlayer, duration > 0 else { return }
        let target = min(max(0, time + seconds), max(0, duration - 0.1))
        p.seek(to: CMTime(seconds: target, preferredTimescale: 600))
        time = target
        showFlash(seconds > 0 ? "+\(Int(seconds)) s" : "−\(Int(-seconds)) s")
    }

    func seek(toFraction f: Double) {
        guard let p = currentPlayer, duration > 0 else { return }
        let target = f * duration
        p.seek(to: CMTime(seconds: target, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        time = target
    }

    func pauseAll() {
        players.values.forEach { $0.pause() }
    }

    func resume() {
        if let p = currentPlayer, !isPaused { p.playImmediately(atRate: rate) }
    }

    func showFlash(_ text: String) {
        flash = text
        flashTask?.cancel()
        flashTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 650_000_000)
            if !Task.isCancelled { self?.flash = nil }
        }
    }
}
