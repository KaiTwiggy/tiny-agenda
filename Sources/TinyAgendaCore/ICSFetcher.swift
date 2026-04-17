import Foundation

public enum ICSFetcher {
    public enum FetchError: LocalizedError {
        case invalidURL
        case http(Int)
        case notUTF8
        case responseTooLarge(Int)

        public var errorDescription: String? {
            switch self {
            case .invalidURL: return "Invalid calendar URL."
            case .http(let c): return "Server returned HTTP \(c)."
            case .notUTF8: return "Calendar response was not valid UTF-8."
            case .responseTooLarge(let max):
                return "Calendar response exceeded \(max / 1_048_576) MB."
            }
        }
    }

    /// Default cap for untrusted feeds (bytes).
    public static let defaultMaxResponseBytes = 10_485_760

    public static let sharedSession: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 60
        c.timeoutIntervalForResource = 120
        c.httpCookieAcceptPolicy = .never
        return URLSession(configuration: c)
    }()

    public static func fetchString(
        from urlString: String,
        session: URLSession? = nil,
        maxBytes: Int = defaultMaxResponseBytes
    ) async throws -> String {
        // HTTPS only: ICS feed URLs are secrets (query-string tokens). Refuse http:// so a local
        // MITM cannot read the token, even if the user pasted a plaintext URL.
        guard let url = URL(string: urlString), url.scheme?.lowercased() == "https" else {
            throw FetchError.invalidURL
        }
        let sess = session ?? sharedSession
        let (data, response) = try await sess.data(from: url)
        if data.count > maxBytes {
            throw FetchError.responseTooLarge(maxBytes)
        }
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw FetchError.http(http.statusCode)
        }
        guard let text = String(data: data, encoding: .utf8) else { throw FetchError.notUTF8 }
        return text
    }
}
