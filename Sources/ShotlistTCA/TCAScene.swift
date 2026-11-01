#if DEBUG && canImport(UIKit)
import ComposableArchitecture
import ShotlistDependencies
import ShotlistKit
import SwiftUI

/// The TCA fast path: a whole screen is one `State` value. The store is built with Shotlist's
/// pinned dependencies (date, UUID, clock, locale).
///
/// ```swift
/// TCAScene(
///     "player-stats",
///     state: AppFeature.State(tab: .players, path: [.stats(.fixture)]),
///     reducer: { AppFeature() },
///     view: { AppView(store: $0) }
/// )
/// ```
public struct TCAScene<R: Reducer, Content: View>: ShotlistScene {
    public let info: SceneInfo
    private let state: @MainActor (ShotlistContext) -> R.State
    private let reducer: @MainActor () -> R
    private let view: @MainActor (StoreOf<R>) -> Content

    public init(
        _ id: String,
        postures: [Posture] = Posture.allCases,
        isolation: Isolation = .shared,
        state: @autoclosure @escaping @MainActor () -> R.State,
        reducer: @escaping @MainActor () -> R,
        @ViewBuilder view: @escaping @MainActor (StoreOf<R>) -> Content
    ) {
        self.init(id, postures: postures, isolation: isolation, state: { _ in state() }, reducer: reducer, view: view)
    }

    /// State that depends on the context, such as locale-specific fixture names.
    public init(
        _ id: String,
        postures: [Posture] = Posture.allCases,
        isolation: Isolation = .shared,
        state: @escaping @MainActor (ShotlistContext) -> R.State,
        reducer: @escaping @MainActor () -> R,
        @ViewBuilder view: @escaping @MainActor (StoreOf<R>) -> Content
    ) {
        info = SceneInfo(id: id, kind: "tca", postures: postures, isolation: isolation)
        self.state = state
        self.reducer = reducer
        self.view = view
    }

    public func content(_ context: ShotlistContext) throws -> SceneContent {
        // State too is built with the pinned values, so an init reading \.uuid or \.date is stable.
        let store = withDependencies { context.pin(&$0) } operation: {
            Store(initialState: state(context)) {
                reducer()
            } withDependencies: {
                context.pin(&$0)
            }
        }
        return .swiftUI(AnyView(view(store)))
    }
}
#endif
