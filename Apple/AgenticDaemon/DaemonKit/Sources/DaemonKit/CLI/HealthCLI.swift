import Foundation

/// CLI extension that adds a `health` command.
///
/// Reads `GET /health` and prints status, version, uptime, and the strategy
/// snapshot's work unit count.
public struct HealthCLI: DaemonCLIExtension {
    public init() {}

    public var commands: [CLICommand] {
        [
            CLICommand(
                name: "health",
                description: "Show daemon status and uptime"
            ) { _, ctx in
                guard let status: HealthStatus = ctx.http.get("/health", as: HealthStatus.self) else {
                    ctx.stderr.write("error: daemon unreachable at \(ctx.http.baseURL)\n")
                    return 1
                }
                ctx.stdout.write("status:   \(status.status)\n")
                ctx.stdout.write("version:  \(status.version)\n")
                ctx.stdout.write("uptime:   \(formatDuration(status.uptimeSeconds))\n")
                ctx.stdout.write("strategy: \(status.strategy.kind) \"\(status.strategy.name)\" (\(status.strategy.workUnits.count) unit\(status.strategy.workUnits.count == 1 ? "" : "s"))\n")
                if !status.strategy.children.isEmpty {
                    for child in status.strategy.children {
                        ctx.stdout.write("  ├─ \(child.kind) \"\(child.name)\" (\(child.workUnits.count) unit\(child.workUnits.count == 1 ? "" : "s"))\n")
                    }
                }
                return 0
            }
        ]
    }
}

