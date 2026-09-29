//
//  WelcomeView.swift
//  SpatialReference
//

import SwiftUI

/// Landing page shown on launch. Warm-toned backdrop, a frosted panel with a
/// wireframe globe behind the wordmark, feature list and a "Get Started" pill.
struct WelcomeView: View {

    var onGetStarted: () -> Void

    private let features = [
        "Stories you can step inside",
        "Narration with live-highlighted text",
        "A full immersive scene for every chapter",
        "Objects you can hold in your space",
    ]

    var body: some View {
        ZStack {
            backdrop

            VStack(spacing: 44) {
                hero
                featureGrid
                getStartedButton
            }
            .padding(64)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(panelFill, in: RoundedRectangle(cornerRadius: 48))
            .overlay(
                RoundedRectangle(cornerRadius: 48)
                    .strokeBorder(.white.opacity(0.16), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.35), radius: 45, y: 40)
            .padding(.horizontal, 64)
            .padding(.vertical, 56)
        }
        .foregroundStyle(.white)
    }

    // MARK: - Pieces

    private var hero: some View {
        ZStack {
            GlobeView()
                .frame(width: 400, height: 400)

            Ellipse()
                .fill(
                    EllipticalGradient(
                        colors: [Color(red: 0.157, green: 0.125, blue: 0.102).opacity(0.55), .clear],
                        startRadiusFraction: 0, endRadiusFraction: 0.5
                    )
                )
                .frame(width: 460, height: 180)

            VStack(spacing: 8) {
                Text("SPATIAL")
                    .font(.system(size: 30, weight: .bold))
                    .tracking(9)
                    .shadow(color: .black.opacity(0.45), radius: 6, y: 2)
                Text("Reference")
                    .font(.system(size: 120, weight: .medium, design: .serif))
                    .tracking(-2.4)
                    .shadow(color: .black.opacity(0.45), radius: 12, y: 4)
            }
        }
        .frame(width: 640, height: 400)
    }

    private var featureGrid: some View {
        Grid(alignment: .leading, horizontalSpacing: 40, verticalSpacing: 14) {
            ForEach(0..<2, id: \.self) { row in
                GridRow {
                    featureRow(features[row * 2])
                    featureRow(features[row * 2 + 1])
                }
            }
        }
    }

