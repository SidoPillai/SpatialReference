//
//  TourView.swift
//  SpatialReference
//

import ArcGIS
import RealityKit
import SwiftUI

/// A StoryMaps guided tour: the stops as numbered points on an ArcGIS 3D
/// map, beside a panel for the selected stop with its interactive 3D model,
/// narration text and audio. Picking a stop (from the map, the stop strip or
/// next/previous) flies the map there and starts its narration; when a
/// recording ends the tour moves on to the next stop after a short countdown.
///
/// Layout note: nothing that contains a live 3D model gets an `.overlay`.
/// On visionOS an overlay sits at the front of its view's depth, so a frame
/// or badge laid over a model would float out of the card towards the user.
struct TourView: View {

    static let accent = Color(red: 0.96, green: 0.76, blue: 0.38)
    private static let advanceDelay = 5

    let itemID: String
    let stops: [TourStop]
    let isThreeD: Bool

    @Environment(AppModel.self) private var appModel
    @Environment(\.openWindow) private var openWindow

    @State private var selectedIndex = 0
    @State private var audioError: String?
    @State private var autoAdvance = true
    /// Seconds left before moving on to the next stop, while counting down.
    @State private var countdown: Int?
    @State private var tourFinished = false

    private var stop: TourStop { stops[selectedIndex] }
    private var audio: TourAudioPlayer { appModel.tourAudio }
    private var speech: NarrationPlayer { appModel.narrationPlayer }
    /// The stop has no recording, so its text is read out instead.
    private var usesSpeech: Bool { stop.audioResourceName == nil }
    private var isNarrating: Bool { usesSpeech ? speech.isSpeaking && !speech.isPaused : audio.isPlaying }
    private var narrationProgress: Double { usesSpeech ? speech.progress : audio.progress }

    var body: some View {
        HStack(spacing: 24) {
            mapColumn
            stopPanel
                .frame(width: 470)
        }
        .task(id: selectedIndex) { await narrate() }
        .task(id: countdown) { await tickCountdown() }
        .onChange(of: audio.finishCount) { narrationEnded() }
        .onChange(of: audio.failure) { _, failure in
            guard let failure else { return }
            audioError = failure
            // Drop the unplayable file so the next attempt downloads it again.
            if let url = audio.url { try? FileManager.default.removeItem(at: url) }
        }
        .onDisappear {
            audio.stop()
            speech.stop()
        }
    }

    private func select(_ index: Int) {
        guard stops.indices.contains(index) else { return }
        countdown = nil
        tourFinished = false
        withAnimation(.smooth(duration: 0.45)) { selectedIndex = index }
    }

    // MARK: - Map column

    private var mapColumn: some View {
        TourMapView(stops: stops, selectedIndex: Binding(get: { selectedIndex }, set: { select($0) }), isThreeD: isThreeD)
            .clipShape(RoundedRectangle(cornerRadius: 32))
            .overlay(RoundedRectangle(cornerRadius: 32).strokeBorder(.white.opacity(0.25), lineWidth: 1))
            .overlay(alignment: .topLeading) { tourBadge }
            .overlay(alignment: .bottom) { stopStrip }
    }

    private var tourBadge: some View {
        let total = zip(stops, stops.dropFirst()).reduce(0) { $0 + Self.distance(from: $1.0, to: $1.1) }
        return HStack(spacing: 10) {
            Image(systemName: "point.bottomleft.forward.to.point.topright.scurvepath.fill")
                .foregroundStyle(Self.accent)
            Text("Guided tour")
                .font(.system(size: 15, weight: .semibold))
            Text("\(stops.count) stops · \(Self.format(distance: total))")
                .font(.system(size: 15))
                .foregroundStyle(.white.opacity(0.75))
        }
        .padding(.horizontal, 18)
        .frame(height: 44)
        .glassBackgroundEffect(in: Capsule())
        .padding(20)
    }

