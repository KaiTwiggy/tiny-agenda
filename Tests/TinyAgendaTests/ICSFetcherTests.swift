import TinyAgendaCore
import Foundation
import XCTest

/// Returns a fixed oversized payload for any HTTP(S) request.
private final class OversizedURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.scheme == "https" || request.url?.scheme == "http"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        let data = Data(count: 200)
        let response = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

final class ICSFetcherTests: XCTestCase {
    override class func tearDown() {
        URLProtocol.unregisterClass(OversizedURLProtocol.self)
        super.tearDown()
    }

    func testRejectsHTTPURL() async throws {
        do {
            _ = try await ICSFetcher.fetchString(from: "http://example.invalid/feed.ics")
            XCTFail("expected error")
        } catch let e as ICSFetcher.FetchError {
            if case .invalidURL = e {} else {
                XCTFail("wrong error: \(e)")
            }
        }
    }

    func testRejectsResponseExceedingMaxBytes() async throws {
        URLProtocol.registerClass(OversizedURLProtocol.self)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [OversizedURLProtocol.self]
        let session = URLSession(configuration: config)

        do {
            _ = try await ICSFetcher.fetchString(
                from: "https://example.invalid/feed.ics",
                session: session,
                maxBytes: 100
            )
            XCTFail("expected error")
        } catch let e as ICSFetcher.FetchError {
            if case .responseTooLarge = e {} else {
                XCTFail("wrong error: \(e)")
            }
        }
    }
}
