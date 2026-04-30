import Foundation

/// CLI extension that adds a `stream` command for tailing SSE events.
///
/// Opens `/events/stream` on the daemon and prints each SSE message as
/// received. Accepts `--filter key=value` flags which become query params
/// on the stream URL (the daemon's SSE handler decides whether to respect
/// them — stenographer uses `session_id`, for example).
public struct EventStrategyCLI: DaemonCLIExtension {
    public let streamPath: String

    public init(streamPath: String = "/events/stream") {
        self.streamPath = streamPath
    }

    public var commands: [CLICommand] {
        let path = streamPath
        return [
            CLICommand(
                name: "stream",
                description: "Tail the SSE event stream (optional: --filter key=value)"
            ) { args, ctx in
                let (host, port) = Self.parseBaseURL(ctx.http.baseURL) ?? ("127.0.0.1", 0)
                guard port != 0 else {
                    ctx.stderr.write("error: could not parse daemon URL \"\(ctx.http.baseURL)\"\n")
                    return 1
                }
                let filters = Self.parseFilters(args)
                let fullPath = filters.isEmpty ? path : path + "?" + Self.encodeQuery(filters)

                let client = SSEStreamClient(host: host, port: port)
                do {
                    let stream = try await client.connect(path: fullPath)
                    for await msg in stream {
                        let type = msg.eventType ?? "message"
                        ctx.stdout.write("[\(type)] \(msg.data)\n")
                    }
                    return 0
                } catch {
                    ctx.stderr.write("error: \(error)\n")
                    return 1
                }
            }
        ]
    }

    static func parseBaseURL(_ url: String) -> (String, UInt16)? {
        guard let comps = URLComponents(string: url),
              let host = comps.host,
              let port = comps.port else { return nil }
        return (host, UInt16(port))
    }

    static func parseFilters(_ args: [String]) -> [String: String] {
        var filters: [String: String] = [:]
        var index = 0
        while index < args.count {
            if args[index] == "--filter", index + 1 < args.count {
                let pair = args[index + 1]
                if let equalsIndex = pair.firstIndex(of: "=") {
                    let key = String(pair[..<equalsIndex])
                    let value = String(pair[pair.index(after: equalsIndex)...])
                    filters[key] = value
                }
                index += 2
            } else {
                index += 1
            }
        }
        return filters
    }

    static func encodeQuery(_ items: [String: String]) -> String {
        items.sorted(by: { $0.key < $1.key }).map { key, value in
            let encodedKey = key.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? key
            let encodedValue = value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
            return "\(encodedKey)=\(encodedValue)"
        }.joined(separator: "&")
    }
}
