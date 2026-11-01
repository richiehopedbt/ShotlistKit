#if DEBUG && canImport(UIKit)
import Foundation
@_exported import ShotlistProtocol
import SwiftUI
import UIKit

/// Everything a scene needs to build itself for one capture.
public struct ShotlistContext: Sendable {
    public enum Appearance: String, Sendable {
        case light
        case dark
    }

    public let sceneID: String
    public let locale: Locale
    public let appearance: Appearance
    public let slot: String
    public let posture: Posture
    /// The run's fixed date. Route "now" through this when the app doesn't use swift-dependencies.
    public let now: Date

    public init(sceneID: String, locale: Locale, appearance: Appearance, slot: String, posture: Posture, now: Date) {
        self.sceneID = sceneID
        self.locale = locale
        self.appearance = appearance
        self.slot = slot
        self.posture = posture
        self.now = now
    }
}

/// What a scene shows once it's built.
public enum SceneContent {
    case swiftUI(AnyView)
    case uiKit(UIViewController)
    /// The app's own root (the host's trailing closure), then the scene's URL is opened.
    case root(URL)
}

/// One screen of the app, set up with fixture content, ready to capture.
@MainActor
public protocol ShotlistScene {
    var info: SceneInfo { get }
    /// Seeds stores, prepares fixtures and the like. Readiness waits for it.
    func prepare(_ context: ShotlistContext) async throws
    func content(_ context: ShotlistContext) throws -> SceneContent
}

extension ShotlistScene {
    public func prepare(_ context: ShotlistContext) async throws {}
}

/// The app's real SwiftUI root (or any view), built for the scene.
public struct SwiftUIScene<Content: View>: ShotlistScene {
    public let info: SceneInfo
    private let prepareWork: (@MainActor (ShotlistContext) async throws -> Void)?
    private let build: @MainActor (ShotlistContext) throws -> Content

    public init(
        _ id: String,
        postures: [Posture] = Posture.allCases,
        isolation: Isolation = .shared,
        prepare: (@MainActor (ShotlistContext) async throws -> Void)? = nil,
        @ViewBuilder content: @escaping @MainActor (ShotlistContext) throws -> Content
    ) {
        info = SceneInfo(id: id, kind: "swiftui", postures: postures, isolation: isolation)
        prepareWork = prepare
        build = content
    }

    public func prepare(_ context: ShotlistContext) async throws {
        try await prepareWork?(context)
    }

    public func content(_ context: ShotlistContext) throws -> SceneContent {
        .swiftUI(AnyView(try build(context)))
    }
}

/// A UIKit view controller hierarchy built for the scene.
public struct UIKitScene: ShotlistScene {
    public let info: SceneInfo
    private let prepareWork: (@MainActor (ShotlistContext) async throws -> Void)?
    private let build: @MainActor (ShotlistContext) throws -> UIViewController

    public init(
        _ id: String,
        postures: [Posture] = Posture.allCases,
        isolation: Isolation = .shared,
        prepare: (@MainActor (ShotlistContext) async throws -> Void)? = nil,
        content: @escaping @MainActor (ShotlistContext) throws -> UIViewController
    ) {
        info = SceneInfo(id: id, kind: "uikit", postures: postures, isolation: isolation)
        prepareWork = prepare
        build = content
    }

    public func prepare(_ context: ShotlistContext) async throws {
        try await prepareWork?(context)
    }

    public func content(_ context: ShotlistContext) throws -> SceneContent {
        .uiKit(try build(context))
    }
}

/// Starts from the app's normal root and lets the app's own URL handling navigate.
/// The URL is opened from inside the app, so no system "Open in…?" alert appears.
public struct LinkScene: ShotlistScene {
    public let info: SceneInfo
    private let prepareWork: (@MainActor (ShotlistContext) async throws -> Void)?
    private let url: @MainActor (ShotlistContext) -> URL

    public init(
        _ id: String,
        url: String,
        postures: [Posture] = Posture.allCases,
        isolation: Isolation = .relaunch,
        prepare: (@MainActor (ShotlistContext) async throws -> Void)? = nil
    ) {
        info = SceneInfo(id: id, kind: "link", url: url, postures: postures, isolation: isolation)
        prepareWork = prepare
        self.url = { _ in URL(string: url)! }
    }

    /// A URL that depends on the context, for example a locale-specific path.
    public init(
        _ id: String,
        postures: [Posture] = Posture.allCases,
        isolation: Isolation = .relaunch,
        prepare: (@MainActor (ShotlistContext) async throws -> Void)? = nil,
        url: @escaping @MainActor (ShotlistContext) -> URL
    ) {
        info = SceneInfo(id: id, kind: "link", postures: postures, isolation: isolation)
        prepareWork = prepare
        self.url = url
    }

    public func prepare(_ context: ShotlistContext) async throws {
        try await prepareWork?(context)
    }

    public func content(_ context: ShotlistContext) throws -> SceneContent {
        .root(url(context))
    }
}

/// Wraps another scene's prepare and build, used by adapters such as ShotlistDependencies.
public struct WrappedScene: ShotlistScene {
    public let base: any ShotlistScene
    private let wrapPrepare: @MainActor (ShotlistContext, @MainActor () async throws -> Void) async throws -> Void
    private let wrapContent: @MainActor (ShotlistContext, @MainActor () throws -> SceneContent) throws -> SceneContent

    public init(
        _ base: any ShotlistScene,
        prepare: @escaping @MainActor (ShotlistContext, @MainActor () async throws -> Void) async throws -> Void,
        content: @escaping @MainActor (ShotlistContext, @MainActor () throws -> SceneContent) throws -> SceneContent
    ) {
        self.base = base
        wrapPrepare = prepare
        wrapContent = content
    }

    public var info: SceneInfo { base.info }

    public func prepare(_ context: ShotlistContext) async throws {
        try await wrapPrepare(context) { try await base.prepare(context) }
    }

    public func content(_ context: ShotlistContext) throws -> SceneContent {
        try wrapContent(context) { try base.content(context) }
    }
}
#endif