    private var stopStrip: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 10) {
                ForEach(Array(stops.enumerated()), id: \.element.id) { index, stop in
                    StopChip(
                        itemID: itemID,
                        index: index,
                        stop: stop,
                        isSelected: index == selectedIndex,
                        isVisited: index < selectedIndex,
                        progress: index == selectedIndex ? narrationProgress : 0
                    ) {
                        select(index)
                    }
                }
            }
            .padding(10)
        }
        .scrollIndicators(.hidden)
        .fixedSize(horizontal: true, vertical: false)
        .glassBackgroundEffect(in: RoundedRectangle(cornerRadius: 28))
        .padding(20)
    }

    // MARK: - Stop panel

    private var stopPanel: some View {
        VStack(alignment: .leading, spacing: 18) {
            stopHeader

            TourModelStage(itemID: itemID, stop: stop)
                .id(stop.id)
                .frame(height: 280)
                .transition(.opacity)

            ScrollView {
                narrationText
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .id(stop.id)
                    .transition(.opacity)
            }
            .scrollIndicators(.hidden)
            .frame(maxHeight: .infinity)

            transportBar
        }
        .padding(24)
        .background {
            StopBackdrop(itemID: itemID, stop: stop)
        }
    }

    private var stopHeader: some View {
        HStack(alignment: .center, spacing: 16) {
            Text("\(selectedIndex + 1)")
                .font(.system(size: 24, weight: .bold, design: .serif))
                .foregroundStyle(.black)
                .frame(width: 52, height: 52)
                .background(Self.accent, in: Circle())
                .overlay(Circle().strokeBorder(.white.opacity(0.7), lineWidth: 2))
                .contentTransition(.numericText())

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text("Stop \(selectedIndex + 1) of \(stops.count)".uppercased())
                        .tracking(2)
                    if selectedIndex > 0 {
                        Text("·")
                        Text("\(Self.format(distance: Self.distance(from: stops[selectedIndex - 1], to: stop))) from stop \(selectedIndex)")
                    }
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.75))
                .lineLimit(1)

                Text(stop.title)
                    .font(.system(size: 30, design: .serif))
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .contentTransition(.opacity)
            }
            Spacer(minLength: 0)

            if let modelName = stop.modelResourceName {
                Button {
                    openWindow(
                        id: appModel.tourModelWindowID,
                        value: TourModelReference(itemID: itemID, resourceName: modelName, title: stop.title)
                    )
                } label: {
                    Image(systemName: "move.3d")
                        .font(.system(size: 18, weight: .semibold))
                        .frame(width: 48, height: 48)
                        .background(.white.opacity(0.14), in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .hoverEffect()
                .help("View in your space")
                .accessibilityLabel("View \(stop.title) in your space")
            }
        }
    }

    /// The stop's text, lit up sentence by sentence as the narration plays.
    private var narrationText: some View {
        Text(narrationAttributedText)
            .font(.system(size: 21, design: .serif))
            .lineSpacing(8)
            .fixedSize(horizontal: false, vertical: true)
            .animation(.easeInOut(duration: 0.4), value: currentSentence?.location)
    }

    /// The sentence being narrated. A recording isn't word-aligned with the
    /// text, so its position is estimated from how far through the audio we are.
    private var currentSentence: NSRange? {
        if usesSpeech {
            return speech.isSpeaking ? speech.highlightedRange : nil
        }
        guard audio.isLoaded, !audio.didFinish, audio.progress > 0 else { return nil }
        let text = stop.narrationText as NSString
        var sentences: [NSRange] = []
        text.enumerateSubstrings(in: NSRange(location: 0, length: text.length), options: .bySentences) { _, range, _, _ in
            sentences.append(range)
        }
        let position = Int(Double(text.length) * audio.progress)
        return sentences.first { NSMaxRange($0) > position } ?? sentences.last
    }

    private var narrationAttributedText: AttributedString {
        let text = stop.narrationText
        var attributed = AttributedString(text)
        attributed.foregroundColor = .white
        guard let current = currentSentence,
              let range = Range(current, in: text),
              let lower = AttributedString.Index(range.lowerBound, within: attributed),
              let upper = AttributedString.Index(range.upperBound, within: attributed) else {
            return attributed
        }
        attributed[attributed.startIndex..<lower].foregroundColor = .white.opacity(0.9)
        attributed[lower..<upper].foregroundColor = Self.accent
        attributed[upper..<attributed.endIndex].foregroundColor = .white.opacity(0.5)
        return attributed
    }

    // MARK: - Transport

    private var transportBar: some View {
        VStack(spacing: 14) {
            statusRow

            HStack(spacing: 10) {
                Text(usesSpeech ? "" : Self.format(audio.currentTime))
                    .frame(width: 44, alignment: .leading)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.18))
                        Capsule()
                            .fill(LinearGradient(colors: [Self.accent.opacity(0.7), Self.accent], startPoint: .leading, endPoint: .trailing))
                            .frame(width: geo.size.width * min(1, max(0, narrationProgress)))
                            .animation(.linear(duration: 0.2), value: narrationProgress)
                    }
                }
                .frame(height: 6)
                Text(usesSpeech || audio.duration == 0 ? "" : "-" + Self.format(max(0, audio.duration - audio.currentTime)))
                    .frame(width: 44, alignment: .trailing)
            }
            .font(.system(size: 13).monospacedDigit())
            .foregroundStyle(.white.opacity(0.8))

            HStack(spacing: 14) {
                roundButton("Previous stop", systemImage: "backward.end.fill", enabled: selectedIndex > 0) {
                    select(selectedIndex - 1)
                }
                roundButton("Back 10 seconds", systemImage: "gobackward.10", enabled: !usesSpeech && audio.isLoaded) {
                    audio.skip(by: -10)
                }

                Button(action: togglePlayback) {
                    Image(systemName: isNarrating ? "pause.fill" : "play.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(.black)
                        .frame(width: 64, height: 64)
                        .background(Self.accent, in: Circle())
                        .contentShape(Circle())
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.plain)
                .hoverEffect()
                .disabled(usesSpeech ? stop.narrationText.isEmpty : !audio.isLoaded)
                .accessibilityLabel(isNarrating ? "Pause narration" : "Play narration")

                roundButton("Forward 10 seconds", systemImage: "goforward.10", enabled: !usesSpeech && audio.isLoaded) {
                    audio.skip(by: 10)
                }
                roundButton("Next stop", systemImage: "forward.end.fill", enabled: selectedIndex < stops.count - 1) {
                    select(selectedIndex + 1)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(18)
        .background(.black.opacity(0.28), in: RoundedRectangle(cornerRadius: 28))
    }

    @ViewBuilder
    private var statusRow: some View {
        HStack(spacing: 10) {
            if let countdown, stops.indices.contains(selectedIndex + 1) {
                Image(systemName: "arrow.turn.down.right")
                    .foregroundStyle(Self.accent)
                Text("Next: \(stops[selectedIndex + 1].title) in \(countdown)s")
                    .lineLimit(1)
                    .contentTransition(.numericText(countsDown: true))
                Spacer(minLength: 0)
                Button("Go now") { select(selectedIndex + 1) }
                    .font(.system(size: 13, weight: .semibold))
                Button("Stay") { self.countdown = nil }
                    .font(.system(size: 13, weight: .semibold))
            } else if tourFinished {
                Image(systemName: "flag.checkered")
                    .foregroundStyle(Self.accent)
                Text("Tour complete")
                Spacer(minLength: 0)
                Button("Start over") { select(0) }
                    .font(.system(size: 13, weight: .semibold))
            } else if let audioError {
                Image(systemName: "exclamationmark.triangle")
                Text(audioError)
                    .lineLimit(2)
                Spacer(minLength: 0)
            } else {
                Image(systemName: "waveform")
                    .foregroundStyle(Self.accent)
                    .symbolEffect(.variableColor.iterative, isActive: isNarrating)
                Text(isNarrating ? "Now narrating" : (usesSpeech || audio.isLoaded ? "Paused" : "Loading narration…"))
                Spacer(minLength: 0)
                Button {
                    autoAdvance.toggle()
                } label: {
                    Label("Auto-advance", systemImage: autoAdvance ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(autoAdvance ? Self.accent : .white.opacity(0.7))
                }
                .buttonStyle(.plain)
                .hoverEffect()
            }
        }
        .font(.system(size: 14, weight: .medium))
        .frame(height: 32)
    }

    private func roundButton(_ label: String, systemImage: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
                .frame(width: 46, height: 46)
                .background(.white.opacity(0.12), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .hoverEffect()
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.35)
        .accessibilityLabel(label)
    }

    // MARK: - Narration

    /// Starts the selected stop's narration: its recording when it has one,
    /// otherwise its text read aloud.
    private func narrate() async {
        audio.stop()
        speech.stop()
        audioError = nil

        guard let audioName = stop.audioResourceName else {
            if !stop.narrationText.isEmpty { speech.speak(stop.narrationText) }
            return
        }
        do {
            let url = try await StoryAssetStore.fileURL(
                itemID: itemID, resourceName: audioName, session: appModel.arcGISSession
            )
            try Task.checkCancellation()
            audio.play(url: url)
        } catch is CancellationError {
            return
        } catch {
            audioError = "Couldn’t load the narration: \(error.localizedDescription)"
        }
    }

    private func narrationEnded() {
        if selectedIndex == stops.count - 1 {
            tourFinished = true
        } else if autoAdvance {
            countdown = Self.advanceDelay
        }
    }

    private func tickCountdown() async {
        guard let remaining = countdown else { return }
        try? await Task.sleep(for: .seconds(1))
        guard !Task.isCancelled, countdown == remaining else { return }
        if remaining <= 1 {
            select(selectedIndex + 1)
        } else {
            withAnimation { countdown = remaining - 1 }
        }
    }

    private func togglePlayback() {
        if usesSpeech {
            if !speech.isSpeaking {
                speech.speak(stop.narrationText)
            } else if speech.isPaused {
                speech.resume()
            } else {
                speech.pause()
            }
        } else {
            countdown = nil
            audio.togglePlayback()
        }
    }

    // MARK: - Formatting

    /// Great-circle distance between two stops, in metres.
    static func distance(from a: TourStop, to b: TourStop) -> Double {
        let radians = Double.pi / 180
        let dLat = (b.latitude - a.latitude) * radians
        let dLon = (b.longitude - a.longitude) * radians
        let h = sin(dLat / 2) * sin(dLat / 2)
            + cos(a.latitude * radians) * cos(b.latitude * radians) * sin(dLon / 2) * sin(dLon / 2)
        return 6_371_000 * 2 * atan2(sqrt(h), sqrt(1 - h))
    }

    static func format(distance meters: Double) -> String {
        let measurement = Measurement(value: meters, unit: UnitLength.meters)
        return measurement.formatted(.measurement(width: .abbreviated, usage: .road, numberFormatStyle: .number.precision(.fractionLength(0))))
    }

    private static func format(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

// MARK: - Stop strip chip

private struct StopChip: View {
    let itemID: String
    let index: Int
    let stop: TourStop
    let isSelected: Bool
    let isVisited: Bool
    let progress: Double
    let action: () -> Void

    @Environment(AppModel.self) private var appModel
    @State private var thumbnail: UIImage?

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ZStack(alignment: .topLeading) {
                    Group {
                        if let thumbnail {
                            Image(uiImage: thumbnail).resizable().scaledToFill()
                        } else {
                            Color.white.opacity(0.1)
                        }
                    }
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 14))

                    Text("\(index + 1)")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(isSelected ? .black : .white)
                        .frame(width: 22, height: 22)
                        .background(isSelected ? TourView.accent : .black.opacity(0.7), in: Circle())
                        .offset(x: -5, y: -5)
                }

                if isSelected {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(stop.title)
                            .font(.system(size: 15, weight: .semibold))
                            .lineLimit(1)
                        Capsule()
                            .fill(.white.opacity(0.2))
                            .frame(width: 150, height: 4)
                            .overlay(alignment: .leading) {
                                Capsule().fill(TourView.accent).frame(width: 150 * min(1, max(0, progress)), height: 4)
                            }
                    }
                    .frame(width: 160, alignment: .leading)
                    .transition(.opacity.combined(with: .move(edge: .leading)))
                }
            }
            .padding(6)
            .padding(.trailing, isSelected ? 10 : 0)
            .background(isSelected ? .white.opacity(0.16) : .clear, in: RoundedRectangle(cornerRadius: 20))
            .opacity(isSelected || !isVisited ? 1 : 0.7)
            .contentShape(RoundedRectangle(cornerRadius: 20))
        }
        .buttonStyle(.plain)
        .hoverEffect()
        .accessibilityLabel("Stop \(index + 1): \(stop.title)")
        .task(id: stop.posterResourceName) {
            thumbnail = await TourImages.image(itemID: itemID, resourceName: stop.posterResourceName, session: appModel.arcGISSession)
        }
    }
}

