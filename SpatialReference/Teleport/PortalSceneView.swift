//
//  PortalSceneView.swift
//  SpatialReference
//

import SwiftUI
import ArcGIS

/// The "teleport" feature: a volumetric window running ArcGIS's own
/// SceneView, flown to the current chapter's 3D scene and camera
/// viewpoint. This is a real ArcGIS-rendered 3D view in a bounded window
/// (per plan decision), not a RealityKit-immersive replacement of the
/// user's surroundings — the SDK doesn't plug into RealityKit's
/// ImmersiveSpace, so that would need a separate rendering pipeline.
struct PortalSceneView: View {

    @Environment(AppModel.self) private var appModel

    @State private var scene: ArcGIS.Scene?
    @State private var loadError: String?

    var body: some View {
        content
            .task(id: appModel.currentChapter?.id) {
                await load()
            }
    }

    @ViewBuilder
    private var content: some View {
        if let scene {
            SceneView(scene: scene)
                .spaceEffect(.transparent)
        } else if let loadError {
            ContentUnavailableView("Couldn't load scene", systemImage: "exclamationmark.triangle", description: Text(loadError))
        } else {
            ContentUnavailableView(
                "No 3D scene for this chapter",
                systemImage: "view.3d",
                description: Text("Pick a chapter with a scene in the story window to teleport there.")
            )
        }
    }

    private func load() async {
        loadError = nil
        guard case .scene(let itemID, _, let sceneCamera) = appModel.currentChapter?.media,
              let id = Item.ID(itemID) else {
            scene = nil
            return
        }

        let portal = Portal.arcGISOnline(connection: .anonymous)
        let portalItem = PortalItem(portal: portal, id: id)
        let newScene = ArcGIS.Scene(item: portalItem)

        do {
            try await newScene.load()
        } catch {
            scene = nil
            loadError = error.localizedDescription
            return
        }

        // Apply the chapter camera as the scene's initial viewpoint before
        // handing it to SceneView. Calling the SceneViewProxy right after
        // assigning `scene` crashes, because the SceneView hasn't been
        // created yet, so the proxy isn't attached to a view.
        if let sceneCamera, let wkid = WKID(sceneCamera.wkid) {
            let spatialReference = SpatialReference(wkid: wkid)
            let point = Point(x: sceneCamera.x, y: sceneCamera.y, z: sceneCamera.z, spatialReference: spatialReference)
            let camera = Camera(location: point, heading: sceneCamera.heading, pitch: sceneCamera.tilt, roll: 0)
            newScene.initialViewpoint = Viewpoint(boundingGeometry: point, camera: camera)
        }

        scene = newScene
    }
}

#Preview {
    PortalSceneView()
        .environment(AppModel())
}
