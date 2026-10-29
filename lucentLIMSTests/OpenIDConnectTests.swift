import Foundation
import Testing
@testable import lucentLIMS

struct OpenIDConnectTests {
    let endpoints = OpenIDConnect.Endpoints(
        authorizationEndpoint: URL(string: "https://id.example.org/realms/lucent/protocol/openid-connect/auth")!,
        tokenEndpoint: URL(string: "https://id.example.org/realms/lucent/protocol/openid-connect/token")!)

    @Test func pkceChallengeIsTheSHA256OfTheVerifier() {
        // Expected value computed independently with Python's hashlib and base64.urlsafe_b64encode.
        let pkce = OpenIDConnect.PKCE(verifier: "dBjftJeZ4CVP-mJ92K9qHj6kPapUSBYMUCwYD2kYE5E")
        #expect(pkce.challenge == "tEhNhHONW28PEmQgxK-dgLHOhAfQpzvhXQ1BXS1kgBY")
    }

    @Test func verifiersAreRandomAndURLSafe() {
        let first = OpenIDConnect.PKCE(), second = OpenIDConnect.PKCE()
        #expect(first.verifier != second.verifier)
        #expect(first.verifier.count == 43)
        #expect(first.verifier.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" })
    }

    @Test func discovery() throws {
        let json = """
            {"issuer": "https://id.example.org/realms/lucent",
             "authorization_endpoint": "https://id.example.org/auth", "token_endpoint": "https://id.example.org/token",
             "jwks_uri": "https://id.example.org/certs"}
            """
        let found = try OpenIDConnect.endpoints(from: Data(json.utf8))
        #expect(found.tokenEndpoint.absoluteString == "https://id.example.org/token")
        #expect(OpenIDConnect.discoveryURL(issuer: URL(string: "https://id.example.org/realms/lucent")!).absoluteString
                == "https://id.example.org/realms/lucent/.well-known/openid-configuration")
    }

    @Test func authorizationURL() throws {
        let pkce = OpenIDConnect.PKCE(verifier: "verifier")
        let url = OpenIDConnect.authorizationURL(endpoints, clientID: "lucentlims", pkce: pkce, state: "s1")
        let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        let query = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
        #expect(query == [
            "response_type": "code", "client_id": "lucentlims", "redirect_uri": "lucentlims://oauth/callback",
            "scope": "openid profile offline_access", "state": "s1", "code_challenge": pkce.challenge,
            "code_challenge_method": "S256",
        ])
    }

    @Test func callbackChecksState() throws {
        let callback = URL(string: "lucentlims://oauth/callback?code=abc&state=s1")!
        #expect(try OpenIDConnect.code(from: callback, state: "s1") == "abc")
        #expect(throws: OpenIDConnect.Failure.self) { try OpenIDConnect.code(from: callback, state: "other") }
        let denied = URL(string: "lucentlims://oauth/callback?error=access_denied&error_description=Nope&state=s1")!
        #expect(throws: OpenIDConnect.Failure(message: "Nope")) { try OpenIDConnect.code(from: denied, state: "s1") }
    }

    @Test func codeExchangeIsAFormPost() throws {
        let request = OpenIDConnect.codeExchange(endpoints, clientID: "lucentlims", code: "a/b",
                                                 pkce: OpenIDConnect.PKCE(verifier: "v"))
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/x-www-form-urlencoded")
        let body = String(decoding: try #require(request.httpBody), as: UTF8.self)
        #expect(body == "client_id=lucentlims&code=a%2Fb&code_verifier=v&grant_type=authorization_code"
                + "&redirect_uri=lucentlims%3A%2F%2Foauth%2Fcallback")
    }

    @Test func tokenAnswers() throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let ok = Data(#"{"access_token": "at", "refresh_token": "rt", "expires_in": 300, "token_type": "Bearer"}"#.utf8)
        let tokens = try OpenIDConnect.tokens(from: ok, status: 200, now: now)
        #expect(tokens == .init(accessToken: "at", refreshToken: "rt", idToken: nil, expiresAt: now + 300))
        #expect(tokens.isFresh(at: now + 200))
        #expect(!tokens.isFresh(at: now + 290))

        let renewed = Data(#"{"access_token": "at2", "expires_in": 300}"#.utf8)
        #expect(try OpenIDConnect.tokens(from: renewed, status: 200, previousRefreshToken: "rt").refreshToken == "rt")

        let refused = Data(#"{"error": "invalid_grant", "error_description": "Token is not active"}"#.utf8)
        #expect(throws: OpenIDConnect.Failure(message: "Token is not active")) {
            try OpenIDConnect.tokens(from: refused, status: 400)
        }
    }
}

/// A fake identity provider for the token manager.
actor FakeProvider {
    var tokenRequests: [String] = []
    var expiresIn = 300
    var refusesRefresh = false

    func setExpiresIn(_ seconds: Int) { expiresIn = seconds }
    func setRefusesRefresh() { refusesRefresh = true }

    func handle(_ request: URLRequest) -> (Data, URLResponse) {
        let url = request.url!
        func answer(_ status: Int, _ json: String) -> (Data, URLResponse) {
            (Data(json.utf8), HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!)
        }
        if url.path.hasSuffix("openid-configuration") {
            return answer(200, #"{"authorization_endpoint": "https://id.example.org/auth", "token_endpoint": "https://id.example.org/token"}"#)
        }
        let form = String(decoding: request.httpBody ?? Data(), as: UTF8.self)
        tokenRequests.append(form)
        if form.contains("grant_type=refresh_token") && refusesRefresh {
            return answer(400, #"{"error": "invalid_grant"}"#)
        }
        return answer(200, #"{"access_token": "at\#(tokenRequests.count)", "refresh_token": "rt", "expires_in": \#(expiresIn)}"#)
    }
}

struct TokenManagerTests {
    func manager(_ provider: FakeProvider) -> TokenManager {
        TokenManager(issuer: URL(string: "https://id.example.org/realms/lucent")!, clientID: "lucentlims",
                     keepsTokens: false, transport: { await provider.handle($0) })
    }

    func signIn(_ tokens: TokenManager) async throws {
        let start = try await tokens.startSignIn()
        #expect(start.url.host() == "id.example.org")
        let callback = URL(string: "lucentlims://oauth/callback?code=abc&state=\(start.state)")!
        try await tokens.finishSignIn(callback: callback, pkce: start.pkce, state: start.state)
    }

    @Test func signInAndUseTheToken() async throws {
        let provider = FakeProvider()
        let tokens = manager(provider)
        #expect(await !tokens.isSignedIn)
        try await signIn(tokens)
        #expect(try await tokens.accessToken() == "at1")
        #expect(try await tokens.accessToken() == "at1")  // still fresh: no second request
        #expect(await provider.tokenRequests.count == 1)
    }

    @Test func expiredTokensAreRefreshed() async throws {
        let provider = FakeProvider()
        await provider.setExpiresIn(0)
        let tokens = manager(provider)
        try await signIn(tokens)
        #expect(try await tokens.accessToken() == "at2")
        #expect(await provider.tokenRequests.last?.contains("grant_type=refresh_token") == true)
    }

    @Test func refusedRefreshSignsOut() async throws {
        let provider = FakeProvider()
        await provider.setExpiresIn(0)
        await provider.setRefusesRefresh()
        let tokens = manager(provider)
        try await signIn(tokens)
        await #expect(throws: OpenIDConnect.Failure.self) { try await tokens.accessToken() }
        #expect(await !tokens.isSignedIn)
    }
}