// MARK: - Backdrop

/// The stop panel's background: the stop's picture, heavily blurred and
/// darkened, cross-fading between stops.
private struct StopBackdrop: View {
    let itemID: String
    let stop: TourStop

    @Environment(AppModel.self) private var appModel
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Color(red: 0.16, green: 0.13, blue: 0.11).opacity(0.75)
            if let image {
                // Fill without letting the image's own size grow the backdrop.
                Color.clear
                    .overlay {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .blur(radius: 40)
                            .opacity(0.55)
                    }
                    .clipped()
                    .transition(.opacity)
            }
            LinearGradient(colors: [.black.opacity(0.05), .black.opacity(0.55)], startPoint: .top, endPoint: .bottom)
        }
        .clipShape(RoundedRectangle(cornerRadius: 32))
        .overlay(RoundedRectangle(cornerRadius: 32).strokeBorder(.white.opacity(0.22), lineWidth: 1))
        .task(id: stop.id) {
            let loaded = await TourImages.image(itemID: itemID, resourceName: stop.posterResourceName, session: appModel.arcGISSession)
            withAnimation(.easeInOut(duration: 0.6)) { image = loaded }
        }
    }
}

/// Decoded stop pictures, shared by the strip, backdrop and model stage so
/// each is read from disk and decoded once.
enum TourImages {
    private static var cache: [String: UIImage] = [:]

