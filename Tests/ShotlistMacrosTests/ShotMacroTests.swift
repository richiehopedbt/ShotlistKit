import ShotlistMacroPlugin
import SwiftSyntaxMacroExpansion
import SwiftSyntaxMacrosGenericTestSupport
import Testing

struct ShotMacroTests {
    @Test func writesBodyAroundRoot() {
        expand(
            """
            @Shot
            struct LarderApp: App {
                var root: some View {
                    RootView()
                }
            }
            """,
            into: """
            struct LarderApp: App {
                var root: some View {
                    RootView()
                }

                var body: some Scene {
                    WindowGroup {
                        #if DEBUG && canImport(UIKit)
                        if ShotlistKit.Shotlist.isActive {
                            ShotlistKit.ShotlistHost(scenes: Screenshots.scenes) {
                                root
                            }
                        } else {
                            root
                        }
                        #else
                        root
                        #endif
                    }
                }
            }
            """
        )
    }

    @Test func linkScenesStartFromShotlistRootInsideIfDebug() {
        expand(
            """
            @Shot
            struct LarderApp: App {
                var root: some View { RootView() }

                #if DEBUG
                var shotlistRoot: some View { RootView(clock: .fixed(Shotlist.now)) }
                #endif
            }
            """,
            into: """
            struct LarderApp: App {
                var root: some View { RootView() }

                #if DEBUG
                var shotlistRoot: some View { RootView(clock: .fixed(Shotlist.now)) }
                #endif

                var body: some Scene {
                    WindowGroup {
                        #if DEBUG && canImport(UIKit)
                        if ShotlistKit.Shotlist.isActive {
                            ShotlistKit.ShotlistHost(scenes: Screenshots.scenes) {
                                shotlistRoot
                            }
                        } else {
                            root
                        }
                        #else
                        root
                        #endif
                    }
                }
            }
            """
        )
    }

    @Test func aShotlistRootFunctionReceivesTheContext() {
        expand(
            """
            @Shot
            public struct LarderApp: App {
                public init() {}
                var root: some View { RootView() }
                func shotlistRoot(_ context: ShotlistContext?) -> some View { RootView(clock: .fixed(context?.now ?? Shotlist.now)) }
            }
            """,
            into: """
            public struct LarderApp: App {
                public init() {}
                var root: some View { RootView() }
                func shotlistRoot(_ context: ShotlistContext?) -> some View { RootView(clock: .fixed(context?.now ?? Shotlist.now)) }

                public var body: some Scene {
                    WindowGroup {
                        #if DEBUG && canImport(UIKit)
                        if ShotlistKit.Shotlist.isActive {
                            ShotlistKit.ShotlistHost(scenes: Screenshots.scenes) { context in
                                shotlistRoot(context)
                            }
                        } else {
                            root
                        }
                        #else
                        root
                        #endif
                    }
                }
            }
            """
        )
    }

    @Test func anExistingBodyAsksForRoot() {
        expand(
            """
            @Shot
            struct LarderApp: App {
                var body: some Scene {
                    WindowGroup { RootView() }
                }
            }
            """,
            into: """
            struct LarderApp: App {
                var body: some Scene {
                    WindowGroup { RootView() }
                }
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "@Shot writes body itself: rename body to root, and make it your app's root view (what you'd put in its WindowGroup)",
                    line: 3, column: 5
                ),
            ]
        )
    }

    @Test func noRootSaysWhatToAdd() {
        expand(
            """
            @Shot
            struct LarderApp: App {
            }
            """,
            into: """
            struct LarderApp: App {
            }
            """,
            diagnostics: [
                DiagnosticSpec(message: "@Shot needs `var root: some View`: your app's root view, which it shows in a WindowGroup", line: 1, column: 1),
            ]
        )
    }

    @Test func onlyGoesOnAStruct() {
        expand(
            """
            @Shot
            final class LarderApp {
                var root: Int { 0 }
            }
            """,
            into: """
            final class LarderApp {
                var root: Int { 0 }
            }
            """,
            diagnostics: [DiagnosticSpec(message: "@Shot goes on your app's App struct", line: 1, column: 1)]
        )
    }

    private func expand(
        _ source: String, into expanded: String, diagnostics: [DiagnosticSpec] = [],
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        assertMacroExpansion(
            source, expandedSource: expanded, diagnostics: diagnostics,
            macroSpecs: ["Shot": MacroSpec(type: ShotMacro.self)],
            failureHandler: { Issue.record(Comment(rawValue: $0.message), sourceLocation: sourceLocation) }
        )
    }
}
