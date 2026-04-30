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
                let unitCount = status.strategy.workUnits.count
                let unitSuffix = unitCount == 1 ? "" : "s"
                ctx.stdout.write(
                    "strategy: \(status.strategy.kind) \"\(status.strategy.name)\" "
                    + "(\(unitCount) unit\(unitSuffix))\n"
                )
                if !status.strategy.children.isEmpty {
                    for child in status.strategy.children {
                        let childUnits = child.workUnits.count
                        let childSuffix = childUnits == 1 ? "" : "s"
                        ctx.stdout.write(
                            "  ├─ \(child.kind) \"\(child.name)\" "
                            + "(\(childUnits) unit\(childSuffix))\n"
                        )
                    }
                }
                return 0
            }
        ]
    }
}
