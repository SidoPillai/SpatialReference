//
//  SpatialReferenceApp.swift
//  SpatialReference
//
//  Created by Siddesh Pillai on 9/28/26.
//

import SwiftUI

@main
struct SpatialReferenceApp: App {

    @State private var appModel = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            Group {
                switch appModel.screen {
                case _ where !appModel.hasRestoredSession:
                    WarmBackdrop()
                case .welcome:
                    WelcomeView { appModel.screen = .explore }
                case .explore:
                    ExploreView { appModel.screen = .browser }
                case .browser:
                    StoryBrowserView()
                }
            }
            .environment(appModel)
            .task { await appModel.restoreSession() }
            .onChange(of: scenePhase, initial: true) { _, phase in
                appModel.backgroundMusic.setAppActive(phase != .background)
            }
            .onChange(of: appModel.screen == .browser, initial: true) { _, viewing in
                appModel.backgroundMusic.setViewingItem(viewing)
            }
            .onChange(of: (appModel.narrationPlayer.isSpeaking && !appModel.narrationPlayer.isPaused) || appModel.tourAudio.isPlaying) { _, speaking in
                appModel.backgroundMusic.setDucked(speaking)
            }
        }
        .defaultSize(width: 1280, height: 960)

        WindowGroup(id: appModel.teleportPortalWindowID) {
            PortalSceneView()
                .environment(appModel)
        }
        .windowStyle(.volumetric)
        .defaultSize(width: 1, height: 0.7, depth: 1, in: .meters)

        WindowGroup(id: appModel.tourModelWindowID, for: TourModelReference.self) { $reference in
            if let reference {
                TourModelVolumeView(reference: reference)
                    .environment(appModel)
            }
        }
        .windowStyle(.volumetric)
        .defaultSize(width: 0.6, height: 0.6, depth: 0.6, in: .meters)

        ImmersiveSpace(id: appModel.immersiveSpaceID) {
            AssetViewerImmersiveView()
                .environment(appModel)
                .onAppear {
                    appModel.immersiveSpaceState = .open
                }
                .onDisappear {
                    appModel.immersiveSpaceState = .closed
                }
        }
        .immersionStyle(selection: .constant(.mixed), in: .mixed)
    }
}
