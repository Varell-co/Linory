import CryptoKit
import Foundation

/// Spotify login with Authorization Code + PKCE (RFC 7636). Pure: no network, no randomness of its own.
public enum SpotifyPKCE {
    public static let authorizeEndpoint = URL(string: "https://accounts.spotify.com/authorize")!
    public static let tokenEndpoint = URL(string: "https://accounts.spotify.com/api/token")!
    public static let redirectURI = "linory://callback"
    public static let callbackScheme = "linory"
    public static let scopes = ["user-library-read", "playlist-read-private", "playlist-read-collaborative",
                                "playlist-modify-private", "user-read-currently-playing",
                                "user-read-playback-state", "user-modify-playback-state",
                                "user-library-modify", "user-top-read"]

    /// Logins from before playback control was added lack the two playback scopes.
    public static func grantsAllScopes(_ granted: String) -> Bool {
        Set(scopes).isSubset(of: Set(granted.split(separator: " ").map(String.init)))
    }

    public enum Grant {
        case authorizationCode(code: String, verifier: String)
        case refreshToken(String)
    }

    /// 32 random bytes give the 43-character minimum; 96 give the 128-character maximum.
    public static func verifier(randomBytes: [UInt8]) -> String { base64URL(Data(randomBytes)) }

    public static func challenge(for verifier: String) -> String { base64URL(Data(SHA256.hash(data: Data(verifier.utf8)))) }

    public static func authorizeURL(clientID: String, redirectURI: String, scopes: [String], state: String, challenge: String) -> URL {
        let query = formEncoded([
            ("client_id", clientID), ("response_type", "code"), ("redirect_uri", redirectURI),
            ("code_challenge_method", "S256"), ("code_challenge", challenge),
            ("scope", scopes.joined(separator: " ")), ("state", state),
        ])
        return URL(string: "\(authorizeEndpoint.absoluteString)?\(query)")!
    }

    /// `application/x-www-form-urlencoded` body for the token endpoint. Public clients send `client_id` and no secret.
    public static func tokenRequestBody(clientID: String, redirectURI: String, grant: Grant) -> String {
        switch grant {
        case let .authorizationCode(code, verifier):
            return formEncoded([("grant_type", "authorization_code"), ("code", code), ("redirect_uri", redirectURI),
                                ("client_id", clientID), ("code_verifier", verifier)])
        case let .refreshToken(token):
            return formEncoded([("grant_type", "refresh_token"), ("refresh_token", token), ("client_id", clientID)])
        }
    }

    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    /// Encodes everything except RFC 3986 unreserved characters, so `:`, `/`, `+` and spaces never reach Spotify raw.
    static func formEncoded(_ pairs: [(String, String)]) -> String {
        let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        func encode(_ value: String) -> String { value.addingPercentEncoding(withAllowedCharacters: unreserved) ?? value }
        return pairs.map { "\(encode($0.0))=\(encode($0.1))" }.joined(separator: "&")
    }
}