    static func image(itemID: String, resourceName: String?, session: ArcGISOnlineSession) async -> UIImage? {
        guard let resourceName else { return nil }
        let key = itemID + "/" + resourceName
        if let cached = cache[key] { return cached }
        guard let data = try? await StoryAssetStore.imageData(itemID: itemID, resourceName: resourceName, session: session),
              let image = UIImage(data: data) else { return nil }
        cache[key] = image
        return image
    }
}

// MARK: - Map

/// The tour's stops as numbered markers joined by a dashed route on an
/// ArcGIS scene (imagery draped on world elevation). Tapping a marker selects
/// its stop; selecting a stop flies the camera to it and then slowly orbits
/// it while the stop is narrated, until the user takes over.
struct TourMapView: View {

    let stops: [TourStop]
    @Binding var selectedIndex: Int
    let isThreeD: Bool

    @State private var scene = TourMapView.makeScene()
    @State private var overlay = TourMapView.makeOverlay()
    @State private var cameraController: CameraController = GlobeCameraController()
    @State private var tappedPoint: CGPoint?
    @State private var hasShownOverview = false
    @State private var showsOverview = false
    @State private var orbits = true

    private struct Flight: Equatable {
        var index: Int
        var overview: Bool
        var orbits: Bool
    }

    var body: some View {
        SceneViewReader { proxy in
            SceneView(scene: scene, viewpoint: overviewViewpoint, graphicsOverlays: [overlay])
                .cameraController(cameraController)
                .atmosphereEffect(.realistic)
                .onSingleTapGesture { screenPoint, _ in
                    tappedPoint = screenPoint
                }
                .task(id: tappedPoint) {
                    guard let tappedPoint,
                          let result = try? await proxy.identify(on: overlay, screenPoint: tappedPoint, tolerance: 20),
                          let index = result.graphics.first?.attributes["stopIndex"] as? Int else { return }
                    showsOverview = false
                    selectedIndex = index
                }
                .task(id: Flight(index: selectedIndex, overview: showsOverview, orbits: orbits)) {
                    await fly(proxy)
                }
                .onChange(of: selectedIndex) { showsOverview = false }
        }
        .overlay(alignment: .topTrailing) { mapControls }
    }

