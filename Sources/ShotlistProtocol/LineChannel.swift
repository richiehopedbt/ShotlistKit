// On iOS this module is compiled into the developer's app, so nothing survives a Release build.
#if DEBUG || !os(iOS)
import Foundation
import Network

public struct ChannelError: Error, CustomStringConvertible {
    public let description: String
    public init(_ description: String) { self.description = description }
}

/// Newline-delimited JSON over an `NWConnection`. Used by both ends of the control channel.
public final class LineChannel: Sendable {
    public let connection: NWConnection
    public let lines: AsyncThrowingStream<Data, Error>
    private let linesContinuation: AsyncThrowingStream<Data, Error>.Continuation
    private let states: AsyncStream<NWConnection.State>
    private let statesContinuation: AsyncStream<NWConnection.State>.Continuation
    private let queue = DispatchQueue(label: "shotlist.channel")

    public init(connection: NWConnection) {
        self.connection = connection
        (lines, linesContinuation) = AsyncThrowingStream.makeStream(of: Data.self)
        (states, statesContinuation) = AsyncStream.makeStream(of: NWConnection.State.self)
    }

    /// Starts the connection and returns once it is ready. Fails on `.waiting` (e.g. refused) or `.failed`.
    public func start() async throws {
        connection.stateUpdateHandler = { [linesContinuation, statesContinuation] state in
            statesContinuation.yield(state)
            switch state {
            case .failed(let error):
                linesContinuation.finish(throwing: error)
                statesContinuation.finish()
            case .cancelled:
                linesContinuation.finish()
                statesContinuation.finish()
            default:
                break
            }
        }
        connection.start(queue: queue)
        for await state in states {
            switch state {
            case .ready:
                receive(buffer: Data())
                return
            case .waiting(let error), .failed(let error):
                connection.cancel()
                throw ChannelError("connection not ready: \(error)")
            case .cancelled:
                throw ChannelError("connection cancelled before ready")
            default:
                continue
            }
        }
        throw ChannelError("connection ended before ready")
    }

    public func send<Message: Encodable>(_ message: Message) async throws {
        var data = try JSONEncoder().encode(message)
        data.append(0x0A)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            })
        }
    }

    /// Enqueues a message without waiting for it to be written. Messages posted from one
    /// thread go out in order.
    public func post<Message: Encodable>(_ message: Message) {
        guard var data = try? JSONEncoder().encode(message) else { return }
        data.append(0x0A)
        connection.send(content: data, completion: .idempotent)
    }

    public func close() {
        connection.cancel()
    }

    private func receive(buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1 << 20) { [self] content, _, isComplete, error in
            var buffer = buffer
            if let content { buffer.append(content) }
            while let newline = buffer.firstIndex(of: 0x0A) {
                linesContinuation.yield(Data(buffer[buffer.startIndex..<newline]))
                buffer.removeSubrange(buffer.startIndex...newline)
            }
            if let error {
                linesContinuation.finish(throwing: error)
            } else if isComplete {
                linesContinuation.finish()
            } else {
                receive(buffer: buffer)
            }
        }
    }
}
#endif
