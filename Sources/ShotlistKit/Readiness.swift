#if DEBUG && canImport(UIKit)
import Foundation
import os
import QuartzCore
import UIKit

/// What a scene is still waiting on. Thread-safe: the fixture protocol updates it from
/// URLSession's protocol thread, the runtime reads it on the main actor.
final class Readiness: Sendable {
    struct State: Sendable {
        var holds: [UUID: String] = [:]
        var requests: [String: String] = [:]
        var unmatched: [String] = []
        /// Bumps on every change, so a check spanning frames can tell whether anything happened.
        var generation = 0
    }

    static let shared = Readiness()
    private let state = OSAllocatedUnfairLock(initialState: State())

    var snapshot: State { state.withLock { $0 } }

    func beginHold(_ label: String) -> UUID {
        let id = UUID()
        state.withLock { $0.holds[id] = label; $0.generation += 1 }
        return id
    }

    func endHold(_ id: UUID) {
        state.withLock { $0.holds[id] = nil; $0.generation += 1 }
    }

    func beginRequest(_ id: String, _ description: String) {
        state.withLock { $0.requests[id] = description; $0.generation += 1 }
    }

    func endRequest(_ id: String, unmatched: String? = nil) {
        state.withLock {
            $0.requests[id] = nil
            if let unmatched { $0.unmatched.append(unmatched) }
            $0.generation += 1
        }
    }

    /// Clears per-scene failures before the next scene.
    func resetUnmatched() {
        state.withLock { $0.unmatched = [] }
    }

    /// Plain words for a timeout: what is still open.
    func describeOpenWork() -> String {
        let current = snapshot
        var parts: [String] = []
        if !current.holds.isEmpty {
            parts.append("open hold" + (current.holds.count == 1 ? " " : "s ") + current.holds.values.sorted().map { "'\($0)'" }.joined(separator: ", "))
        }
        if !current.requests.isEmpty {
            parts.append("pending " + current.requests.values.sorted().joined(separator: ", "))
        }
        return parts.isEmpty ? "nothing open (the scene never appeared)" : parts.joined(separator: "; ")
    }
}

/// Readiness step 3: rendered frames.
@MainActor
enum Frames {
    static func wait(_ count: Int) async {
        await withCheckedContinuation { continuation in
            let counter = FrameCounter(remaining: count, continuation: continuation)
            let link = CADisplayLink(target: counter, selector: #selector(FrameCounter.tick(_:)))
            link.add(to: .main, forMode: .common)
        }
    }
}

@MainActor
private final class FrameCounter: NSObject {
    private var remaining: Int
    private let continuation: CheckedContinuation<Void, Never>

    init(remaining: Int, continuation: CheckedContinuation<Void, Never>) {
        self.remaining = remaining
        self.continuation = continuation
    }

    @objc func tick(_ link: CADisplayLink) {
        remaining -= 1
        if remaining <= 0 {
            link.invalidate()
            continuation.resume()
        }
    }
}
#endif