    private var mapControls: some View {
        VStack(spacing: 8) {
            mapButton(
                showsOverview ? "Back to stop" : "Show all stops",
                systemImage: showsOverview ? "scope" : "map",
                isOn: showsOverview
            ) { showsOverview.toggle() }
            if isThreeD {
                mapButton(orbits ? "Stop orbiting" : "Orbit stop", systemImage: "rotate.3d", isOn: orbits) {
                    orbits.toggle()
                }
            }
        }
        .padding(8)
        .glassBackgroundEffect(in: RoundedRectangle(cornerRadius: 26))
        .padding(20)
    }

    private func mapButton(_ label: String, systemImage: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(isOn ? .black : .white)
                .frame(width: 44, height: 44)
                .background(isOn ? TourView.accent : .clear, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .hoverEffect()
        .help(label)
        .accessibilityLabel(label)
    }

    // MARK: Camera

    private var stopDistance: Double { isThreeD ? 1600 : 3500 }
    private var stopPitch: Double { isThreeD ? 62 : 0 }

    private func fly(_ proxy: SceneViewProxy) async {
        updateMarkers()
        if cameraController is OrbitLocationCameraController {
            // The orbit controller pins the camera to the previous stop and
            // ignores fly-tos, so let the swap back reach the SceneView first.
            cameraController = GlobeCameraController()
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
        }

        if showsOverview {
            _ = await proxy.setViewpoint(overviewViewpoint, duration: 2.5)
            return
        }
        // Let the overview of all stops show before the first fly-to.
        if !hasShownOverview {
            hasShownOverview = true
            try? await Task.sleep(for: .seconds(1.2))
        }
        guard !Task.isCancelled else { return }

        let stop = stops[selectedIndex]
        let target = Point(latitude: stop.latitude, longitude: stop.longitude)
        let camera = Camera(lookingAt: target, distance: stopDistance, heading: 0, pitch: stopPitch, roll: 0)
        // False when the flight was interrupted (by the user, or another flight).
        guard await proxy.setViewpointCamera(camera, duration: 3), orbits, isThreeD, !Task.isCancelled else { return }

        // Hand over to an orbit controller around the stop (the user can still
        // drag to look around it) and turn slowly while the stop is narrated.
        let orbit = OrbitLocationCameraController(target: target, distance: stopDistance)
        orbit.cameraPitchOffset = stopPitch
        orbit.cameraHeadingOffset = 0
        cameraController = orbit
        try? await Task.sleep(for: .milliseconds(300))
        guard !Task.isCancelled else { return }
        await orbit.moveCamera(distanceDelta: 0, headingDelta: 360, pitchDelta: 0, duration: 120)
    }

    // MARK: Scene content

    private static func makeScene() -> ArcGIS.Scene {
        let scene = ArcGIS.Scene(basemapStyle: .arcGISImagery)
        let elevation = ArcGISTiledElevationSource(
            url: URL(string: "https://elevation3d.arcgis.com/arcgis/rest/services/WorldElevation3D/Terrain3D/ImageServer")!
        )
        scene.baseSurface.addElevationSource(elevation)
        return scene
    }

    private static func makeOverlay() -> GraphicsOverlay {
        let overlay = GraphicsOverlay()
        overlay.sceneProperties = LayerSceneProperties(surfacePlacement: .drapedBillboarded)
        return overlay
    }

    /// A view that frames every stop, used before the first fly-to and for
    /// "show all stops".
    private var overviewViewpoint: Viewpoint {
        let latitudes = stops.map(\.latitude)
        let longitudes = stops.map(\.longitude)
        let padding = max(0.05, (latitudes.max()! - latitudes.min()!) * 0.25)
        let extent = Envelope(
            xMin: longitudes.min()! - padding, yMin: latitudes.min()! - padding,
            xMax: longitudes.max()! + padding, yMax: latitudes.max()! + padding,
            spatialReference: .wgs84
        )
        return Viewpoint(boundingGeometry: extent)
    }

    /// Redraws the route and the numbered markers, highlighting (and naming)
    /// the selected stop.
    private func updateMarkers() {
        overlay.removeAllGraphics()
        let accent = UIColor(TourView.accent)
        let points = stops.map { Point(latitude: $0.latitude, longitude: $0.longitude) }

        if points.count > 1 {
            let route = Graphic(
                geometry: Polyline(points: points),
                symbol: SimpleLineSymbol(style: .dash, color: UIColor(white: 1, alpha: 0.85), width: 3)
            )
            overlay.addGraphic(route)
        }

        for (index, stop) in stops.enumerated() {
            let isSelected = index == selectedIndex
            var symbols: [Symbol] = []
            if isSelected {
                symbols.append(SimpleMarkerSymbol(style: .circle, color: accent.withAlphaComponent(0.3), size: 64))
            }
            let circle = SimpleMarkerSymbol(
                style: .circle,
                color: isSelected ? accent : UIColor(red: 0.12, green: 0.1, blue: 0.09, alpha: 0.9),
                size: isSelected ? 40 : 30
            )
            circle.outline = SimpleLineSymbol(style: .solid, color: isSelected ? .white : accent, width: 2)
            symbols.append(circle)

            let number = TextSymbol(text: "\(index + 1)", color: isSelected ? .black : .white, size: isSelected ? 18 : 14)
            number.fontWeight = .bold
            symbols.append(number)

            if isSelected {
                let label = TextSymbol(text: stop.title, color: .white, size: 15, horizontalAlignment: .center, verticalAlignment: .bottom)
                label.fontWeight = .bold
                label.haloColor = UIColor(white: 0, alpha: 0.75)
                label.haloWidth = 2.5
                label.offsetY = 30
                symbols.append(label)
            }

            let graphic = Graphic(
                geometry: points[index],
                attributes: ["stopIndex": index],
                symbol: CompositeSymbol(symbols: symbols)
            )
            graphic.zIndex = isSelected ? 2 : 1
            overlay.addGraphic(graphic)
        }
    }
}

// MARK: - Model stage

/// The stop's interactive 3D model on a softly lit stage, downloaded and
/// unzipped on demand. Shows the stop's picture while it loads, or on its own
/// when the stop has no model.
private struct TourModelStage: View {

