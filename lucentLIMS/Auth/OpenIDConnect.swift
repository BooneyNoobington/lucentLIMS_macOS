import CryptoKit
import Foundation

/// Signing in with OpenID Connect: the authorization code flow with PKCE, for a public client
/// (an app can't keep a secret). The browser part runs in `ASWebAuthenticationSession`; this
/// file builds the requests and reads the answers.
enum OpenIDConnect {
    /// Where the app's login comes back to. Register it as a redirect URI at the provider.
    static let redirectURI = URL(string: "lucentlims://oauth/callback")!
    static let scopes = ["openid", "profile", "offline_access"]

    struct Endpoints: Codable, Hashable, Sendable {
        var authorizationEndpoint: URL
        var tokenEndpoint: URL
        var endSessionEndpoint: URL?
    }

    struct Tokens: Codable, Hashable, Sendable {
        var accessToken: String
        var refreshToken: String?
        var idToken: String?
        var expiresAt: Date

        /// Renew a little before the provider would refuse it.
        func isFresh(at now: Date = .now) -> Bool { expiresAt.timeIntervalSince(now) > 30 }
    }

    struct Failure: LocalizedError, Hashable, Sendable {
        var message: String
        var errorDescription: String? { message }
    }

    /// A random code verifier and its S256 challenge (RFC 7636).
    struct PKCE: Hashable, Sendable {
        var verifier: String
        var challenge: String

        init(verifier: String = randomString()) {
            self.verifier = verifier
            challenge = base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
        }
    }

    static func randomString(bytes: Int = 32) -> String {
        var generator = SystemRandomNumberGenerator()
        return base64URL(Data((0..<bytes).map { _ in UInt8.random(in: .min ... .max, using: &generator) }))
    }

    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func discoveryURL(issuer: URL) -> URL {
        issuer.appending(path: ".well-known/openid-configuration")
    }

    static func endpoints(from data: Data) throws -> Endpoints {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(Endpoints.self, from: data)
    }

    static func authorizationURL(_ endpoints: Endpoints, clientID: String, pkce: PKCE, state: String) -> URL {
        var components = URLComponents(url: endpoints.authorizationEndpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = (components.queryItems ?? []) + [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI.absoluteString),
            URLQueryItem(name: "scope", value: scopes.joined(separator: " ")),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: pkce.challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
        ]
        return components.url!
    }

    /// The authorization code from the redirect, after checking `state`.
    static func code(from callback: URL, state: String) throws -> String {
        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func item(_ name: String) -> String? { items.first { $0.name == name }?.value }
        if let error = item("error") {
            throw Failure(message: item("error_description") ?? String(localized: "Sign-in failed: \(error)."))
        }
        guard item("state") == state else {
            throw Failure(message: String(localized: "The sign-in answer doesn't belong to this request."))
        }
        guard let code = item("code") else {
            throw Failure(message: String(localized: "The sign-in answer has no code."))
        }
        return code
    }

    static func codeExchange(_ endpoints: Endpoints, clientID: String, code: String, pkce: PKCE) -> URLRequest {
        tokenRequest(endpoints, [
            "grant_type": "authorization_code", "code": code, "redirect_uri": redirectURI.absoluteString,
            "client_id": clientID, "code_verifier": pkce.verifier,
        ])
    }

    static func refresh(_ endpoints: Endpoints, clientID: String, refreshToken: String) -> URLRequest {
        tokenRequest(endpoints, ["grant_type": "refresh_token", "refresh_token": refreshToken, "client_id": clientID])
    }

    private static func tokenRequest(_ endpoints: Endpoints, _ form: [String: String]) -> URLRequest {
        var request = URLRequest(url: endpoints.tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        request.httpBody = Data(form.sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")" }
            .joined(separator: "&").utf8)
        return request
    }

