import SwiftCompilerPlugin
import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

/// `@Shot` on the app's `App` struct writes its `body`: one `WindowGroup` showing `root`, which
/// becomes the Shotlist host when the engine launches the app. Release builds show `root` alone.
///
/// A macro can add declarations but not replace one the app wrote, which is why the app writes
/// `root` and `@Shot` writes `body`. Link scenes start from `shotlistRoot` when the app has one
/// (a property, or a function taking the scene's `ShotlistContext?`), and from `root` otherwise.
public struct ShotMacro: MemberMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard declaration.is(StructDeclSyntax.self) else {
            context.diagnose(Diagnostic(node: node, message: ShotDiagnostic.notAStruct))
            return []
        }
        let members = Members(declaration.memberBlock.members)
        if let body = members.declaration(named: "body") {
            context.diagnose(Diagnostic(node: body, message: ShotDiagnostic.hasBody))
            return []
        }
        guard members.declaration(named: "root")?.is(VariableDeclSyntax.self) == true else {
            context.diagnose(Diagnostic(node: node, message: ShotDiagnostic.noRoot))
            return []
        }

        let hosted: ExprSyntax = switch members.declaration(named: "shotlistRoot") {
        case let function? where function.is(FunctionDeclSyntax.self):
            "ShotlistKit.ShotlistHost(scenes: Screenshots.scenes) { context in shotlistRoot(context) }"
        case _?:
            "ShotlistKit.ShotlistHost(scenes: Screenshots.scenes) { shotlistRoot }"
        case nil:
            "ShotlistKit.ShotlistHost(scenes: Screenshots.scenes) { root }"
        }
        let access = declaration.modifiers.contains { $0.name.tokenKind == .keyword(.public) } ? "public " : ""
        // The same condition every ShotlistKit symbol sits behind, so a Release build, or a Debug
        // build for a platform without UIKit, compiles `root` alone.
        return [
            """
            \(raw: access)var body: some Scene {
                WindowGroup {
                    #if DEBUG && canImport(UIKit)
                    if ShotlistKit.Shotlist.isActive {
                        \(hosted)
                    } else {
                        root
                    }
                    #else
                    root
                    #endif
                }
            }
            """,
        ]
    }
}

/// The struct's members by name, including those inside `#if` blocks (such as a `shotlistRoot`
/// inside `#if DEBUG`).
private struct Members {
    private var byName: [String: DeclSyntax] = [:]

    init(_ items: MemberBlockItemListSyntax) {
        add(items)
    }

    func declaration(named name: String) -> DeclSyntax? {
        byName[name]
    }

    private mutating func add(_ items: MemberBlockItemListSyntax) {
        for item in items {
            if let variable = item.decl.as(VariableDeclSyntax.self) {
                for binding in variable.bindings {
                    if let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text {
                        byName[name] = byName[name] ?? item.decl
                    }
                }
            } else if let function = item.decl.as(FunctionDeclSyntax.self) {
                byName[function.name.text] = byName[function.name.text] ?? item.decl
            } else if let ifConfig = item.decl.as(IfConfigDeclSyntax.self) {
                for clause in ifConfig.clauses {
                    if case .decls(let nested)? = clause.elements { add(nested) }
                }
            }
        }
    }
}

enum ShotDiagnostic: String, DiagnosticMessage {
    case notAStruct
    case hasBody
    case noRoot

    var message: String {
        switch self {
        case .notAStruct:
            "@Shot goes on your app's App struct"
        case .hasBody:
            "@Shot writes body itself: rename body to root, and make it your app's root view (what you'd put in its WindowGroup)"
        case .noRoot:
            "@Shot needs `var root: some View`: your app's root view, which it shows in a WindowGroup"
        }
    }

    var diagnosticID: MessageID { MessageID(domain: "ShotlistMacros", id: rawValue) }
    var severity: DiagnosticSeverity { .error }
}

@main
struct ShotlistMacroPlugin: CompilerPlugin {
    let providingMacros: [any Macro.Type] = [ShotMacro.self]
}
