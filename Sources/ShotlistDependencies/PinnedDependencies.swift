#if DEBUG && canImport(UIKit)
import Dependencies
import Foundation
import ShotlistKit

extension ShotlistContext {
    /// The values Shotlist pins for every scene: the run's fixed date, incrementing UUIDs, a clock
    /// that never waits, and the scene's locale.
    public func pin(_ dependencies: inout DependencyValues) {
        dependencies.date = .constant(now)
        dependencies.uuid = .incrementing
        dependencies.continuousClock = ImmediateClock()
        dependencies.locale = locale
    }
}

extension Array where Element == any ShotlistScene {
    /// Builds every scene, and runs its `prepare`, with pinned swift-dependencies values, so
    /// anything resolving `@Dependency(\.date)` and friends during the scene sees the run's values.
    ///
    /// ```swift
    /// ShotlistHost(scenes: Screenshots.scenes.pinningDependencies()) { RootView() }
    /// ```
    @MainActor
    public func pinningDependencies() -> [any ShotlistScene] {
        map { scene in
            WrappedScene(
                scene,
                prepare: { context, work in
                    try await withDependencies { context.pin(&$0) } operation: { try await work() }
                },
                content: { context, build in
                    try withDependencies { context.pin(&$0) } operation: { try build() }
                }
            )
        }
    }
}
#endif