    let itemID: String
    let stop: TourStop

    @Environment(AppModel.self) private var appModel

    private enum ModelState {
        case none
        case loading
        case ready(InteractiveModel)
        case failed(String)
    }

    @State private var picture: UIImage?
    @State private var modelState = ModelState.none
    @State private var attempt = 0

    private var hasModel: Bool { stop.modelResourceName != nil }

    var body: some View {
        // Flat card first, its decorations as overlays on it alone; the live
        // model is the last layer so nothing is laid over (and pushed in
        // front of) it.
        stageCard
            .overlay(alignment: .topLeading) { badge }
            .overlay {
                if case .ready(let model) = modelState {
                    TurntableModelView(model: model, zoom: 0.8)
                        .padding(24)
                }
            }
            .task { picture = await TourImages.image(itemID: itemID, resourceName: stop.posterResourceName, session: appModel.arcGISSession) }
            .task(id: attempt) { await loadModel() }
    }

    private var isReady: Bool {
        if case .ready = modelState { return true }
        return false
    }

    private var stageCard: some View {
        ZStack {
            Color.black.opacity(0.3)
            if hasModel {
                // A pool of light with a soft floor shadow for the model.
                RadialGradient(colors: [.white.opacity(0.18), .clear], center: .center, startRadius: 10, endRadius: 220)
                Ellipse()
                    .fill(.black.opacity(0.45))
                    .frame(width: 220, height: 34)
                    .blur(radius: 14)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 18)
            }

            if let picture, !isReady {
                Color.clear
                    .overlay {
                        Image(uiImage: picture)
                            .resizable()
                            .scaledToFill()
                            .opacity(hasModel ? 0.35 : 1)
                            .blur(radius: hasModel ? 6 : 0)
                    }
                    .clipped()
            } else if !isReady {
                Image(systemName: hasModel ? "cube.transparent" : "photo")
                    .font(.system(size: 60, weight: .ultraLight))
                    .opacity(0.5)
            }

            switch modelState {
            case .loading:
                VStack(spacing: 10) {
                    ProgressView()
                    Text("Preparing 3D model…").font(.system(size: 14, weight: .medium))
                }
                .padding(16)
                .background(.black.opacity(0.4), in: RoundedRectangle(cornerRadius: 18))
            case .failed(let message):
                VStack(spacing: 10) {
                    Label("Couldn’t load this model", systemImage: "exclamationmark.triangle")
                        .font(.system(size: 15, weight: .semibold))
                    Text(message)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.85))
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                    Button("Try again") { attempt += 1 }
                }
                .padding(16)
                .background(.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 18))
                .padding(16)
            case .none, .ready:
                EmptyView()
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 28))
        .overlay(RoundedRectangle(cornerRadius: 28).strokeBorder(.white.opacity(0.3), lineWidth: 1))
    }

    private var badge: some View {
        Label(hasModel ? (isReady ? "Drag to turn · Tap to interact" : "3D model") : "Photo", systemImage: hasModel ? "cube" : "photo")
            .font(.system(size: 12, weight: .semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(.black.opacity(0.4), in: Capsule())
            .padding(14)
    }

    private func loadModel() async {
        guard let resourceName = stop.modelResourceName else { return }
        modelState = .loading
        do {
            let model = try await TourModelLoader.load(itemID: itemID, resourceName: resourceName, session: appModel.arcGISSession)
            withAnimation(.easeOut(duration: 0.4)) { modelState = .ready(model) }
        } catch is CancellationError {
            return
        } catch {
            modelState = .failed(error.localizedDescription)
        }
    }
}

enum TourModelLoader {
    /// Downloads (once), unzips and loads a stop's model, ready to display.
    static func load(itemID: String, resourceName: String, session: ArcGISOnlineSession) async throws -> InteractiveModel {
        let url = try await StoryAssetStore.modelURL(itemID: itemID, resourceName: resourceName, session: session)
        let entity = try await Entity(contentsOf: url)
        return InteractiveModel(entity, isRealityFile: url.pathExtension.lowercased() == "reality")
    }
}

// MARK: - Turntable

/// A model that slowly turns on its own until the user drags it; double-tap
/// resets it and starts the turntable again. Taps on the model run the
/// behaviors authored into a `.reality` file.
struct TurntableModelView: View {

    let model: InteractiveModel
    var zoom = 0.85
    /// Centre the model in the view's depth (for a volume) rather than
    /// standing it just in front of the window.
    var centersInDepth = false

    private static let degreesPerSecond = 14.0

    @State private var spinning = true
    @State private var spinOrigin = Date()
    @State private var yaw = 0.0
    @State private var pitch = 0.0
    @State private var dragTranslation = CGSize.zero

    var body: some View {
        TimelineView(.animation(paused: !spinning)) { context in
            let spin = spinning ? context.date.timeIntervalSince(spinOrigin) * Self.degreesPerSecond : 0
            GeometryReader3D { geometry in
                RealityView { content in
                    content.add(model.pivot)
                } update: { content in
                    let frame = content.convert(geometry.frame(in: .local), from: .local, to: content)
                    model.fit(
                        in: frame,
                        yaw: yaw + spin + dragTranslation.width * 0.4,
                        pitch: pitch + dragTranslation.height * 0.4,
                        zoom: zoom
                    )
                    if centersInDepth { model.pivot.position.z = frame.center.z }
                }
                .gesture(SpatialTapGesture().targetedToAnyEntity().onEnded { model.tap($0.entity) })
            }
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 4)
                .onChanged { value in
                    if spinning { freezeSpin() }
                    dragTranslation = value.translation
                }
                .onEnded { value in
                    yaw += value.translation.width * 0.4
                    pitch = min(80, max(-80, pitch + value.translation.height * 0.4))
                    dragTranslation = .zero
                }
        )
        .onTapGesture(count: 2) {
            yaw = 0
            pitch = 0
            spinOrigin = Date()
            spinning = true
        }
    }

    /// Stops the turntable where it is, folding its angle into `yaw`.
    private func freezeSpin() {
        yaw += Date().timeIntervalSince(spinOrigin) * Self.degreesPerSecond
        spinning = false
    }
}

