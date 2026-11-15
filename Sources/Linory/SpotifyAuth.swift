import AppKit
import AuthenticationServices
import LyricsCore
import os

enum SpotifyError: LocalizedError {
    /// No Client ID or no stored login.
    case notConnected
    /// The refresh token was revoked or expired; the user must connect again.
    case loginExpired
    case loginFailed(String)
    case http(Int)

    var errorDescription: String? {
        switch self {
        case .notConnected: return "Not connected"
        case .loginExpired: return "Login expired"
        case .loginFailed(let detail): return detail
        case .http(let status): return "HTTP \(status)"
        }
    }
}

/// Spotify login (Authorization Code + PKCE). The refresh token lives in the Keychain, the access token only in memory.
@MainActor
final class SpotifyAuth: ObservableObject {
    enum State: Equatable {
        case disconnected, connecting
        case connected(String)
        case failed(String)
    }

    @Published private(set) var state: State = .disconnected
    /// Connected with a login from before playback control was added; Shuffle & play then falls back to AppleScript.
    @Published private(set) var needsReconnect = false
    private(set) var user: SpotifyUser?
    private(set) lazy var api = SpotifyAPI(auth: self)
    private var accessToken: String?
    private var expiresAt = Date.distantPast
    private var refreshing: Task<String, Error>?
    private var session: ASWebAuthenticationSession?
    private let anchor = AnchorProvider()
    private static let account = "spotify-refresh-token"
    private let log = Logger(subsystem: LyricsService.subsystem, category: "spotify")

    /// Created by the app delegate before the main actor is known to the compiler; holds no state that needs isolation yet.
    nonisolated init() {}

    var clientID: String { (UserDefaults.standard.string(forKey: "spotifyClientID") ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }
    var isConnected: Bool { if case .connected = state { return true } else { return false } }
    var canControlPlayback: Bool { isConnected && !needsReconnect }
    private var hasStoredLogin: Bool { !clientID.isEmpty && Keychain.read(account: Self.account) != nil }

    /// At launch: reconnect silently when a login is stored.
    func restore() {
        guard hasStoredLogin else { return }
        state = .connecting
        Task { await loadUser() }
    }

    /// After a launch without network the login is still stored; try again when the user needs it.
    func retryIfNeeded() {
        guard case .failed = state, hasStoredLogin else { return }
        state = .connecting
        Task { await loadUser() }
    }

    func connect() {
        let clientID = clientID
        guard !clientID.isEmpty else { return }
        session?.cancel()
        guard let verifier = Self.randomString(bytes: 32), let expectedState = Self.randomString(bytes: 16) else {
            state = .failed("SecRandomCopyBytes failed")
            return
        }
        let url = SpotifyPKCE.authorizeURL(clientID: clientID, redirectURI: SpotifyPKCE.redirectURI, scopes: SpotifyPKCE.scopes,
                                           state: expectedState, challenge: SpotifyPKCE.challenge(for: verifier))
        state = .connecting
        let session = ASWebAuthenticationSession(url: url, callbackURLScheme: SpotifyPKCE.callbackScheme) { [weak self] callback, error in
            Task { @MainActor in
                await self?.finishLogin(callback: callback, error: error, verifier: verifier, expectedState: expectedState, clientID: clientID)
            }
        }
        anchor.window = NSApp.keyWindow
        session.presentationContextProvider = anchor
        self.session = session
        if !session.start() { state = .failed("The login window could not be opened.") }
    }

    func disconnect() {
        session?.cancel()
        session = nil
        Keychain.delete(account: Self.account)
        accessToken = nil
        expiresAt = .distantPast
        user = nil
        needsReconnect = false
        state = .disconnected
        log.info("disconnected")
    }

    /// Refreshes when the token expires within 60 s.
    func validAccessToken() async throws -> String {
        if let accessToken, expiresAt.timeIntervalSinceNow > 60 { return accessToken }
        return try await refreshAccessToken()
    }

    /// Concurrent callers share one refresh.
    func refreshAccessToken() async throws -> String {
        if let refreshing { return try await refreshing.value }
        let task = Task { try await performRefresh() }
        refreshing = task
        defer { refreshing = nil }
        return try await task.value
    }

    private func performRefresh() async throws -> String {
        let clientID = clientID
        guard !clientID.isEmpty, let refreshToken = Keychain.read(account: Self.account) else { throw SpotifyError.notConnected }
        do {
            let token = try await requestToken(.refreshToken(refreshToken), clientID: clientID)
            store(token)
            log.info("token refreshed (expires in \(token.expiresIn) s)")
            return token.accessToken
        } catch SpotifyError.loginExpired {
            log.error("refresh rejected, login removed")
            disconnect()
            throw SpotifyError.loginExpired
        }
    }

    private func finishLogin(callback: URL?, error: Error?, verifier: String, expectedState: String, clientID: String) async {
        session = nil
        if let error {
            if (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin {
                state = .disconnected
            } else {
                fail(error.localizedDescription)
            }
            return
        }
        let items = callback.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }?.queryItems ?? []
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
        if value("error") == "access_denied" { state = .disconnected; return }
        guard value("state") == expectedState, let code = value("code") else {
            fail(value("error") ?? "Invalid login response")
            return
        }
        do {
            let token = try await requestToken(.authorizationCode(code: code, verifier: verifier), clientID: clientID)
            store(token)
            await loadUser()
        } catch {
            fail(error.localizedDescription)
        }
    }

    private func loadUser() async {
        do {
            let user = try await api.me()
            self.user = user
            state = .connected(user.displayName ?? user.id)
            log.info("connected as \(user.displayName ?? user.id, privacy: .public)")
        } catch SpotifyError.loginExpired, SpotifyError.notConnected {
            disconnect()
        } catch {
            fail(error.localizedDescription)
        }
    }

    private func fail(_ message: String) {
        state = .failed(message)
        log.error("login failed: \(message, privacy: .public)")
    }

    private func store(_ token: SpotifyToken) {
        if let scope = token.scope { needsReconnect = !SpotifyPKCE.grantsAllScopes(scope) }
        accessToken = token.accessToken
        expiresAt = Date().addingTimeInterval(TimeInterval(token.expiresIn))
        if let refresh = token.refreshToken, !Keychain.write(refresh, account: Self.account) {
            log.error("keychain write failed")
        }
    }

    private func requestToken(_ grant: SpotifyPKCE.Grant, clientID: String) async throws -> SpotifyToken {
        var request = URLRequest(url: SpotifyPKCE.tokenEndpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(SpotifyPKCE.tokenRequestBody(clientID: clientID, redirectURI: SpotifyPKCE.redirectURI, grant: grant).utf8)
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if (200..<300).contains(status) { return try JSONDecoder().decode(SpotifyToken.self, from: data) }
        let error = (try? JSONDecoder().decode(SpotifyTokenError.self, from: data))?.error
        // invalid_grant: revoked or expired refresh token. invalid_client: the Client ID no longer exists.
        if error == "invalid_grant" || error == "invalid_client" { throw SpotifyError.loginExpired }
        throw SpotifyError.loginFailed(error ?? "HTTP \(status)")
    }

    private static func randomString(bytes count: Int) -> String? {
        var bytes = [UInt8](repeating: 0, count: count)
        guard SecRandomCopyBytes(kSecRandomDefault, count, &bytes) == errSecSuccess else { return nil }
        return SpotifyPKCE.verifier(randomBytes: bytes)
    }
}

/// The login sheet attaches to the window that was key when Connect was pressed (Settings).
private final class AnchorProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    weak var window: NSWindow?
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor { window ?? ASPresentationAnchor() }
}
