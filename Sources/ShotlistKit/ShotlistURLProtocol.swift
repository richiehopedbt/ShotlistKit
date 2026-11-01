#if DEBUG && canImport(UIKit)
import Foundation

/// Answers HTTP(S) requests from the engine's fixtures over the control channel. An unmatched
/// request fails, and fails its scene, naming the URL.
public final class ShotlistURLProtocol: URLProtocol {
    /// `@unchecked Sendable`: URLSession calls startLoading and stopLoading serially on the
    /// protocol's thread, and `loading` is only touched there. Delivery goes back to that thread
    /// through its run loop, as URLProtocol requires, so `target` is never used concurrently.
    private struct Handle: @unchecked Sendable {
        let target: ShotlistURLProtocol
        let runLoop: CFRunLoop

        func perform(_ work: @escaping (ShotlistURLProtocol) -> Void) {
            let target = self.target
            CFRunLoopPerformBlock(runLoop, CFRunLoopMode.commonModes.rawValue) { work(target) }
            CFRunLoopWakeUp(runLoop)
        }
    }

    private var loading: Task<Void, Never>?

    static let asyncImageSession: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.protocolClasses = [ShotlistURLProtocol.self] + (configuration.protocolClasses ?? [])
        return URLSession(configuration: configuration)
    }()

    public override class func canInit(with request: URLRequest) -> Bool {
        guard Shotlist.isActive, let scheme = request.url?.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }

    public override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    public override func startLoading() {
        let request = self.request
        let method = request.httpMethod ?? "GET"
        let url = request.url?.absoluteString ?? ""
        let fixtureRequest = FixtureRequest(
            id: UUID().uuidString,
            method: method,
            url: url,
            headers: request.allHTTPHeaderFields ?? [:],
            body: request.httpBody ?? request.httpBodyStream.map(Self.readAll)
        )
        Readiness.shared.beginRequest(fixtureRequest.id, "\(method) \(url)")
        let handle = Handle(target: self, runLoop: CFRunLoopGetCurrent())
        loading = Task {
            do {
                let response = try await ShotlistRuntime.shared.fetchFixture(fixtureRequest)
                handle.perform { $0.deliver(response, for: request) }
                Readiness.shared.endRequest(fixtureRequest.id, unmatched: response.unmatched)
            } catch {
                handle.perform { $0.client?.urlProtocol($0, didFailWithError: error) }
                Readiness.shared.endRequest(fixtureRequest.id, unmatched: "\(method) \(url) failed: \(error)")
            }
        }
    }

    public override func stopLoading() {
        loading?.cancel()
    }

    private func deliver(_ response: FixtureResponse, for request: URLRequest) {
        if let unmatched = response.unmatched {
            let error = NSError(domain: "Shotlist", code: 404, userInfo: [NSLocalizedDescriptionKey: unmatched])
            client?.urlProtocol(self, didFailWithError: error)
            return
        }
        guard let url = request.url,
              let http = HTTPURLResponse(url: url, statusCode: response.status, httpVersion: "HTTP/1.1", headerFields: response.headers) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
        if let body = response.body {
            client?.urlProtocol(self, didLoad: body)
        }
        client?.urlProtocolDidFinishLoading(self)
    }

    private static func readAll(_ stream: InputStream) -> Data {
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 16_384)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 { break }
            data.append(buffer, count: count)
        }
        return data
    }
}
#endif
