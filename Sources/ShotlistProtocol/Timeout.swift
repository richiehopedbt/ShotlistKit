#if DEBUG || !os(iOS)
import Foundation
import os

public struct TimeoutError: Error, CustomStringConvertible {
    public let seconds: Double
    public let what: String

    public init(seconds: Double, what: String) {
        self.seconds = seconds
        self.what = what
    }

    public var description: String { "timed out after \(Self.format(seconds)) waiting for \(what)" }

    private static func format(_ seconds: Double) -> String {
        seconds == seconds.rounded() ? "\(Int(seconds)) s" : String(format: "%.1f s", seconds)
    }
}

/// Runs `operation` with a deadline. The operation must honour cancellation, because the task
/// group can't return until its child does. Use `withDeadline` for code that might not.
public func withTimeout<T: Sendable>(
    _ seconds: Double,
    _ what: String,
    _ operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await operation() }
        group.addTask {
            try await Task.sleep(for: .seconds(seconds))
            throw TimeoutError(seconds: seconds, what: what)
        }
        defer { group.cancelAll() }
        guard let result = try await group.next() else {
            throw TimeoutError(seconds: seconds, what: what)
        }
        return result
    }
}

/// Races `operation` against a deadline and returns as soon as either finishes, cancelling but
/// not waiting for the loser. For work that may ignore cancellation, such as a scene's own code.
public func withDeadline<T: Sendable>(
    _ seconds: Double,
    _ what: String,
    _ operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    let claimed = OSAllocatedUnfairLock(initialState: false)
    let claim: @Sendable () -> Bool = {
        claimed.withLock { taken in
            if taken { return false }
            taken = true
            return true
        }
    }
    return try await withCheckedThrowingContinuation { continuation in
        let work = Task {
            do {
                let value = try await operation()
                if claim() { continuation.resume(returning: value) }
            } catch {
                if claim() { continuation.resume(throwing: error) }
            }
        }
        Task {
            try? await Task.sleep(for: .seconds(seconds))
            if claim() {
                work.cancel()
                continuation.resume(throwing: TimeoutError(seconds: seconds, what: what))
            }
        }
    }
}
#endif
