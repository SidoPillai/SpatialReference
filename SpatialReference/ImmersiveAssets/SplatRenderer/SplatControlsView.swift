//
//  SplatControlsView.swift
//  SpatialReference
//

import SwiftUI

/// The splat space's floating toolbar, in a small window of its own since a
/// Metal layer can't host SwiftUI. It also loads whichever capture is active,
/// and closes with the space.
struct SplatControlsView: View {

    @Environment(AppModel.self) private var appModel
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow

    @State private var openCard: Card?

    enum Card { case exposure, music, info }

    private var viewer: SplatViewer { appModel.splatViewer }

    var body: some View {
        @Bindable var viewer = viewer
        VStack(spacing: 10) {
            if let openCard {
                EnvironmentToolbar.card {
                    switch openCard {
                    case .exposure: ExposureCard(exposure: $viewer.exposure)
                    case .music: BackgroundMusicCard()
                    case .info: infoCard
                    }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .bottom)))
            }
            if let status {
                EnvironmentToolbar.status(status.text, systemImage: status.symbol)
            }
            HStack(spacing: 4) {
                EnvironmentToolbar.button("Close", systemImage: "xmark") {
                    Task { await appModel.dismissOpenImmersiveSpace(using: dismissImmersiveSpace) }
                }
                .disabled(appModel.isImmersiveSpaceInTransition)
                EnvironmentToolbar.divider
                EnvironmentToolbar.button("Previous", systemImage: "chevron.left") { step(-1) }
                    .disabled(appModel.steppableEnvironmentIDs.count < 2 || appModel.isImmersiveSpaceInTransition)
                EnvironmentToolbar.button("Next", systemImage: "chevron.right") { step(1) }
                    .disabled(appModel.steppableEnvironmentIDs.count < 2 || appModel.isImmersiveSpaceInTransition)
                EnvironmentToolbar.divider
                EnvironmentToolbar.button("Recenter", systemImage: "arrow.counterclockwise") { viewer.recenter() }
                EnvironmentToolbar.button("Turn", systemImage: "rotate.right") { viewer.turn() }
                EnvironmentToolbar.button("Flip upside down", systemImage: "arrow.up.and.down", isOn: viewer.isFlipped) { viewer.toggleFlip() }
                EnvironmentToolbar.divider
                EnvironmentToolbar.button("Exposure", systemImage: "sun.max", isOn: openCard == .exposure) { toggle(.exposure) }
                EnvironmentToolbar.button("Music", systemImage: "music.note", isOn: openCard == .music) { toggle(.music) }
                EnvironmentToolbar.button("Info", systemImage: "info.circle", isOn: openCard == .info) { toggle(.info) }
            }
            .padding(6)
            .glassBackgroundEffect(in: Capsule())
        }
        .frame(width: 600, alignment: .bottom)
        .animation(.easeInOut(duration: 0.2), value: openCard)
        .task(id: appModel.activeEnvironmentID) {
            guard let env = appModel.activeEnvironment, case .pointCloud(let url) = env.content else { return }
            await viewer.load(url)
        }
        .onChange(of: appModel.splatSpaceState) { _, state in
            if state == .closed { dismissWindow(id: appModel.splatControlsWindowID) }
        }
        .onDisappear {
            // Closing the toolbar leaves nothing to get out with.
            if appModel.splatSpaceState == .open {
                Task { await appModel.dismissOpenImmersiveSpace(using: dismissImmersiveSpace) }
            }
        }
    }

    private var status: (text: String, symbol: String)? {
        switch viewer.phase {
        case .loading: ("Loading…", "hourglass")
        case .failed(let message): (message, "exclamationmark.triangle")
        case .idle, .ready: nil
        }
    }

    private func step(_ offset: Int) {
        Task {
            await appModel.showAdjacentEnvironment(offset, using: .init(openSpace: openImmersiveSpace, dismissSpace: dismissImmersiveSpace, openWindow: openWindow))
        }
    }

    private func toggle(_ card: Card) {
        openCard = openCard == card ? nil : card
    }

    @ViewBuilder
    private var infoCard: some View {
        if let env = appModel.activeEnvironment {
            VStack(alignment: .leading, spacing: 4) {
                Text(env.title).font(.title3.bold()).lineLimit(2)
                Text(env.subtitle).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 8) {
                ForEach(infoRows, id: \.0) { row in
                    LabeledContent(row.0, value: row.1)
                }
            }
            .font(.system(size: 15))
            Text(viewer.isGaussianSplat
                 ? "Life size, seen from where it was captured · Recenter after you move"
                 : "Life size · Recenter after you move")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
        }
    }

    private var infoRows: [(String, String)] {
        var rows: [(String, String)] = []
        if viewer.splatCount > 0 {
            rows.append((viewer.isGaussianSplat ? "Splats" : "Points", viewer.splatCount.formatted()))
        }
        if let performance = viewer.performance {
            rows.append(("Rendering", performance))
        }
        if viewer.exposure != 0 {
            rows.append(("Exposure", viewer.exposure.formatted(.number.precision(.fractionLength(1)).sign(strategy: .always()))))
        }
        if viewer.isFlipped { rows.append(("Orientation", "Upside down")) }
        return rows
    }
}

#if DEBUG
/// For measuring on device without the UI: launching with
/// `-SplatAutoOpen <title>` enters the first imported environment whose
/// title contains that text. `-SplatForceMetal YES` uses the Metal splat
/// space in the simulator too.
struct SplatAutoOpen: ViewModifier {
    @Environment(AppModel.self) private var appModel
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @Environment(\.openWindow) private var openWindow

    func body(content: Content) -> some View {
        content.task {
            // `-SplatImport <path>` first imports a file, for the simulator.
            if let path = UserDefaults.standard.string(forKey: "SplatImport"),
               !appModel.importedEnvironments.items.contains(where: { $0.title == ((path as NSString).lastPathComponent as NSString).deletingPathExtension }) {
                _ = try? await appModel.importedEnvironments.add(from: URL(filePath: path))
            }
            guard let query = UserDefaults.standard.string(forKey: "SplatAutoOpen"),
                  let item = appModel.importedEnvironments.items.first(where: { $0.title.localizedCaseInsensitiveContains(query) }) else { return }
            try? await Task.sleep(for: .seconds(1))
            await appModel.enterEnvironment(item.id, using: .init(openSpace: openImmersiveSpace, dismissSpace: dismissImmersiveSpace, openWindow: openWindow))
        }
    }
}
#endif
