//
//  SignInView.swift
//  SpatialReference
//

import SwiftUI

/// Sign-in screen: a centered frosted card with the globe mark and a single
/// "Sign in with ArcGIS" action that runs the OAuth flow.
struct SignInView: View {

    @Environment(AppModel.self) private var appModel

    var onBack: () -> Void
    var onSignedIn: () -> Void
    var onSkip: () -> Void = {}

    private var session: ArcGISOnlineSession { appModel.arcGISSession }

    var body: some View {
        ZStack {
            WarmBackdrop()

            card
                .frame(width: 640, height: 780)
                .background(
                    Color(red: 104 / 255, green: 90 / 255, blue: 77 / 255).opacity(0.66),
                    in: RoundedRectangle(cornerRadius: 48)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 48)
                        .strokeBorder(.white.opacity(0.16), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.35), radius: 45, y: 40)
        }
        .foregroundStyle(.white)
        .onChange(of: session.state) { _, state in
            if case .signedIn = state { onSignedIn() }
        }
        .onAppear {
            if case .signedIn = session.state { onSignedIn() }
        }
    }

    private var card: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 22, weight: .semibold))
                        .frame(width: 52, height: 52)
                        .background(.white.opacity(0.12), in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .hoverEffect()
                .accessibilityLabel("Back")
                Spacer()
            }

            GlobeView(gridOpacity: 0.6, gridLineWidth: 1.1, orbitOpacity: 0.85, orbitLineWidth: 1.4, dotRadius: 5)
                .frame(width: 150, height: 150)
                .padding(.top, 4)

            Text("Sign in to Spatial Reference")
                .font(.system(size: 44, weight: .regular, design: .serif))
                .multilineTextAlignment(.center)
                .padding(.top, 20)

            Text("Bring your own stories into the room, at full scale.")
                .font(.system(size: 18))
                .lineSpacing(4)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.84))
                .frame(maxWidth: 440)
                .padding(.top, 14)

            benefits
                .padding(.top, 26)

            signInButton
                .padding(.top, 30)

            Group {
                if case .failed(let message) = session.state {
                    Text(message).foregroundStyle(Color(red: 1, green: 0.78, blue: 0.72))
                } else {
                    Text("You’ll continue to ArcGIS to sign in securely.")
                        .foregroundStyle(.white.opacity(0.8))
                }
            }
            .font(.system(size: 15))
            .multilineTextAlignment(.center)
            .padding(.top, 16)

            skipButton
                .padding(.top, 10)

            Spacer(minLength: 0)

            HStack(spacing: 28) {
                Text("Terms")
                Text("Privacy")
            }
            .font(.system(size: 15))
            .foregroundStyle(.white.opacity(0.86))
        }
        .padding(.top, 32)
        .padding(.bottom, 40)
        .padding(.horizontal, 56)
    }

    private var benefits: some View {
        VStack(alignment: .leading, spacing: 14) {
            benefit("person.crop.square", "Your stories", "Open the story maps you’ve authored.")
            benefit("building.2", "Your organization’s", "Private and org-shared stories that public Explore can’t show.")
            benefit("bookmark", "Pick up where you left off", "Bookmarks and narration progress follow you.")
        }
        .frame(width: 440, alignment: .leading)
    }

    private func benefit(_ icon: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 17, weight: .semibold))
                Text(detail)
                    .font(.system(size: 15))
                    .foregroundStyle(.white.opacity(0.78))
            }
        }
    }

    private var skipButton: some View {
        Button(action: onSkip) {
            Text("Skip for now — explore public stories")
                .font(.system(size: 17, weight: .medium))
                .underline()
                .frame(height: 44)
                .padding(.horizontal, 20)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .hoverEffect()
        .disabled(session.state == .signingIn)
    }

    private var signInButton: some View {
        Button {
            Task { await session.signIn() }
        } label: {
            HStack(spacing: 12) {
                if session.state == .signingIn {
                    ProgressView().tint(darkInk)
                } else {
                    Image(systemName: "globe")
                        .font(.system(size: 22, weight: .regular))
                }
                Text(session.state == .signingIn ? "Signing in…" : "Sign in with ArcGIS")
                    .font(.system(size: 20, weight: .semibold))
            }
            .foregroundStyle(darkInk)
            .frame(width: 420, height: 64)
            .background(Color(red: 0.965, green: 0.945, blue: 0.918), in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .hoverEffect()
        .disabled(session.state == .signingIn)
    }

    private var darkInk: Color { Color(red: 0.169, green: 0.141, blue: 0.118) }
}

#Preview(windowStyle: .automatic) {
    SignInView(onBack: {}, onSignedIn: {}, onSkip: {})
        .environment(AppModel())
}
