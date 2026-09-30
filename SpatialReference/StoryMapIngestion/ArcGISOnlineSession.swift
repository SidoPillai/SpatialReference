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

    init() {
        oauthConfiguration = OAuthUserConfiguration(
            portalURL: portalURL,
            clientID: "J3UzuLLFu8g1Nn0R",
            redirectURL: URL(string: "spatialreference-auth://auth")!
        )
        ArcGISEnvironment.authenticationManager.arcGISAuthenticationChallengeHandler = ChallengeHandler(
            configuration: oauthConfiguration
        )
    }

    func signIn() async {
        guard state != .signingIn else { return }
        state = .signingIn
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

    /// The signed-in user's StoryMaps, newest first — including private ones,
    /// which the search API only returns because the request is authenticated.
    func listMyStoryMaps() async throws -> [StoryMapItem] {
        guard case .signedIn(let username) = state else { throw SessionError.notSignedIn }
        let token = try await accessToken()

        let data = try await fetchData(
            path: "sharing/rest/search",
            extraQueryItems: [
                URLQueryItem(name: "f", value: "json"),
                URLQueryItem(name: "q", value: "owner:\"\(username)\" AND type:\"StoryMap\""),
                URLQueryItem(name: "sortField", value: "modified"),
                URLQueryItem(name: "sortOrder", value: "desc"),
                URLQueryItem(name: "num", value: "100"),
            ],
            token: token
        )
        let response = try JSONDecoder().decode(SearchResponse.self, from: data)
        return response.results.map { result in
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
