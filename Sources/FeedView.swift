import SwiftUI
import AVFoundation
import UIKit

struct FeedView: View {
    @EnvironmentObject var library: Library
    @EnvironmentObject var pool: PlayerPool
    let pick: (PickAction) -> Void

    @State private var position: String?
    @State private var scrubbing = false
    @State private var scrubValue: Double = 0
    @State private var showMenu = false
    private let speeds: [Float] = [1, 1.25, 1.5, 2, 0.5]

    var body: some View {
        ScrollViewReader { proxy in
            ZStack {
                Color.black.ignoresSafeArea()

                if library.items.isEmpty {
                    VStack(spacing: 14) {
                        if library.scanning { ProgressView().tint(.white) }
                        Text(library.scanning ? "Recherche des vidéos…" : "Aucune vidéo trouvée dans ce dossier.")
                            .foregroundStyle(.secondary)
                        if !library.scanning {
                            Button("Choisir d'autres vidéos") { pick(.files(replace: true)) }
                                .buttonStyle(.borderedProminent).tint(.pink)
                        }
                    }
                } else {
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVStack(spacing: 0) {
                            ForEach(library.items) { item in
                                VideoPage(item: item)
                                    .containerRelativeFrame([.horizontal, .vertical])
                                    .id(item.id)
                            }
                        }
                        .scrollTargetLayout()
                    }
                    .scrollTargetBehavior(.paging)
                    .scrollPosition(id: $position)
                    .ignoresSafeArea()
                }

                controls

                if let f = pool.flash {
                    Text(f)
                        .font(.title.bold())
                        .padding(.horizontal, 22).padding(.vertical, 14)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.2), value: pool.flash)
            .onAppear {
                if position == nil { position = library.current ?? library.items.first?.id }
                focus()
            }
            .onChange(of: position) { _, _ in
                library.current = position
                focus()
            }
            .onChange(of: library.items.count) { _, _ in
                if position == nil || !library.items.contains(where: { $0.id == position }) {
                    position = library.items.first?.id
                }
                focus()
            }
            .onChange(of: library.rebuildToken) { _, _ in
                if position == nil || !library.items.contains(where: { $0.id == position }) {
                    position = library.items.first?.id
                }
                if let p = position {
                    DispatchQueue.main.async { proxy.scrollTo(p, anchor: .top) }
                }
                focus()
            }
        }
        .confirmationDialog("Vidéos", isPresented: $showMenu) {
            Button("Ajouter des vidéos") { pick(.files(replace: false)) }
            Button("Remplacer par d'autres vidéos") { pick(.files(replace: true)) }
            Button("Choisir un dossier") { pick(.folder) }
            if library.rootURL != nil {
                Button("Réanalyser le dossier") { library.rescan(known: Set(library.items.map(\.id))) }
            }
            Button("Tout retirer", role: .destructive) { pool.reset(); library.forget() }
            Button("Annuler", role: .cancel) {}
        }
        .statusBarHidden()
    }

    private func focus() {
        guard let id = position, let i = library.items.firstIndex(where: { $0.id == id }) else { return }
        pool.focus(on: i, in: library.items, urlFor: library.url(for:))
    }

    // MARK: Commandes superposées

    private var currentItem: VideoItem? {
        guard let id = position else { return nil }
        return library.items.first(where: { $0.id == id })
    }

    private var controls: some View {
        VStack(spacing: 0) {
            // Barre du haut
            HStack {
                Text(counterText)
                    .font(.footnote.monospacedDigit())
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(.black.opacity(0.45), in: Capsule())
                Spacer()
                HStack(spacing: 8) {
                    roundButton(pool.muted ? "speaker.slash.fill" : "speaker.wave.2.fill") {
                        pool.muted.toggle()
                        pool.showFlash(pool.muted ? "Son coupé" : "Son activé")
                    }
                    roundButton("shuffle", highlighted: library.shuffle) {
                        library.setShuffle(!library.shuffle)
                        pool.showFlash(library.shuffle ? "Aléatoire" : "Ordre normal")
                    }
                    Button {
                        let i = speeds.firstIndex(of: pool.rate) ?? 0
                        pool.rate = speeds[(i + 1) % speeds.count]
                    } label: {
                        Text(speedLabel)
                            .font(.subheadline.bold().monospacedDigit())
                            .frame(minWidth: 44, minHeight: 44)
                            .padding(.horizontal, 4)
                            .background(.black.opacity(0.45), in: Capsule())
                    }
                    roundButton("folder") { showMenu = true }
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
            .padding(.bottom, 28)
            .background(
                LinearGradient(colors: [.black.opacity(0.6), .clear], startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            )

            Spacer(minLength: 0)

            // Barre du bas
            VStack(alignment: .leading, spacing: 6) {
                if let item = currentItem {
                    if !item.folder.isEmpty {
                        Text(item.folder.replacingOccurrences(of: "/", with: " / "))
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Text(item.name).font(.subheadline.bold()).lineLimit(1)
                }
                HStack(spacing: 8) {
                    Button { pool.seek(by: -10) } label: { pillLabel("−10") }
                    Slider(value: Binding(
                        get: { scrubbing ? scrubValue : (pool.duration > 0 ? pool.time / pool.duration : 0) },
                        set: { v in
                            scrubValue = v
                            pool.seek(toFraction: v)
                        }
                    ), in: 0...1, onEditingChanged: { editing in
                        scrubbing = editing
                        pool.scrubbing = editing
                    })
                    .tint(.pink)
                    Button { pool.seek(by: 10) } label: { pillLabel("+10") }
                }
                Text("\(format(scrubbing ? scrubValue * pool.duration : pool.time)) / \(format(pool.duration))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(.horizontal, 14)
            .padding(.top, 36)
            .padding(.bottom, 6)
            .background(
                LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            )
        }
        .foregroundStyle(.white)
        .opacity(library.items.isEmpty ? 0 : 1)
    }

    private var counterText: String {
        let i = position.flatMap { id in library.items.firstIndex(where: { $0.id == id }) }.map { $0 + 1 } ?? 0
        return "\(i) / \(library.items.count)" + (library.scanning ? " · analyse…" : "")
    }

    private var speedLabel: String {
        pool.rate == 1 ? "1x" : String(format: "%gx", Double(pool.rate))
    }

    private func roundButton(_ symbol: String, highlighted: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 44, height: 44)
                .background(highlighted ? Color.pink : Color.black.opacity(0.45), in: Circle())
        }
    }

    private func pillLabel(_ text: String) -> some View {
        Text(text)
            .font(.subheadline.bold().monospacedDigit())
            .frame(minWidth: 44, minHeight: 36)
            .padding(.horizontal, 4)
            .background(.black.opacity(0.45), in: Capsule())
    }

    private func format(_ t: Double) -> String {
        guard t.isFinite, t > 0 else { return "0:00" }
        let s = Int(t)
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec)
    }
}

// MARK: Une page = une vidéo

struct VideoPage: View {
    let item: VideoItem
    @EnvironmentObject var pool: PlayerPool

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black
                if let p = pool.players[item.id] {
                    PlayerLayerView(player: p)
                } else if let err = pool.failed[item.id] {
                    VStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle").font(.title)
                        Text(err).font(.callout)
                        Text(item.name).font(.caption).foregroundStyle(.secondary)
                    }
                    .multilineTextAlignment(.center)
                    .padding()
                } else {
                    ProgressView().tint(.white)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture(count: 2) { location in
                let x = location.x / max(geo.size.width, 1)
                if x < 0.35 { pool.seek(by: -10) }
                else if x > 0.65 { pool.seek(by: 10) }
                else { pool.togglePlay() }
            }
            .onTapGesture { pool.togglePlay() }
        }
    }
}

struct PlayerLayerView: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerUIView {
        let view = PlayerUIView()
        view.backgroundColor = .black
        view.playerLayer.videoGravity = .resizeAspect
        view.playerLayer.player = player
        return view
    }

    func updateUIView(_ view: PlayerUIView, context: Context) {
        if view.playerLayer.player !== player { view.playerLayer.player = player }
    }
}

final class PlayerUIView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}
