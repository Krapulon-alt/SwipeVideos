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

struct RootView: View {
    @EnvironmentObject var library: Library
    @EnvironmentObject var pool: PlayerPool
    @Environment(\.scenePhase) private var scenePhase
    @State private var picking = false

    var body: some View {
        Group {
            if library.rootURL == nil {
                StartView(pick: { picking = true })
            } else {
                FeedView(pick: { picking = true })
            }
        }
        .fileImporter(isPresented: $picking, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result {
                pool.reset()
                library.setRoot(url)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { pool.resume() } else { pool.pauseAll() }
        }
    }
}

struct StartView: View {
    @EnvironmentObject var library: Library
    let pick: () -> Void

    var body: some View {
        VStack(spacing: 22) {
            Spacer()
            Image(systemName: "play.rectangle.on.rectangle.fill")
                .font(.system(size: 56))
                .foregroundStyle(.pink)
            Text("Swipe Vidéos")
                .font(.largeTitle.bold())
            Text("Choisis une fois le dossier de tes vidéos, par exemple dans ton coffre Cryptomator. Les sous-dossiers sont inclus et l'app s'en souviendra.")
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
            Button(action: pick) {
                Label("Choisir le dossier", systemImage: "folder")
                    .font(.headline)
                    .frame(maxWidth: 280)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .tint(.pink)
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
