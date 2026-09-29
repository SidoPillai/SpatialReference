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

    private func fetchRawJSON(path: String, extraQueryItems: [URLQueryItem]) async throws -> String {
        guard let credential = ArcGISEnvironment.authenticationManager.arcGISCredentialStore.credential(for: portalURL) as? OAuthUserCredential else {
            throw SessionError.notSignedIn
        }
        let token = try await credential.tokenInfo.accessToken

        var components = URLComponents(url: portalURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        components.queryItems = extraQueryItems + [URLQueryItem(name: "token", value: token)]

        let (data, response) = try await URLSession.shared.data(from: components.url!)
        if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
            throw SessionError.httpError(httpResponse.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        return String(data: data, encoding: .utf8) ?? "<\(data.count) bytes of binary data>"
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
