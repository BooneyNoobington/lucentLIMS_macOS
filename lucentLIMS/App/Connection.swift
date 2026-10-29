import AuthenticationServices
import Foundation
import SwiftUI
import LucentAPIClient
import Observation

/// Where the data comes from (the demo data or a lucentAPI server), how to sign in there, and
/// the `LabStore` that results. The settings live in UserDefaults, tokens in the Keychain.
@MainActor
@Observable
final class Connection {
    enum Source: String, CaseIterable, Identifiable {
        case demo, server
        var id: String { rawValue }
    }

    enum SignInMethod: String, CaseIterable, Identifiable {
        /// Log in at the identity provider in the browser.
        case openIDConnect
        /// Paste an access token, e.g. from lucentAPI's dev/mint_token.py.
        case accessToken
        var id: String { rawValue }
    }

    enum State: Equatable {
        case ready
        case loading
        case needsSignIn
        case failed(String)
    }

    var source: Source { didSet { save(source.rawValue, "LucentSource") } }
    var serverURL: String { didSet { save(serverURL, "LucentServerURL") } }
    var method: SignInMethod { didSet { save(method.rawValue, "LucentSignInMethod") } }
    var issuer: String { didSet { save(issuer, "LucentIssuer") } }
    var clientID: String { didSet { save(clientID, "LucentClientID") } }

    private(set) var state = State.ready
    private(set) var store: LabStore
    @ObservationIgnored private var tokens: TokenManager?

    init(defaults: UserDefaults = .standard) {
        source = Source(rawValue: defaults.string(forKey: "LucentSource") ?? "") ?? .demo
        serverURL = defaults.string(forKey: "LucentServerURL") ?? "http://localhost:8000"
        method = SignInMethod(rawValue: defaults.string(forKey: "LucentSignInMethod") ?? "") ?? .openIDConnect
        issuer = defaults.string(forKey: "LucentIssuer") ?? ""
        clientID = defaults.string(forKey: "LucentClientID") ?? "lucentlims"
        store = .demo()
        #if DEBUG
        // For automated runs: -LucentAccessToken <token> on the command line.
        if let token = defaults.string(forKey: "LucentAccessToken") {
            Keychain.write(token, account: Self.accessTokenAccount)
        }
        #endif
        if source == .server {
            state = .loading
            Task { await connect() }
        }
    }

    var isDemo: Bool { source == .demo }
    var hasAccessToken: Bool { Keychain.read(String.self, account: Self.accessTokenAccount) != nil }

    /// Shown in the sidebar: "Demo data" or the server's host.
    var summary: String {
        isDemo ? String(localized: "Demo data") : (URL(string: serverURL)?.host() ?? serverURL)
    }

    func useDemoData() {
        source = .demo
        store = .demo()
        state = .ready
    }

    /// Loads everything from the server with the current settings.
    func connect() async {
        source = .server
        guard let base = URL(string: serverURL), base.scheme != nil else {
            state = .failed(String(localized: "The server address isn't a URL."))
            return
        }
        let provider: LucentAPIClient.TokenProvider
        switch method {
        case .accessToken:
            guard let token = Keychain.read(String.self, account: Self.accessTokenAccount) else {
                state = .needsSignIn
                return
            }
            provider = { token }
        case .openIDConnect:
            guard let manager = tokenManager(), await manager.isSignedIn else {
                state = .needsSignIn
                return
            }
            provider = { try await manager.accessToken() }
        }

        state = .loading
        let service = APILabService(client: LucentAPIClient(baseURL: base, token: provider))
        do {
            let snapshot = try await service.load()
            store = LabStore(snapshot: snapshot, service: service)
            state = .ready
        } catch let error as LucentAPIError where error.status == 401 {
            state = .needsSignIn
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    /// Signs in at the identity provider in the browser, then connects.
    func signIn(with session: WebAuthenticationSession) async {
        guard let manager = tokenManager() else {
            state = .failed(String(localized: "Enter the identity provider's address (issuer) first."))
            return
        }
        do {
            let request = try await manager.startSignIn()
            let callback = try await session.authenticate(
                using: request.url, callback: .customScheme(OpenIDConnect.redirectURI.scheme!),
                preferredBrowserSession: .shared, additionalHeaderFields: [:])
            try await manager.finishSignIn(callback: callback, pkce: request.pkce, state: request.state)
            await connect()
        } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
            state = .needsSignIn
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    /// Uses a pasted access token, then connects.
    func use(accessToken: String) async {
        Keychain.write(accessToken.trimmingCharacters(in: .whitespacesAndNewlines), account: Self.accessTokenAccount)
        method = .accessToken
        await connect()
    }

    func signOut() async {
        Keychain.delete(account: Self.accessTokenAccount)
        await tokens?.signOut()
        tokens = nil
        state = .needsSignIn
    }

    private static let accessTokenAccount = "access token"

    private func tokenManager() -> TokenManager? {
        guard let url = URL(string: issuer), url.scheme != nil, !clientID.isEmpty else { return nil }
        if let tokens, tokens.issuer == url, tokens.clientID == clientID { return tokens }
        tokens = TokenManager(issuer: url, clientID: clientID)
        return tokens
    }

    private func save(_ value: String, _ key: String) {
        UserDefaults.standard.set(value, forKey: key)
    }
}
