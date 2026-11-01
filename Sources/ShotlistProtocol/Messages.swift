// On iOS this module is compiled into the developer's app, so nothing survives a Release build.
#if DEBUG || !os(iOS)
import Foundation

/// The control-channel protocol between the engine (host) and ShotlistKit (app).
/// One JSON object per line over loopback TCP. Bump `version` on any incompatible change.
public enum ShotlistWire {
    public static let version = 1

    /// Launch argument keys. `-shotlist.port 51234` lands in UserDefaults as "shotlist.port".
    public enum Argument {
        public static let port = "shotlist.port"
        public static let token = "shotlist.token"
        public static let now = "shotlist.now"
        public static let slot = "shotlist.slot"
        public static let locale = "shotlist.locale"
        public static let appearance = "shotlist.appearance"
        public static let sceneTimeout = "shotlist.sceneTimeout"
    }
}

public enum Posture: String, Codable, Sendable, CaseIterable {
    /// Any single-display device, or the Duo folded (outer display).
    case closed
    /// The Duo unfolded (inner display).
    case open
}

public enum Isolation: String, Codable, Sendable {
    /// Scenes share one launch per locale and appearance.
    case shared
    /// The app is relaunched before this scene, for scenes that mutate global state.
    case relaunch
}

public struct SceneInfo: Codable, Sendable, Equatable {
    public var id: String
    /// "swiftui", "uikit", "link" or "tca"; informational.
    public var kind: String
    public var url: String?
    public var postures: [Posture]
    public var isolation: Isolation

    public init(id: String, kind: String, url: String? = nil, postures: [Posture] = Posture.allCases, isolation: Isolation = .shared) {
        self.id = id
        self.kind = kind
        self.url = url
        self.postures = postures
        self.isolation = isolation
    }
}

public struct Hello: Codable, Sendable {
    public var protocolVersion: Int
    public var token: String
    public var pid: Int32
    public var bundleID: String
    public var scenes: [SceneInfo]

    public init(protocolVersion: Int, token: String, pid: Int32, bundleID: String, scenes: [SceneInfo]) {
        self.protocolVersion = protocolVersion
        self.token = token
        self.pid = pid
        self.bundleID = bundleID
        self.scenes = scenes
    }
}

public struct ShowScene: Codable, Sendable {
    public var id: String
    public var posture: Posture

    public init(id: String, posture: Posture) {
        self.id = id
        self.posture = posture
    }
}

public struct FixtureRequest: Codable, Sendable {
    public var id: String
    public var method: String
    public var url: String
    public var headers: [String: String]
    public var body: Data?

    public init(id: String, method: String, url: String, headers: [String: String], body: Data?) {
        self.id = id
        self.method = method
        self.url = url
        self.headers = headers
        self.body = body
    }
}

public struct FixtureResponse: Codable, Sendable {
    public var id: String
    public var status: Int
    public var headers: [String: String]
    public var body: Data?
    /// Set when no fixture matched; the app fails the request with this text, and the scene with it.
    public var unmatched: String?

    public init(id: String, status: Int, headers: [String: String], body: Data?, unmatched: String?) {
        self.id = id
        self.status = status
        self.headers = headers
        self.body = body
        self.unmatched = unmatched
    }
}

public struct ScreenInfo: Codable, Sendable, Equatable {
    /// Native pixels of the screen the app's window scene is on.
    public var width: Int
    public var height: Int
    /// UIInterfaceOrientation raw value.
    public var orientation: Int

    public init(width: Int, height: Int, orientation: Int) {
        self.width = width
        self.height = height
        self.orientation = orientation
    }
}

/// Messages the engine sends to the app.
public enum HostMessage: Codable, Sendable {
    case welcome
    case reject(reason: String)
    case ping(seq: Int)
    case show(ShowScene)
    case fixtureResponse(FixtureResponse)
}

/// Messages the app sends to the engine.
public enum AppMessage: Codable, Sendable {
    case hello(Hello)
    case pong(seq: Int)
    case ready(scene: String)
    /// The scene can't become ready; `reason` names the open hold or pending URL.
    case failed(scene: String, reason: String)
    case fixtureRequest(FixtureRequest)
    case screen(ScreenInfo)
    case log(String)
}
#endif
