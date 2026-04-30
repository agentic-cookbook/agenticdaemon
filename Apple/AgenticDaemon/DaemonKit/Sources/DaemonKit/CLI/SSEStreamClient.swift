import Foundation
import Network

/// A single parsed Server-Sent Events message.
public struct SSEMessage: Sendable, Equatable {
    public let eventType: String?
    public let data: String
    public let id: String?

    public init(eventType: String? = nil, data: String, id: String? = nil) {
        self.eventType = eventType
        self.data = data
        self.id = id
    }
}

/// Client that opens an HTTP connection, issues GET on an SSE path, and
/// yields parsed messages as they arrive.
///
/// CLIs use this to implement `stream`/`tail` commands. The caller owns the
/// lifetime — cancel the returned task to stop receiving.
///
///     let client = SSEStreamClient(host: "127.0.0.1", port: 8080)
///     for await msg in try await client.connect(path: "/events/stream") {
///         print(msg.eventType ?? "", msg.data)
///     }
public final class SSEStreamClient: @unchecked Sendable {
    public let host: String
    public let port: UInt16

    public init(host: String = "127.0.0.1", port: UInt16) {
        self.host = host
        self.port = port
    }

    /// Open the stream. Returns an `AsyncStream` of parsed ``SSEMessage``.
    /// Canceling the enclosing task closes the connection.
    public func connect(path: String) async throws -> AsyncStream<SSEMessage> {
        let endpointHost: NWEndpoint.Host = (host == "127.0.0.1")
            ? .ipv4(.loopback)
            : .init(host)
        let connection = NWConnection(
            host: endpointHost,
            port: NWEndpoint.Port(rawValue: port)!,
            using: .tcp
        )

        return AsyncStream { continuation in
            let parser = SSEParser()

            connection.stateUpdateHandler = { [weak connection] state in
                switch state {
                case .ready:
                    // Send the GET request
                    let req = "GET \(path) HTTP/1.1\r\nHost: \(self.host):\(self.port)\r\n"
                        + "Accept: text/event-stream\r\n\r\n"
                    connection?.send(content: Data(req.utf8), completion: .contentProcessed { _ in })
                    Self.receiveLoop(connection: connection, parser: parser, continuation: continuation)
                case .failed, .cancelled:
                    continuation.finish()
                default: break
                }
            }

            continuation.onTermination = { _ in
                connection.cancel()
            }

            connection.start(queue: .global(qos: .utility))
        }
    }

    private static func receiveLoop(
        connection: NWConnection?,
        parser: SSEParser,
        continuation: AsyncStream<SSEMessage>.Continuation
    ) {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, isComplete, error in
            if let data, !data.isEmpty {
                for msg in parser.feed(data) {
                    continuation.yield(msg)
                }
            }
            if isComplete || error != nil {
                continuation.finish()
                return
            }
            receiveLoop(connection: connection, parser: parser, continuation: continuation)
        }
    }
}

/// Incremental parser for Server-Sent Events. Holds a buffer across reads
/// and emits complete messages (terminated by blank line) as it sees them.
final class SSEParser: @unchecked Sendable {
    private var buffer = Data()
    private var sawHeaders = false

    func feed(_ data: Data) -> [SSEMessage] {
        buffer.append(data)
        var messages: [SSEMessage] = []

        if !sawHeaders {
            // Look for \r\n\r\n terminator ending the HTTP response headers
            if let headerEnd = buffer.range(of: Data("\r\n\r\n".utf8)) {
                sawHeaders = true
                buffer.removeSubrange(buffer.startIndex..<headerEnd.upperBound)
            } else {
                return []
            }
        }

        // Messages are separated by blank lines — i.e. "\n\n"
        while let separator = buffer.range(of: Data("\n\n".utf8)) {
            let messageData = buffer.subdata(in: buffer.startIndex..<separator.lowerBound)
            buffer.removeSubrange(buffer.startIndex..<separator.upperBound)
            if let msg = Self.parseMessage(messageData) {
                messages.append(msg)
            }
        }
        return messages
    }

    private static func parseMessage(_ data: Data) -> SSEMessage? {
        guard let text = String(data: data, encoding: .utf8), !text.isEmpty else { return nil }
        var eventType: String?
        var dataLines: [String] = []
        var id: String?
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let str = String(line)
            if str.hasPrefix(":") || str.isEmpty { continue }  // comment or blank
            if let colon = str.firstIndex(of: ":") {
                let field = String(str[..<colon])
                var value = String(str[str.index(after: colon)...])
                if value.hasPrefix(" ") { value.removeFirst() }
                switch field {
                case "event": eventType = value
                case "data":  dataLines.append(value)
                case "id":    id = value
                default: break
                }
            } else {
                // Field with no colon — the whole line is the field name
                // and value is empty. Ignored.
            }
        }
        guard !dataLines.isEmpty else { return nil }
        return SSEMessage(eventType: eventType, data: dataLines.joined(separator: "\n"), id: id)
    }
}
