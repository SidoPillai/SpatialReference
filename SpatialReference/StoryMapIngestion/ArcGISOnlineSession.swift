//
//  ArcGISOnlineSession.swift
//  SpatialReference
//

import ArcGIS
import Foundation

/// Handles ArcGIS Online OAuth sign-in and raw item-resource fetches.
///
/// This is the milestone-1 "spike" surface: the ArcGIS Maps SDK has no
/// public API for arbitrary item resources (e.g. a StoryMap's draft.json),
/// so once signed in we hit the Portal REST API directly with the OAuth
/// token the SDK obtained for us.
@MainActor
@Observable
final class ArcGISOnlineSession {
    enum State: Equatable {
        case signedOut
        case signingIn
        case signedIn(username: String)
        case failed(String)
    }

    private(set) var state = State.signedOut

    let portalURL = URL(string: "https://www.arcgis.com")!

    private let oauthConfiguration: OAuthUserConfiguration
    private let challengeHandler: ChallengeHandler
    /// Swaps the in-memory credential store for a Keychain-backed one, so an
    /// OAuth sign-in survives relaunches. Sign-in waits on it so the new
    /// credential always lands in the persistent store.
    private var persistentStoreSetup: Task<Void, Never>?

    init() {
        oauthConfiguration = OAuthUserConfiguration(
            portalURL: portalURL,
            clientID: "J3UzuLLFu8g1Nn0R",
            redirectURL: URL(string: "spatialreference-auth://auth")!
        )
        challengeHandler = ChallengeHandler(configuration: oauthConfiguration)
        ArcGISEnvironment.authenticationManager.arcGISAuthenticationChallengeHandler = challengeHandler
        persistentStoreSetup = Task {
            do {
                ArcGISEnvironment.authenticationManager.arcGISCredentialStore = try await .makePersistent(
                    access: .afterFirstUnlockThisDeviceOnly
                )
            } catch {
                // Fall back to the default in-memory store: sign-in still
                // works, it just won't be remembered across launches.
            }
        }
    }

    /// Signs back in silently with the credential saved in the Keychain by a
    /// previous session. Never shows the OAuth sheet: if there is no saved
    /// credential, or it can no longer be refreshed, the user stays signed out.
    func restoreSession() async {
        await persistentStoreSetup?.value
        guard state == .signedOut,
              ArcGISEnvironment.authenticationManager.arcGISCredentialStore.credential(for: portalURL) != nil
        else { return }

        state = .signingIn
        // Without a challenge handler an expired credential fails the load
        // instead of prompting.
        ArcGISEnvironment.authenticationManager.arcGISAuthenticationChallengeHandler = nil
        defer { ArcGISEnvironment.authenticationManager.arcGISAuthenticationChallengeHandler = challengeHandler }
        do {
            let portal = Portal(url: portalURL, connection: .authenticated)
            try await portal.load()
            state = .signedIn(username: portal.user?.username ?? "Unknown user")
        } catch {
            // Keep the saved credential: the failure may just be no network,
            // and an explicit sign-in or sign-out replaces it anyway.
            state = .signedOut
        }
    }

    /// Revokes the OAuth token and forgets the saved credential, so the next
    /// launch starts signed out.
    func signOut() async {
        let store = ArcGISEnvironment.authenticationManager.arcGISCredentialStore
        for case let credential as OAuthUserCredential in store.credentials {
            try? await credential.revokeToken()
        }
        store.removeAll()
        state = .signedOut
    }

