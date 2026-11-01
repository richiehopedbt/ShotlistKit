#if DEBUG && canImport(UIKit)
import Foundation
import Network
import Observation
import SwiftUI
import UIKit

/// The app side of a capture run: talks to the engine, builds and presents scenes, and decides
/// when a scene is ready. One per process.
@MainActor
@Observable
final class ShotlistRuntime {
    static let shared = ShotlistRuntime()

    enum Presented {
        case root(id: Int)
        case swiftUI(AnyView, id: Int)
        case uiKit(UIViewController, id: Int)
    }

    private(set) var presented: Presented = .root(id: 0)
    /// The context of the link scene the root is showing, for hosts whose root takes one.
    @ObservationIgnored private(set) var rootContext: ShotlistContext?
    private(set) var status = "Waiting for the Shotlist engine"

    @ObservationIgnored private var scenes: [String: any ShotlistScene] = [:]
    @ObservationIgnored private var sceneInfos: [SceneInfo] = []
    @ObservationIgnored private var channel: LineChannel?
    @ObservationIgnored private var configured = false
    @ObservationIgnored private var started = false
    @ObservationIgnored private var appearedID = -1
    @ObservationIgnored private var nextID = 1
    @ObservationIgnored private var pending: [String: CheckedContinuation<FixtureResponse, Error>] = [:]
    @ObservationIgnored private var showTask: Task<Void, Never>?
    @ObservationIgnored private let geometry = SceneGeometryReporter()

    private init() {}

    // MARK: Setup

    /// Called from the host's initialiser, before the app's root is built.
    func configure(scenes: [any ShotlistScene]) {
        guard Shotlist.isActive, !configured else { return }
        configured = true
        for scene in scenes {
            let info = scene.info
            precondition(self.scenes[info.id] == nil, "Two Shotlist scenes share the id '\(info.id)'")
            self.scenes[info.id] = scene
            sceneInfos.append(info)
        }
        URLProtocol.registerClass(ShotlistURLProtocol.self)
        UIView.setAnimationsEnabled(false)
        UITextField.appearance().tintColor = .clear
        UITextView.appearance().tintColor = .clear
    }

    func start() {
        guard configured, !started else { return }
        started = true
        Task { await connect() }
    }

    private func connect() async {
        let defaults = UserDefaults.standard
        guard let portText = defaults.string(forKey: ShotlistWire.Argument.port),
              let port = NWEndpoint.Port(portText) else { return }
        let token = defaults.string(forKey: ShotlistWire.Argument.token) ?? ""
        let channel = LineChannel(connection: NWConnection(host: "127.0.0.1", port: port, using: .tcp))
        do {
            try await withTimeout(10, "the Shotlist engine on 127.0.0.1:\(portText)") { try await channel.start() }
        } catch {
            status = "Couldn't reach the Shotlist engine: \(error)"
            return
        }
        self.channel = channel
        channel.post(AppMessage.hello(Hello(
            protocolVersion: ShotlistWire.version,
            token: token,
            pid: ProcessInfo.processInfo.processIdentifier,
            bundleID: Bundle.main.bundleIdentifier ?? "unknown",
            scenes: sceneInfos
        )))
        do {
            for try await line in channel.lines {
                handle(try JSONDecoder().decode(HostMessage.self, from: line))
            }
            if !status.hasPrefix("Rejected") { status = "The Shotlist engine closed the channel" }
        } catch {
            status = "Shotlist channel error: \(error)"
        }
        let waiting = pending
        pending.removeAll()
        for continuation in waiting.values { continuation.resume(throwing: ChannelError("control channel closed")) }
        self.channel = nil
    }

    func send(_ message: AppMessage) {
        channel?.post(message)
    }

    private func handle(_ message: HostMessage) {
        switch message {
        case .welcome:
            status = "Connected to the Shotlist engine"
            geometry.start { [weak self] screen in self?.send(.screen(screen)) }
        case .reject(let reason):
            status = "Rejected by the Shotlist engine: \(reason)"
            channel?.close()
        case .ping(let seq):
            send(.pong(seq: seq))
        case .show(let request):
            showTask?.cancel()
            showTask = Task { await show(request) }
        case .fixtureResponse(let response):
            pending.removeValue(forKey: response.id)?.resume(returning: response)
        }
    }

    // MARK: Fixtures

