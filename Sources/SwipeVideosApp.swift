import SwiftUI
import AVFoundation
import UniformTypeIdentifiers

@main
struct SwipeVideosApp: App {
    @StateObject private var library = Library()
    @StateObject private var pool = PlayerPool()

    init() {
        // Le son joue même si l'iPhone est en mode silencieux
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(library)
                .environmentObject(pool)
                .preferredColorScheme(.dark)
        }
    }
}

enum PickAction: Equatable {
    case folder
    case files(replace: Bool)
}

struct RootView: View {
    @EnvironmentObject var library: Library
    @EnvironmentObject var pool: PlayerPool
    @Environment(\.scenePhase) private var scenePhase
    @State private var picking = false
    @State private var action: PickAction = .files(replace: true)

    private func pick(_ a: PickAction) {
        action = a
        picking = true
    }

    private var types: [UTType] {
        action == .folder ? [.folder] : [.movie, .video, .mpeg4Movie, .quickTimeMovie]
    }

    var body: some View {
        Group {
            if !library.hasSource {
                StartView(pick: pick)
            } else {
                FeedView(pick: pick)
            }
        }
        .fileImporter(isPresented: $picking, allowedContentTypes: types, allowsMultipleSelection: action != .folder) { result in
            guard case .success(let urls) = result, !urls.isEmpty else { return }
            switch action {
            case .folder:
                pool.reset()
                library.setRoot(urls[0])
            case .files(let replace):
                if replace { pool.reset() }
                library.addFiles(urls, replace: replace)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { pool.resume() } else { pool.pauseAll() }
        }
    }
}

struct StartView: View {
    @EnvironmentObject var library: Library
    let pick: (PickAction) -> Void

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "play.rectangle.on.rectangle.fill")
                .font(.system(size: 56))
                .foregroundStyle(.pink)
            Text("Swipe Vidéos")
                .font(.largeTitle.bold())
            Text("Déverrouille d'abord ton coffre dans Cryptomator. Ouvre-le, touche « Sélectionner », puis « Tout sélectionner ». L'app se souviendra de ta sélection.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 340)
            Toggle("Ordre aléatoire", isOn: Binding(
                get: { library.shuffle },
                set: { library.shuffle = $0 }
            ))
            .tint(.pink)
            .frame(maxWidth: 260)
            Button { pick(.files(replace: true)) } label: {
                Label("Choisir des vidéos", systemImage: "film.stack")
                    .font(.headline)
                    .frame(maxWidth: 280)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .tint(.pink)
            Button { pick(.folder) } label: {
                Label("Choisir un dossier", systemImage: "folder")
                    .frame(maxWidth: 280)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.bordered)
            Text("Le choix d'un dossier entier, sous-dossiers inclus, fonctionne pour « Sur mon iPhone » et « iCloud Drive ».")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
            if let err = library.errorMessage {
                Text(err).font(.footnote).foregroundStyle(.red)
            }
            Spacer()
            Text("Tout reste sur ton iPhone.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}
