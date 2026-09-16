import Foundation
import CryptoKit
import Security

/// TOKEN MASTER's own Claude OAuth (PKCE) so it holds a *separate* access token
/// with its own rate budget — independent of the Claude Code CLI token. Uses the
/// public Claude Code client id and the manual code-paste flow.
final class ClaudeOAuth: @unchecked Sendable {
    static let shared = ClaudeOAuth()

    private let clientID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
    private let authorizeURL = "https://claude.ai/oauth/authorize"
    private let tokenURL = "https://console.anthropic.com/v1/oauth/token"
    private let redirectURI = "https://console.anthropic.com/oauth/code/callback"
    private let scopes = "org:create_api_key user:profile user:inference"

    private let lock = NSLock()
    private var pendingVerifier: String?
    private var pendingState: String?

    private let storeURL: URL = {
        let d = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TokenMaster", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d.appendingPathComponent("claude_oauth.json")
    }()

    struct Tokens: Codable { var accessToken: String; var refreshToken: String; var expiresAt: Double }

    var isConnected: Bool { (loadTokens()?.refreshToken.isEmpty == false) }

    // MARK: Login flow

    /// Builds the authorize URL and remembers the PKCE verifier + state.
    func authorizeURLString() -> String {
        let verifier = Self.randomURLSafe(32)
        let challenge = Self.base64url(Data(SHA256.hash(data: Data(verifier.utf8))))
        let state = Self.randomURLSafe(24)
        lock.lock(); pendingVerifier = verifier; pendingState = state; lock.unlock()

        var c = URLComponents(string: authorizeURL)!
        c.queryItems = [
            .init(name: "code", value: "true"),
            .init(name: "client_id", value: clientID),
            .init(name: "response_type", value: "code"),
            .init(name: "redirect_uri", value: redirectURI),
            .init(name: "scope", value: scopes),
            .init(name: "code_challenge", value: challenge),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "state", value: state)
        ]
        return c.url!.absoluteString
    }

    /// Exchanges the pasted `code#state` for tokens.
    func completeLogin(pasted: String) throws {
        let trimmed = pasted.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(separator: "#", maxSplits: 1).map(String.init)
        let code = parts.first ?? trimmed
        lock.lock(); let verifier = pendingVerifier; let pState = pendingState; lock.unlock()
        let state = parts.count > 1 ? parts[1] : (pState ?? "")
        guard let verifier else { throw err("Tap “Sign in” first, then paste the code.") }

        let tokens = try postToken([
            "grant_type": "authorization_code",
            "code": code, "state": state,
            "client_id": clientID, "redirect_uri": redirectURI,
            "code_verifier": verifier
        ])
        saveTokens(tokens)
    }

    func signOut() { try? FileManager.default.removeItem(at: storeURL) }

    // MARK: Token access

    /// A valid access token, refreshing if near expiry. Call off the main thread.
    func validAccessToken() -> String? {
        guard var t = loadTokens() else { return nil }
        if Date().timeIntervalSince1970 > t.expiresAt - 60 {
            guard let refreshed = try? postToken([
                "grant_type": "refresh_token",
                "refresh_token": t.refreshToken,
                "client_id": clientID,
                "scope": scopes
            ]) else { return nil }
            saveTokens(refreshed); t = refreshed
        }
        return t.accessToken
    }

    // MARK: HTTP

    private func postToken(_ body: [String: Any]) throws -> Tokens {
        var req = URLRequest(url: URL(string: tokenURL)!, timeoutInterval: 20)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // console.anthropic.com is behind Cloudflare, which bans default client
        // signatures (error 1010). Present a browser-like User-Agent.
        req.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        var result: Tokens?
        var failure: String?
        let sem = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: req) { data, resp, _ in
            defer { sem.signal() }
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            guard code == 200, let data,
                  let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                failure = "token exchange failed (HTTP \(code))"; return
            }
            guard let at = o["access_token"] as? String,
                  let rt = o["refresh_token"] as? String else {
                failure = "response missing tokens"; return
            }
            let exp = (o["expires_in"] as? NSNumber)?.doubleValue ?? 3600
            result = Tokens(accessToken: at, refreshToken: rt,
                            expiresAt: Date().timeIntervalSince1970 + exp)
        }.resume()
        _ = sem.wait(timeout: .now() + 22)
        if let result { return result }
        throw err(failure ?? "network error")
    }

    // MARK: Storage

    private func loadTokens() -> Tokens? {
        guard let d = try? Data(contentsOf: storeURL) else { return nil }
        return try? JSONDecoder().decode(Tokens.self, from: d)
    }

    private func saveTokens(_ t: Tokens) {
        guard let d = try? JSONEncoder().encode(t) else { return }
        try? d.write(to: storeURL)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: storeURL.path)
    }

    private func err(_ m: String) -> NSError {
        NSError(domain: "ClaudeOAuth", code: 1, userInfo: [NSLocalizedDescriptionKey: m])
    }

    static let userAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 "
        + "(KHTML, like Gecko) Version/17.0 Safari/605.1.15"

    static func randomURLSafe(_ n: Int) -> String {
        var b = [UInt8](repeating: 0, count: n)
        _ = SecRandomCopyBytes(kSecRandomDefault, n, &b)
        return base64url(Data(b))
    }

    static func base64url(_ d: Data) -> String {
        d.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
