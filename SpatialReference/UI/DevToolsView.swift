//
//  DevToolsView.swift
//  SpatialReference
//

import SwiftUI

/// ArcGIS Online spike UI: sign-in state, story loading by item ID and a raw
/// resource lister. Presented as a sheet from the story viewer.
struct DevToolsView: View {

    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss

    @State private var storyItemID = ""
    @State private var resourceOutput = ""
    @State private var isFetching = false
    @State private var parseError: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                devToolsSection
                    .padding()
            }
            .navigationTitle("Developer Tools")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .onAppear {
            if storyItemID.isEmpty {
                storyItemID = appModel.demoStoryItemID
            }
        }
    }

    // MARK: - Developer tools (ArcGIS Online spike UI)

    private var devToolsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            signInSection

            if case .signedIn = appModel.arcGISSession.state {
                storyMapFetchSection
            }
        }
        .padding(.top, 8)
    }

    @ViewBuilder
    private var signInSection: some View {
        switch appModel.arcGISSession.state {
        case .signedOut:
            Button("Sign in to ArcGIS Online") {
                Task { await appModel.arcGISSession.signIn() }
            }
        case .signingIn:
            ProgressView("Signing in…")
        case .signedIn(let username):
            Label("Signed in as \(username)", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed(let message):
            VStack(alignment: .leading) {
                Label("Sign-in failed", systemImage: "xmark.circle.fill")
                    .foregroundStyle(.red)
                Text(message).font(.caption)
                Button("Retry") {
                    Task { await appModel.arcGISSession.signIn() }
                }
            }
        }
    }

    private var storyMapFetchSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("StoryMap item ID", text: $storyItemID)
                .textFieldStyle(.roundedBorder)

            HStack {
                Button("Load story") {
                    loadStory()
                }
                Button("List resources (debug)") {
                    fetch { try await appModel.arcGISSession.listResources(itemID: storyItemID) }
                }
            }
            .disabled(storyItemID.isEmpty || isFetching)

            if isFetching {
                ProgressView()
            }

            if let parseError {
                Text(parseError).foregroundStyle(.red).font(.caption)
            }

            if !resourceOutput.isEmpty {
                Text(resourceOutput)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private func loadStory() {
        isFetching = true
        parseError = nil
        Task {
            defer { isFetching = false }
            do {
                try await appModel.loadStory(itemID: storyItemID)
                resourceOutput = ""
            } catch {
                parseError = "Error: \(error.localizedDescription)"
            }
        }
    }

    private func fetch(_ operation: @escaping () async throws -> String) {
        isFetching = true
        resourceOutput = ""
        Task {
            defer { isFetching = false }
            do {
                resourceOutput = try await operation()
            } catch {
                resourceOutput = "Error: \(error.localizedDescription)"
            }
        }
    }
}

#Preview {
    DevToolsView()
        .environment(AppModel())
}