    func fetchFixture(_ request: FixtureRequest) async throws -> FixtureResponse {
        guard let channel else { throw ChannelError("no Shotlist control channel for \(request.method) \(request.url)") }
        return try await withCheckedThrowingContinuation { continuation in
            pending[request.id] = continuation
            channel.post(AppMessage.fixtureRequest(request))
        }
    }

    // MARK: Showing a scene

    private var sceneTimeout: Double {
        UserDefaults.standard.string(forKey: ShotlistWire.Argument.sceneTimeout).flatMap(Double.init) ?? 20
    }

    private func show(_ request: ShowScene) async {
        guard scenes[request.id] != nil else {
            send(.failed(scene: request.id, reason: "the app has no scene '\(request.id)'; it has \(sceneInfos.map(\.id).joined(separator: ", "))"))
            return
        }
        Readiness.shared.resetUnmatched()
        let id = request.id
        let posture = request.posture
        let timeout = sceneTimeout
        do {
            try await withDeadline(timeout, "scene '\(id)'") { @MainActor in
                try await self.prepareAndSettle(id, posture: posture)
            }
            guard !Task.isCancelled else { return }
            send(.ready(scene: id))
        } catch is TimeoutError {
            send(.failed(scene: id, reason: "not ready after \(Int(timeout)) s: \(Readiness.shared.describeOpenWork())"))
        } catch {
            send(.failed(scene: id, reason: String(describing: error)))
        }
    }

    private func prepareAndSettle(_ sceneID: String, posture: Posture) async throws {
        guard let scene = scenes[sceneID] else { return }
        let context = makeContext(sceneID: sceneID, posture: posture)

        // 1. The scene's own preparation.
        try await scene.prepare(context)
        try Task.checkCancellation()

        // 2. The root has appeared (or the link has been handed to the app), no request is in
        //    flight and no hold is open.
        let content = try scene.content(context)
        switch content {
        case .swiftUI(let view):
            try await present(.swiftUI(view, id: nextID))
        case .uiKit(let controller):
            try await present(.uiKit(controller, id: nextID))
        case .root(let url):
            rootContext = context
            try await present(.root(id: nextID))
            let accepted = await UIApplication.shared.open(url)
            if !accepted { throw ChannelError("the app didn't accept \(url.absoluteString); check its URL scheme") }
        }
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)

        // 3. Two further frames with nothing new happening. Repeats if work started meanwhile.
        while true {
            try Task.checkCancellation()
            let before = Readiness.shared.snapshot
            if !before.holds.isEmpty || !before.requests.isEmpty {
                await Frames.wait(1)
                continue
            }
            await Frames.wait(2)
            let after = Readiness.shared.snapshot
            if after.generation == before.generation { break }
        }

        if let unmatched = Readiness.shared.snapshot.unmatched.first {
            throw ChannelError(unmatched)
        }

        // 4. Scroll indicators flash when a scroll view appears and fade a second or so later;
        //    a screenshot shouldn't depend on which side of the fade it lands.
        hideScrollIndicators()
        await Frames.wait(1)
    }

    private func hideScrollIndicators() {
        let windows = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows)
        var pending: [UIView] = windows
        while let view = pending.popLast() {
            if let scrollView = view as? UIScrollView {
                scrollView.showsVerticalScrollIndicator = false
                scrollView.showsHorizontalScrollIndicator = false
            }
            pending.append(contentsOf: view.subviews)
        }
    }

    private func present(_ next: Presented) async throws {
        let id = nextID
        nextID += 1
        presented = next
        while appearedID < id {
            try Task.checkCancellation()
            await Frames.wait(1)
        }
    }

    func didAppear(_ id: Int) {
        appearedID = max(appearedID, id)
    }

    private func makeContext(sceneID: String, posture: Posture) -> ShotlistContext {
        let defaults = UserDefaults.standard
        let locale = defaults.string(forKey: ShotlistWire.Argument.locale).map(Locale.init(identifier:)) ?? .current
        let appearance = defaults.string(forKey: ShotlistWire.Argument.appearance).flatMap(ShotlistContext.Appearance.init(rawValue:)) ?? .light
        let slot = defaults.string(forKey: ShotlistWire.Argument.slot) ?? "unknown"
        return ShotlistContext(sceneID: sceneID, locale: locale, appearance: appearance, slot: slot, posture: posture, now: Shotlist.now)
    }
}
#endif