// MARK: - Volume

/// Identifies a stop's model for the "view in your space" volume window.
struct TourModelReference: Codable, Hashable {
    var itemID: String
    var resourceName: String
    var title: String
}

/// A stop's 3D model in its own volumetric window, large enough to walk
/// around, with a title ornament.
struct TourModelVolumeView: View {

    let reference: TourModelReference

    @Environment(AppModel.self) private var appModel

    @State private var model: InteractiveModel?
    @State private var failure: String?

    var body: some View {
        Group {
            if let model {
                TurntableModelView(model: model, zoom: 0.9, centersInDepth: true)
            } else if let failure {
                ContentUnavailableView("Couldn’t load this model", systemImage: "exclamationmark.triangle", description: Text(failure))
            } else {
                ProgressView("Preparing 3D model…")
            }
        }
        .ornament(attachmentAnchor: .scene(.bottomFront)) {
            Label(reference.title, systemImage: "cube")
                .font(.system(size: 17, weight: .semibold))
                .padding(.horizontal, 20)
                .frame(height: 48)
                .glassBackgroundEffect(in: Capsule())
        }
        .task(id: reference) {
            do {
                model = try await TourModelLoader.load(
                    itemID: reference.itemID, resourceName: reference.resourceName, session: appModel.arcGISSession
                )
            } catch {
                failure = error.localizedDescription
            }
        }
    }
}