    /// Reads a token answer; an answer without a refresh token keeps `previousRefreshToken`.
    static func tokens(from data: Data, status: Int, now: Date = .now,
                       previousRefreshToken: String? = nil) throws -> Tokens {
        struct Answer: Decodable {
            var accessToken: String?
            var refreshToken: String?
            var idToken: String?
            var expiresIn: Double?
            var error: String?
            var errorDescription: String?
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let answer = try decoder.decode(Answer.self, from: data)
        guard (200..<300).contains(status), let accessToken = answer.accessToken else {
            throw Failure(message: answer.errorDescription ?? answer.error
                          ?? String(localized: "The sign-in server refused the request (\(status))."))
        }
        return Tokens(accessToken: accessToken, refreshToken: answer.refreshToken ?? previousRefreshToken,
                      idToken: answer.idToken, expiresAt: now.addingTimeInterval(answer.expiresIn ?? 300))
    }
}

/// Keeps the tokens of one provider and hands out fresh access tokens.
actor TokenManager {
    typealias Transport = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    let issuer: URL
    let clientID: String
    private let keychainAccount: String?
    private let transport: Transport
    private var endpoints: OpenIDConnect.Endpoints?
    private var tokens: OpenIDConnect.Tokens?
    private var refreshing: Task<OpenIDConnect.Tokens, Error>?

    /// `keepsTokens: false` holds them in memory only (for tests).
    init(issuer: URL, clientID: String, keepsTokens: Bool = true,
         transport: @escaping Transport = { try await URLSession.shared.data(for: $0) }) {
        self.issuer = issuer
        self.clientID = clientID
        self.transport = transport
        keychainAccount = keepsTokens ? "oidc \(clientID)@\(issuer.absoluteString)" : nil
        tokens = keychainAccount.flatMap { Keychain.read(OpenIDConnect.Tokens.self, account: $0) }
    }

    var isSignedIn: Bool { tokens != nil }

    /// Step 1: where to send the browser, and what to remember for step 2.
    func startSignIn() async throws -> (url: URL, pkce: OpenIDConnect.PKCE, state: String) {
        let pkce = OpenIDConnect.PKCE()
        let state = OpenIDConnect.randomString(bytes: 16)
        return (OpenIDConnect.authorizationURL(try await discover(), clientID: clientID, pkce: pkce, state: state),
                pkce, state)
    }

    /// Step 2: trade the code from the redirect for tokens.
    func finishSignIn(callback: URL, pkce: OpenIDConnect.PKCE, state: String) async throws {
        let code = try OpenIDConnect.code(from: callback, state: state)
        let request = OpenIDConnect.codeExchange(try await discover(), clientID: clientID, code: code, pkce: pkce)
        store(try await exchange(request, previousRefreshToken: nil))
    }

    /// A current access token, renewed with the refresh token when needed.
    func accessToken() async throws -> String {
        if let tokens, tokens.isFresh() { return tokens.accessToken }
        if let refreshing { return try await refreshing.value.accessToken }
        guard let refreshToken = tokens?.refreshToken else {
            throw OpenIDConnect.Failure(message: String(localized: "Please sign in."))
        }
        let task = Task {
            try await exchange(OpenIDConnect.refresh(try await discover(), clientID: clientID,
                                                     refreshToken: refreshToken), previousRefreshToken: refreshToken)
        }
        refreshing = task
        defer { refreshing = nil }
        do {
            let renewed = try await task.value
            store(renewed)
            return renewed.accessToken
        } catch {
            signOut()
            throw error
        }
    }

    func signOut() {
        tokens = nil
        if let keychainAccount { Keychain.delete(account: keychainAccount) }
    }

    private func store(_ new: OpenIDConnect.Tokens) {
        tokens = new
        if let keychainAccount { Keychain.write(new, account: keychainAccount) }
    }

    private func discover() async throws -> OpenIDConnect.Endpoints {
        if let endpoints { return endpoints }
        let (data, _) = try await transport(URLRequest(url: OpenIDConnect.discoveryURL(issuer: issuer)))
        let found = try OpenIDConnect.endpoints(from: data)
        endpoints = found
        return found
    }

    private func exchange(_ request: URLRequest, previousRefreshToken: String?) async throws -> OpenIDConnect.Tokens {
        let (data, response) = try await transport(request)
        return try OpenIDConnect.tokens(from: data, status: (response as? HTTPURLResponse)?.statusCode ?? 0,
                                        previousRefreshToken: previousRefreshToken)
    }
}
