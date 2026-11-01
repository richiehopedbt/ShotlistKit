#if DEBUG && canImport(UIKit)
import Foundation
import Observation
import os
import UIKit

/// Entry points for the app.
public enum Shotlist {
    /// True only when the Shotlist engine launched the app.
    public static var isActive: Bool {
        UserDefaults.standard.string(forKey: ShotlistWire.Argument.port) != nil
    }

    /// Add these to any `URLSessionConfiguration` you create, so its requests are answered from
    /// fixtures: `configuration.protocolClasses = Shotlist.protocolClasses + (configuration.protocolClasses ?? [])`.
    /// `URLSession.shared` and SwiftUI's `AsyncImage` under `ShotlistHost` need nothing.
    public static var protocolClasses: [AnyClass] { [ShotlistURLProtocol.self] }

    /// The run's fixed date, from the engine (`fixedDate` in shotlist.json).
    public static var now: Date {
        UserDefaults.standard.string(forKey: ShotlistWire.Argument.now)
            .flatMap { try? Date.ISO8601FormatStyle().parse($0) }
            ?? Date(timeIntervalSince1970: 1_781_433_000) // 2026-06-14 10:30 UTC
    }

    /// Keeps the current scene from being captured until `work` finishes. Use it for async work
    /// that ShotlistKit can't see, such as an image decode or a database query.
    public static func hold<T>(_ label: String, _ work: () async throws -> T) async rethrows -> T {
        let id = Readiness.shared.beginHold(label)
        defer { Readiness.shared.endHold(id) }
        return try await work()
    }

    /// Holds the scene until `condition` is true, re-checking whenever the `@Observable` state it
    /// reads changes. For loading ShotlistKit can't see, such as a local store's async streams:
    ///
    /// ```swift
    /// await Shotlist.waitUntil("league loaded") { model.league?.games.isEmpty == false }
    /// ```
    @MainActor
    public static func waitUntil(_ label: String, _ condition: @escaping @MainActor () -> Bool) async {
        let id = Readiness.shared.beginHold(label)
        defer { Readiness.shared.endHold(id) }
        while !condition() {
            if Task.isCancelled { return }
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                let resumed = OSAllocatedUnfairLock(initialState: false)
                let resumeOnce: @Sendable () -> Void = {
                    if resumed.withLock({ done in defer { done = true }; return !done }) { continuation.resume() }
                }
                let satisfied = withObservationTracking { condition() } onChange: { resumeOnce() }
                if satisfied { resumeOnce() }
            }
        }
    }

    /// The non-async form of `hold`: release the returned hold when the work is done.
    public static func beginHold(_ label: String) -> ShotlistHold {
        ShotlistHold(id: Readiness.shared.beginHold(label))
    }

    /// The UIKit host. Install it as the window's root when `isActive`; `root` builds the app's
    /// normal root view controller, which link scenes start from.
    @MainActor
    public static func hostingController(scenes: [any ShotlistScene], root: @escaping @MainActor () -> UIViewController) -> UIViewController {
        hostingController(scenes: scenes) { (_: ShotlistContext?) in root() }
    }

    /// As above; the root receives the link scene's context (nil before the first scene).
    @MainActor
    public static func hostingController(scenes: [any ShotlistScene], root: @escaping @MainActor (ShotlistContext?) -> UIViewController) -> UIViewController {
        ShotlistRuntime.shared.configure(scenes: scenes)
        return ShotlistContainerController(runtime: .shared, makeRoot: root)
    }
}

/// An open hold on the current scene's readiness.
public final class ShotlistHold: Sendable {
    private let id: UUID

    init(id: UUID) {
        self.id = id
    }

    public func release() {
        Readiness.shared.endHold(id)
    }

    deinit {
        Readiness.shared.endHold(id)
    }
}
#endif
