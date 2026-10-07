//
//  SettingsView.swift
//  SpatialReference
//

import SwiftUI

/// UserDefaults keys for app settings. Missing values mean "on".
enum SettingsKey {
    static let tapSounds = "settings.tapSounds"
    static let hoverChime = "settings.hoverChime"
    static let backgroundMusic = "settings.backgroundMusic"
    static let backgroundMusicTrack = "settings.backgroundMusicTrack"
    static let defaultEnvironment = "settings.defaultEnvironment"
}

/// Settings tab: account, sounds, environment preference and app info.
struct SettingsView: View {

    @Environment(AppModel.self) private var appModel

    @AppStorage(SettingsKey.tapSounds) private var tapSounds = true
    @AppStorage(SettingsKey.hoverChime) private var hoverChime = true
    @AppStorage(SettingsKey.backgroundMusic) private var backgroundMusic = true
    @AppStorage(SettingsKey.backgroundMusicTrack) private var backgroundMusicTrack = MusicTrack.defaultID
    @AppStorage(SettingsKey.defaultEnvironment) private var defaultEnvironment = ""

    private var session: ArcGISOnlineSession { appModel.arcGISSession }

    private var signedInUsername: String? {
        if case .signedIn(let name) = session.state { return name }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Settings")
                .font(.system(size: 40, weight: .bold))
                .padding(.horizontal, 16)

            Form {
                Section("Account") {
                    if let name = signedInUsername {
                        LabeledContent("Signed in as", value: name)
                    } else {
                        LabeledContent("Status", value: session.state == .signingIn ? "Signing in…" : "Guest")
                        Button("Sign in with ArcGIS") {
                            Task { await session.signIn() }
                        }
                        .disabled(session.state == .signingIn)
                    }
                }

                Section {
                    Toggle("Tap sounds", isOn: $tapSounds)
                    Toggle("Hover chime", isOn: $hoverChime)
                } header: {
                    Text("Sounds")
                } footer: {
                    Text("Narration audio isn’t affected by these settings.")
                }

                Section {
                    Toggle("Background music", isOn: $backgroundMusic)
                    Picker("Track", selection: $backgroundMusicTrack) {
                        ForEach(MusicTrack.catalog) { Text($0.title).tag($0.id) }
                    }
                    .disabled(!backgroundMusic)
                } header: {
                    Text("Music")
                } footer: {
                    Text("Music softens automatically while a story is narrated.")
                }
                .onChange(of: backgroundMusic) { appModel.backgroundMusic.refresh() }
                .onChange(of: backgroundMusicTrack) { appModel.backgroundMusic.refresh() }

                Section {
                    Picker("Default environment", selection: $defaultEnvironment) {
                        Text("None").tag("")
                        ForEach(ImmersiveEnvironment.catalog) { Text($0.title).tag($0.id) }
                    }
                } header: {
                    Text("Environments")
                } footer: {
                    Text("Stories will open inside this environment once environments are available.")
                }

                Section("About") {
                    LabeledContent("Version", value: appVersion)
                }

                if signedInUsername != nil {
                    Section {
                        // visionOS doesn't tint destructive buttons, so color it explicitly.
                        Button(role: .destructive) {
                            Task { await appModel.signOut() }
                        } label: {
                            Text("Sign Out")
                                .foregroundStyle(.red)
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
            .formStyle(.grouped)
        }
        .padding(.top, 40)
        .padding(.horizontal, 40)
        .frame(maxWidth: 900, maxHeight: .infinity, alignment: .top)
        .frame(maxWidth: .infinity)
    }

    private var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "–"
        let build = info?["CFBundleVersion"] as? String ?? "–"
        return "\(version) (\(build))"
    }
}
