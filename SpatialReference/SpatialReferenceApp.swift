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

    var body: some Scene {
        WindowGroup {
            Group {
                switch appModel.screen {
                case .welcome:
                    WelcomeView { appModel.screen = .signIn }
                case .signIn:
                    SignInView(
                        onBack: { appModel.screen = .welcome },
                        onSignedIn: { appModel.screen = .explore }
                    )
                case .explore:
                    ExploreView { appModel.screen = .browser }
                case .browser:
                    StoryBrowserView()
                }
            }
            .environment(appModel)
        }

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