    func signIn() async {
        guard state != .signingIn else { return }
        state = .signingIn
        await persistentStoreSetup?.value
        do {
            let portal = Portal(url: portalURL, connection: .authenticated)
            try await portal.load()
            state = .signedIn(username: portal.user?.username ?? "Unknown user")
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    /// Lists the resources attached to a portal item (e.g. to discover the
    /// exact name of a StoryMap's draft JSON resource).
    func listResources(itemID: String) async throws -> String {
        try await fetchRawJSON(
            path: "sharing/rest/content/items/\(itemID)/resources",
            extraQueryItems: [URLQueryItem(name: "f", value: "json")]
        )
    }

    /// Fetches a named resource from a portal item as raw text.
    func fetchResource(itemID: String, resourceName: String) async throws -> String {
        try await fetchRawJSON(
            path: "sharing/rest/content/items/\(itemID)/resources/\(resourceName)",
            extraQueryItems: []
        )
    }

    /// Fetches a named resource from a portal item as raw bytes (e.g. an
    /// image, or the `.zip` a StoryMaps 3D model is stored as).
    func fetchResourceData(itemID: String, resourceName: String) async throws -> Data {
        try await fetchData(
            path: "sharing/rest/content/items/\(itemID)/resources/\(resourceName)",
            extraQueryItems: []
        )
    }

    /// The type keyword that marks a StoryMap as authored for mixed reality.
    static let mixedRealityTypeKeyword = "mixed-reality"

    /// The signed-in user's mixed-reality StoryMaps, newest first — including
    /// private ones, which the search API only returns because the request is
    /// authenticated. Items without the `mixed-reality` type keyword are skipped.
    func listMyStoryMaps() async throws -> [StoryMapItem] {
        guard case .signedIn(let username) = state else { throw SessionError.notSignedIn }
        let token = try await accessToken()

        let data = try await fetchData(
            path: "sharing/rest/search",
            extraQueryItems: [
                URLQueryItem(name: "f", value: "json"),
                URLQueryItem(name: "q", value: "owner:\"\(username)\" AND type:\"StoryMap\" AND typekeywords:\"\(Self.mixedRealityTypeKeyword)\""),
                URLQueryItem(name: "sortField", value: "modified"),
                URLQueryItem(name: "sortOrder", value: "desc"),
                URLQueryItem(name: "num", value: "100"),
            ],
            token: token
        )
        let response = try JSONDecoder().decode(SearchResponse.self, from: data)
        // The search index tokenizes keywords, so re-check for an exact match.
        let mixedRealityResults = response.results.filter { result in
            (result.typeKeywords ?? []).contains {
                $0.caseInsensitiveCompare(Self.mixedRealityTypeKeyword) == .orderedSame
            }
        }
        return mixedRealityResults.map { result in
            StoryMapItem(
                id: result.id,
                title: result.title,
                summary: result.snippet ?? "",
                modified: result.modified.map { Date(timeIntervalSince1970: $0 / 1000) },
                access: result.access ?? "private",
                thumbnailURL: result.thumbnail.flatMap { thumbnail in
                    var components = URLComponents(
                        url: portalURL.appendingPathComponent("sharing/rest/content/items/\(result.id)/info/\(thumbnail)"),
                        resolvingAgainstBaseURL: false
                    )
                    components?.queryItems = [URLQueryItem(name: "token", value: token)]
                    return components?.url
                }
            )
        }
    }

    private func fetchRawJSON(path: String, extraQueryItems: [URLQueryItem]) async throws -> String {
        let data = try await fetchData(path: path, extraQueryItems: extraQueryItems)
        return String(data: data, encoding: .utf8) ?? "<\(data.count) bytes of binary data>"
    }

    private func accessToken() async throws -> String {
        guard let credential = ArcGISEnvironment.authenticationManager.arcGISCredentialStore.credential(for: portalURL) as? OAuthUserCredential else {
            throw SessionError.notSignedIn
        }
        return try await credential.tokenInfo.accessToken
    }

    private func fetchData(path: String, extraQueryItems: [URLQueryItem], token: String? = nil) async throws -> Data {
        let token = if let token { token } else { try await accessToken() }

        var components = URLComponents(url: portalURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        components.queryItems = extraQueryItems + [URLQueryItem(name: "token", value: token)]

        let (data, response) = try await URLSession.shared.data(from: components.url!)
        if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
            throw SessionError.httpError(httpResponse.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        // The REST API reports many failures (missing resource, expired
        // token) as HTTP 200 with a JSON `error` body.
        if response.mimeType?.contains("json") == true || response.mimeType == "text/plain",
           let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let error = body["error"] as? [String: Any] {
            throw SessionError.httpError(error["code"] as? Int ?? 0, error["message"] as? String ?? "Request failed")
        }
        return data
    }

    private struct SearchResponse: Decodable {
        struct Result: Decodable {
            let id: String
            let title: String
            let snippet: String?
            let modified: Double?
            let access: String?
            let thumbnail: String?
            let typeKeywords: [String]?
        }
        let results: [Result]
    }

    /// A StoryMap item listed in the user's library.
    struct StoryMapItem: Identifiable, Equatable {
        let id: String
        let title: String
        let summary: String
        let modified: Date?
        /// "private", "shared", "org" or "public".
        let access: String
        let thumbnailURL: URL?
    }

    enum SessionError: LocalizedError {
        case notSignedIn
        case httpError(Int, String)

        var errorDescription: String? {
            switch self {
            case .notSignedIn:
                return "Not signed in to ArcGIS Online yet."
            case .httpError(let status, let body):
                return "HTTP \(status): \(body)"
            }
        }
    }

    private final class ChallengeHandler: ArcGISAuthenticationChallengeHandler {
        let configuration: OAuthUserConfiguration

        init(configuration: OAuthUserConfiguration) {
            self.configuration = configuration
        }

        func handleArcGISAuthenticationChallenge(
            _ challenge: ArcGISAuthenticationChallenge
        ) async throws -> ArcGISAuthenticationChallenge.Disposition {
            let credential = try await OAuthUserCredential.credential(for: configuration)
            return .continueWithCredential(credential)
        }
    }
}
