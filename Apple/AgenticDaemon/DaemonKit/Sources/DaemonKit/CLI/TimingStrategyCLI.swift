import Foundation

/// CLI extension that adds `jobs` and `job <name>` commands.
///
/// Reads from the standardized TimingStrategy HTTP surface (PR 3):
/// `GET /jobs` and `GET /jobs/{name}` returning ``TimingJobSummary``.
public struct TimingStrategyCLI: DaemonCLIExtension {
    public init() {}

    public var commands: [CLICommand] {
        [
            CLICommand(
                name: "jobs",
                description: "List scheduled jobs"
            ) { _, ctx in
                guard let summaries = ctx.http.get("/jobs", as: [TimingJobSummary].self) else {
                    ctx.stderr.write("error: could not fetch /jobs\n")
                    return 1
                }
                if summaries.isEmpty {
                    ctx.stdout.write("(no scheduled jobs)\n")
                    return 0
                }
                let nameWidth = (summaries.map(\.name.count).max() ?? 0) + 2
                let stateWidth = (summaries.map(\.state.count).max() ?? 0) + 2
                ctx.stdout.write("\(padRight("NAME", nameWidth))\(padRight("STATE", stateWidth))FAILURES  NEXT\n")
                for s in summaries {
                    let next = s.nextActivation.map { formatTimestamp($0) } ?? "-"
                    ctx.stdout.write("\(padRight(s.name, nameWidth))\(padRight(s.state, stateWidth))\(padRight(String(s.consecutiveFailures), 10))\(next)\n")
                }
                return 0
            },
            CLICommand(
                name: "job",
                description: "Show a single scheduled job's details (usage: job <name>)"
            ) { args, ctx in
                guard let name = args.first else {
                    ctx.stderr.write("usage: job <name>\n")
                    return 2
                }
                guard let summary = ctx.http.get("/jobs/\(name)", as: TimingJobSummary.self) else {
                    ctx.stderr.write("error: job \"\(name)\" not found\n")
                    return 1
                }
                ctx.stdout.write("name:                 \(summary.name)\n")
                ctx.stdout.write("state:                \(summary.state)\n")
                ctx.stdout.write("consecutive_failures: \(summary.consecutiveFailures)\n")
                ctx.stdout.write("is_blacklisted:       \(summary.isBlacklisted)\n")
                if let next = summary.nextActivation {
                    ctx.stdout.write("next_activation:      \(formatTimestamp(next))\n")
                }
                return 0
            }
        ]
    }
}
