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

    private var session: ArcGISOnlineSession { appModel.arcGISSession }

    var body: some View {
        ZStack {
            WarmBackdrop()

            card
                .frame(width: 640, height: 640)
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

            Text("Your library, bookmarks and narration progress follow you into every space.")
                .font(.system(size: 18))
                .lineSpacing(4)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.84))
                .frame(maxWidth: 440)
                .padding(.top, 14)

            signInButton
                .padding(.top, 40)

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
    SignInView(onBack: {}, onSignedIn: {})
        .environment(AppModel())
}
