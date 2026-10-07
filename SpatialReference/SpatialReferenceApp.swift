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
            .onChange(of: appModel.narrationPlayer.isSpeaking && !appModel.narrationPlayer.isPaused) { _, speaking in
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
