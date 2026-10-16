//
//  SpatialReferenceApp.swift
//  SpatialReference
//
//  Created by Siddesh Pillai on 9/28/26.
//

import CompositorServices
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
            #if DEBUG
            .modifier(SplatAutoOpen())
            #endif
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

        ImmersiveSpace(id: appModel.environmentSpaceID) {
            EnvironmentImmersiveView()
                .environment(appModel)
                .onAppear {
                    appModel.environmentSpaceState = .open
                }
                .onDisappear {
                    appModel.environmentSpaceState = .closed
                    // Unless it's already moved on to a splat capture.
                    if let env = appModel.activeEnvironment, appModel.spaceID(for: env) == appModel.environmentSpaceID {
                        appModel.activeEnvironmentID = nil
                    }
                }
        }
        // Panoramas are progressive: the Digital Crown dials them from a
        // portal in front of you up to fully surrounding you. Imported
        // models are mixed, so they sit in your room.
        .immersionStyle(selection: Binding<any ImmersionStyle>(
            get: { appModel.activeEnvironment?.isModel == true ? MixedImmersionStyle() as any ImmersionStyle : ProgressiveImmersionStyle() },
            set: { _ in }
        ), in: .mixed, .progressive)

        // Splat captures, life size and drawn with Metal, in the room.
        ImmersiveSpace(id: appModel.splatSpaceID) {
            CompositorLayer(configuration: SplatLayerConfiguration()) { layerRenderer in
                appModel.startSplatLayer(layerRenderer)
            }
        }
        .immersionStyle(selection: .constant(.mixed), in: .mixed)

        WindowGroup(id: appModel.splatControlsWindowID) {
            SplatControlsView()
                .environment(appModel)
        }
        .windowStyle(.plain)
        .windowResizability(.contentSize)
        .defaultWindowPlacement { _, _ in
            WindowPlacement(.utilityPanel)
        }
        // It only makes sense with the splat space open, which never comes
        // back on relaunch; otherwise it reopens alone, empty, and hides the
        // main window.
        .restorationBehavior(.disabled)
        .defaultLaunchBehavior(.suppressed)
    }
}
