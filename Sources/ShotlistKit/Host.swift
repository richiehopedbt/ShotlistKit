#if DEBUG && canImport(UIKit)
import Observation
import SwiftUI
import UIKit

/// The SwiftUI host. Use it as the window's content when `Shotlist.isActive`; the trailing
/// closure is the app's normal root, which link scenes start from.
///
/// ```swift
/// WindowGroup {
///     #if DEBUG
///     if Shotlist.isActive { ShotlistHost(scenes: Screenshots.scenes) { RootView() } } else { RootView() }
///     #else
///     RootView()
///     #endif
/// }
/// ```
public struct ShotlistHost<Root: View>: View {
    private let root: (ShotlistContext?) -> Root
    private let runtime = ShotlistRuntime.shared

    public init(scenes: [any ShotlistScene], @ViewBuilder root: @escaping () -> Root) {
        self.root = { _ in root() }
        ShotlistRuntime.shared.configure(scenes: scenes)
    }

    /// The root receives the link scene's context (nil before the first scene), so it can use
    /// `context.now`, pin dependencies (`withDependencies { context.pin(&$0) }`) or seed a store.
    public init(scenes: [any ShotlistScene], @ViewBuilder root: @escaping (ShotlistContext?) -> Root) {
        self.root = root
        ShotlistRuntime.shared.configure(scenes: scenes)
    }

    public var body: some View {
        presentedContent
            .transaction { transaction in
                transaction.animation = nil
                transaction.disablesAnimations = true
            }
            .scrollIndicators(.hidden)
            .shotlistImageSession()
            .task { runtime.start() }
    }

    @ViewBuilder
    private var presentedContent: some View {
        switch runtime.presented {
        // onAppear sits inside .id(), so each new scene is a new view whose appearance fires.
        case .root(let id):
            root(runtime.rootContext)
                .onAppear { runtime.didAppear(id) }
                .id(id)
        case .swiftUI(let view, let id):
            view
                .onAppear { runtime.didAppear(id) }
                .id(id)
        case .uiKit(let controller, let id):
            ControllerView(controller: controller)
                .ignoresSafeArea()
                .onAppear { runtime.didAppear(id) }
                .id(id)
        }
    }
}

private struct ControllerView: UIViewControllerRepresentable {
    let controller: UIViewController

    func makeUIViewController(context: Context) -> UIViewController { controller }
    func updateUIViewController(_ controller: UIViewController, context: Context) {}
}

/// The UIKit host behind `Shotlist.hostingController`. Swaps its single child as scenes change.
final class ShotlistContainerController: UIViewController {
    private let runtime: ShotlistRuntime
    private let makeRoot: @MainActor (ShotlistContext?) -> UIViewController
    private var rootController: UIViewController?
    private var child: UIViewController?
    private var appliedID = -1

    init(runtime: ShotlistRuntime, makeRoot: @escaping @MainActor (ShotlistContext?) -> UIViewController) {
        self.runtime = runtime
        self.makeRoot = makeRoot
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func viewDidLoad() {
        super.viewDidLoad()
        observe()
        runtime.start()
    }

    private func observe() {
        withObservationTracking {
            apply(runtime.presented)
        } onChange: { [weak self] in
            Task { @MainActor in self?.observe() }
        }
    }

    private func apply(_ presented: ShotlistRuntime.Presented) {
        let next: UIViewController
        let id: Int
        switch presented {
        case .root(let rootID):
            // A fresh root per link scene, so each starts from the app's launch state.
            if rootID != appliedID || rootController == nil { rootController = makeRoot(runtime.rootContext) }
            next = rootController!
            id = rootID
        case .uiKit(let controller, let controllerID):
            next = controller
            id = controllerID
        case .swiftUI(let view, let viewID):
            next = UIHostingController(rootView: view.shotlistImageSession())
            id = viewID
        }
        guard id != appliedID else { return }
        appliedID = id
        if let child {
            child.willMove(toParent: nil)
            child.view.removeFromSuperview()
            child.removeFromParent()
        }
        addChild(next)
        next.view.frame = view.bounds
        next.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(next.view)
        next.didMove(toParent: self)
        child = next
        view.layoutIfNeeded()
        runtime.didAppear(id)
    }
}

extension View {
    /// iOS 27's AsyncImage loads through SwiftUI's own loader rather than `URLSession.shared`;
    /// this routes it through the fixtures. Earlier systems use the shared session.
    @ViewBuilder
    func shotlistImageSession() -> some View {
        if #available(iOS 27, *) {
            asyncImageURLSession(ShotlistURLProtocol.asyncImageSession)
        } else {
            self
        }
    }
}
#endif
