// Not inside #if DEBUG: `@Shot` has to resolve in Release builds too, where it writes a body that
// shows `root` alone. A macro declaration compiles to nothing, so Release builds still contain no
// Shotlist code. Importing this module imports ShotlistKit as well.
@_exported import ShotlistKit

/// Writes your app's `body`: a `WindowGroup` showing `root`, which becomes the Shotlist host when
/// Shotlist launches the app to capture it.
///
/// ```swift
/// import ShotlistMacros
/// import SwiftUI
///
/// @main
/// @Shot
/// struct LarderApp: App {
///     var root: some View {
///         RootView()
///     }
/// }
/// ```
///
/// Your scenes come from `Screenshots.scenes`, as `shotlist init` writes them. Link scenes start
/// from `root`. If they need a different root, such as one with the run's fixed date, add a
/// `shotlistRoot` (inside `#if DEBUG` if it uses ShotlistKit):
///
/// ```swift
/// #if DEBUG
/// var shotlistRoot: some View {
///     RootView(clock: .fixed(Shotlist.now))
/// }
/// #endif
/// ```
///
/// or `func shotlistRoot(_ context: ShotlistContext?) -> some View` to receive the link scene's
/// context. For an app with more than one scene, or scene modifiers, host the scenes yourself
/// with `ShotlistHost`.
@attached(member, names: named(body))
public macro Shot() = #externalMacro(module: "ShotlistMacroPlugin", type: "ShotMacro")