    private func featureRow(_ text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark")
                .font(.system(size: 18, weight: .heavy))
                .accessibilityHidden(true)
            Text(text)
                .font(.system(size: 22, weight: .medium))
        }
    }

    private var getStartedButton: some View {
        Button(action: onGetStarted) {
            Text("GET STARTED")
                .font(.system(size: 22, weight: .semibold))
                .tracking(1.8)
                .frame(width: 480, height: 72)
                .background(.white.opacity(0.14), in: Capsule())
                .overlay(Capsule().strokeBorder(.white.opacity(0.22), lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .hoverEffect()
    }

    // MARK: - Backgrounds

    private var panelFill: Color {
        Color(red: 104 / 255, green: 90 / 255, blue: 77 / 255).opacity(0.62)
    }

    private var backdrop: some View { WarmBackdrop() }
}

/// Shared warm gradient backdrop used by the welcome and sign-in screens.
struct WarmBackdrop: View {

    var body: some View {
        ZStack {
            LinearGradient(
                stops: [
                    .init(color: Color(red: 0.165, green: 0.145, blue: 0.129), location: 0),
                    .init(color: Color(red: 0.294, green: 0.251, blue: 0.212), location: 0.7),
                    .init(color: Color(red: 0.365, green: 0.294, blue: 0.227), location: 1),
                ],
                startPoint: .top, endPoint: .bottom
            )
            glow(Color(red: 0.541, green: 0.290, blue: 0.165), width: 0.6, height: 1.2, x: 0.04, y: 0.5)
            glow(Color(red: 0.659, green: 0.471, blue: 0.290), width: 0.5, height: 0.9, x: 0.97, y: 0.45)
            glow(Color(red: 0.290, green: 0.251, blue: 0.220), width: 1.4, height: 0.8, x: 0.5, y: 0)
        }
        .ignoresSafeArea()
    }

    /// Elliptical radial glow sized/positioned as fractions of the window.
    private func glow(_ color: Color, width: CGFloat, height: CGFloat, x: CGFloat, y: CGFloat) -> some View {
        GeometryReader { geo in
            Ellipse()
                .fill(EllipticalGradient(colors: [color, color.opacity(0)], startRadiusFraction: 0, endRadiusFraction: 0.5))
                .frame(width: geo.size.width * width, height: geo.size.height * height)
                .position(x: geo.size.width * x, y: geo.size.height * y)
        }
    }
}

/// Wireframe globe with an orbiting dot, drawn to match the design's SVG.
struct GlobeView: View {

    var gridOpacity = 0.34
    var gridLineWidth: CGFloat = 0.6
    var orbitOpacity = 0.6
    var orbitLineWidth: CGFloat = 0.8
    var dotRadius: CGFloat = 3.2

    private let orbitPeriod: Double = 14

    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            Canvas { context, size in
                let s = size.width / 200
                var ctx = context
                ctx.scaleBy(x: s, y: s)

                drawGlobe(&ctx)
                drawOrbit(&ctx, phase: (t.truncatingRemainder(dividingBy: orbitPeriod)) / orbitPeriod)
            }
        }
        .accessibilityHidden(true)
    }

    private func ellipse(cx: CGFloat, cy: CGFloat, rx: CGFloat, ry: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: cx - rx, y: cy - ry, width: rx * 2, height: ry * 2))
    }

    private func rotated(_ ctx: inout GraphicsContext, degrees: Double) {
        ctx.translateBy(x: 100, y: 100)
        ctx.rotate(by: .degrees(degrees))
        ctx.translateBy(x: -100, y: -100)
    }

    private func drawGlobe(_ context: inout GraphicsContext) {
        var ctx = context
        rotated(&ctx, degrees: -20)
        let stroke = GraphicsContext.Shading.color(.white.opacity(gridOpacity))
        let style = StrokeStyle(lineWidth: gridLineWidth)

        for path in [
            ellipse(cx: 100, cy: 100, rx: 70, ry: 70),
            ellipse(cx: 100, cy: 100, rx: 52, ry: 70),
            ellipse(cx: 100, cy: 100, rx: 26, ry: 70),
            ellipse(cx: 100, cy: 100, rx: 70, ry: 14),
            ellipse(cx: 100, cy: 65, rx: 61, ry: 11),
            ellipse(cx: 100, cy: 135, rx: 61, ry: 11),
            ellipse(cx: 100, cy: 40, rx: 36, ry: 6),
            ellipse(cx: 100, cy: 160, rx: 36, ry: 6),
        ] {
            ctx.stroke(path, with: stroke, style: style)
        }

        var meridian = Path()
        meridian.move(to: CGPoint(x: 100, y: 30))
        meridian.addLine(to: CGPoint(x: 100, y: 170))
        ctx.stroke(meridian, with: stroke, style: style)
    }

    private func drawOrbit(_ context: inout GraphicsContext, phase: Double) {
        var ctx = context
        rotated(&ctx, degrees: 14)

        ctx.stroke(
            ellipse(cx: 100, cy: 100, rx: 96, ry: 26),
            with: .color(.white.opacity(orbitOpacity)),
            style: StrokeStyle(lineWidth: orbitLineWidth)
        )

        // Dot starts at the left vertex (4,100) and travels the ellipse.
        let angle = Double.pi + phase * 2 * .pi
        let dot = CGPoint(x: 100 + 96 * cos(angle), y: 100 + 26 * sin(angle))
        ctx.fill(
            Path(ellipseIn: CGRect(x: dot.x - dotRadius, y: dot.y - dotRadius, width: dotRadius * 2, height: dotRadius * 2)),
            with: .color(Color(red: 1, green: 0.914, blue: 0.722))
        )
    }
}

#Preview(windowStyle: .automatic) {
    WelcomeView(onGetStarted: {})
}
