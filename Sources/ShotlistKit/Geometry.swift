#if DEBUG && canImport(UIKit)
import UIKit

/// Tells the engine which screen the app is on, so a Duo unfold is seen from inside the app
/// (about 0.1 s) instead of by polling a black framebuffer.
@MainActor
final class SceneGeometryReporter {
    private var observation: NSKeyValueObservation?
    private var last: ScreenInfo?
    private var send: (@MainActor (ScreenInfo) -> Void)?

    func start(send: @escaping @MainActor (ScreenInfo) -> Void) {
        guard self.send == nil else { return }
        self.send = send
        guard let scene = currentScene else { return }
        report(scene)
        // The window scene's geometry changes as soon as the Duo folds or unfolds (Phase 0:
        // 0.12 s after Device Hub's Open), so this one observation is enough.
        observation = scene.observe(\.effectiveGeometry, options: [.new]) { [weak self] scene, _ in
            MainActor.assumeIsolated { self?.report(scene) }
        }
    }

    private var currentScene: UIWindowScene? {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
    }

    private func report(_ scene: UIWindowScene) {
        let bounds = scene.screen.nativeBounds
        let info = ScreenInfo(width: Int(bounds.width), height: Int(bounds.height), orientation: scene.effectiveGeometry.interfaceOrientation.rawValue)
        guard info != last else { return }
        last = info
        send?(info)
    }
}
#endif
