//
//  AssetViewerImmersiveView.swift
//  SpatialReference
//

import SwiftUI
import RealityKit

/// Mixed-immersion space hosting gesture-manipulable 3D content.
///
/// Milestone-1 content is the template's placeholder "Immersive" scene
/// (two grid spheres) since the demo StoryMap chosen for this milestone
/// doesn't itself embed a USDZ asset — its media are web maps/images. Each
/// top-level entity in the scene gets pinch-move/rotate/hand-off gestures
/// via RealityKit's Manipulation component, which is what a real chapter
/// asset would also get once story content includes one.
struct AssetViewerImmersiveView: View {

    var body: some View {
        RealityView { content in
            if let immersiveContentEntity = try? await Entity(named: "Immersive", in: .main) {
                for child in immersiveContentEntity.children {
                    child.generateCollisionShapes(recursive: true)
                    child.components.set(InputTargetComponent())
                    ManipulationComponent.configureEntity(child)
                }
                content.add(immersiveContentEntity)
            }
        }
    }
}

#Preview(immersionStyle: .mixed) {
    AssetViewerImmersiveView()
        .environment(AppModel())
}
