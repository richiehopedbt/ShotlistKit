import Foundation
import ShotlistProtocol
import Testing

struct ProtocolTests {
    @Test func messagesRoundTripAsJSON() throws {
        let hello = AppMessage.hello(Hello(protocolVersion: ShotlistWire.version, token: "t", pid: 42, bundleID: "app.example",
                                           scenes: [SceneInfo(id: "home", kind: "swiftui", postures: [.closed], isolation: .relaunch)]))
        let decoded = try JSONDecoder().decode(AppMessage.self, from: JSONEncoder().encode(hello))
        guard case .hello(let value) = decoded else {
            Issue.record("expected hello")
            return
        }
        #expect(value.pid == 42)
        #expect(value.scenes.first?.postures == [.closed])
        #expect(value.scenes.first?.isolation == .relaunch)

        let show = HostMessage.show(ShowScene(id: "home", posture: .open))
        guard case .show(let request) = try JSONDecoder().decode(HostMessage.self, from: JSONEncoder().encode(show)) else {
            Issue.record("expected show")
            return
        }
        #expect(request.posture == .open)
    }

    @Test func encodedMessagesAreSingleLines() throws {
        let data = try JSONEncoder().encode(AppMessage.failed(scene: "x", reason: "line one\nline two"))
        #expect(!data.contains(0x0A))
    }

    @Test func withDeadlineReturnsEvenWhenTheWorkIgnoresCancellation() async throws {
        let started = ContinuousClock.now
        do {
            _ = try await withDeadline(0.2, "stubborn work") {
                // Ignores cancellation on purpose, like a scene's prepare that never returns.
                await withCheckedContinuation { (_: CheckedContinuation<Void, Never>) in }
                return 1
            }
            Issue.record("expected a timeout")
        } catch let error as TimeoutError {
            #expect(error.description == "timed out after 0.2 s waiting for stubborn work")
        }
        #expect(ContinuousClock.now - started < .seconds(2))
    }

    @Test func withTimeoutReturnsTheValue() async throws {
        let value = try await withTimeout(1, "quick work") { 7 }
        #expect(value == 7)
    }
}
