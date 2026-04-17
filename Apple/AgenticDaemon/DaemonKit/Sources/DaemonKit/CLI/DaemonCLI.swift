import Foundation

/// A single CLI subcommand.
///
/// Keep commands small and stateless — they receive a ``CLIContext`` with the
/// daemon connection handles they need. Return an integer exit code (0 ok).
public struct CLICommand: Sendable {
    /// Command name as typed on the command line, e.g. `"jobs"`.
    public let name: String
    /// One-line description shown in `--help`.
    public let description: String
    /// The command body. `args` excludes the command name itself.
    public let run: @Sendable (_ args: [String], _ context: CLIContext) async throws -> Int32

    public init(
        name: String,
        description: String,
        run: @escaping @Sendable (_ args: [String], _ context: CLIContext) async throws -> Int32
    ) {
        self.name = name
        self.description = description
        self.run = run
    }
}

/// Runtime context passed to every ``CLICommand``.
public struct CLIContext: Sendable {
    public let http: DaemonHTTPClient
    public let xpc: DaemonConnection?
    public let stdout: CLIWriter
    public let stderr: CLIWriter

    public init(
        http: DaemonHTTPClient,
        xpc: DaemonConnection? = nil,
        stdout: CLIWriter = .standardOutput,
        stderr: CLIWriter = .standardError
    ) {
        self.http = http
        self.xpc = xpc
        self.stdout = stdout
        self.stderr = stderr
    }
}

/// Bundle of commands a strategy (or any client) contributes to a ``DaemonCLI``.
///
/// A conforming type returns its commands; the CLI dispatcher merges them
/// with other extensions. Name collisions are resolved in declaration order
/// (earlier extensions win).
public protocol DaemonCLIExtension: Sendable {
    var commands: [CLICommand] { get }
}

/// Composes CLI extensions into a single command-line interface.
///
///     let cli = DaemonCLI(
///         programName: "agenticctl",
///         extensions: [HealthCLI(), TimingStrategyCLI()],
///         additional: []
///     )
///     exit(await cli.run(CommandLine.arguments))
///
/// Built-in behavior: `--help` / `-h` prints usage and exits 0; unknown
/// commands print a suggestion and exit 2.
public struct DaemonCLI: Sendable {
    public let programName: String
    public let commands: [CLICommand]
    public let contextProvider: @Sendable () -> CLIContext

    public init(
        programName: String,
        extensions: [any DaemonCLIExtension] = [],
        additional: [CLICommand] = [],
        contextProvider: @escaping @Sendable () -> CLIContext
    ) {
        self.programName = programName
        var merged: [String: CLICommand] = [:]
        for ext in extensions {
            for cmd in ext.commands where merged[cmd.name] == nil {
                merged[cmd.name] = cmd
            }
        }
        for cmd in additional where merged[cmd.name] == nil {
            merged[cmd.name] = cmd
        }
        self.commands = merged.values.sorted { $0.name < $1.name }
        self.contextProvider = contextProvider
    }

    /// Entry point. `argv` includes the program name at index 0 (matching
    /// `CommandLine.arguments`).
    public func run(_ argv: [String]) async -> Int32 {
        let ctx = contextProvider()
        let args = Array(argv.dropFirst())
        guard let first = args.first else {
            printUsage(to: ctx.stderr)
            return 2
        }
        if first == "--help" || first == "-h" || first == "help" {
            printUsage(to: ctx.stdout)
            return 0
        }
        guard let cmd = commands.first(where: { $0.name == first }) else {
            ctx.stderr.write("error: unknown command \"\(first)\"\n")
            printUsage(to: ctx.stderr)
            return 2
        }
        do {
            return try await cmd.run(Array(args.dropFirst()), ctx)
        } catch {
            ctx.stderr.write("error: \(error)\n")
            return 1
        }
    }

    public func printUsage(to writer: CLIWriter) {
        writer.write("Usage: \(programName) <command> [args…]\n\n")
        writer.write("Commands:\n")
        let width = (commands.map(\.name.count).max() ?? 0) + 2
        for cmd in commands {
            let padded = cmd.name.padding(toLength: width, withPad: " ", startingAt: 0)
            writer.write("  \(padded)\(cmd.description)\n")
        }
    }
}

/// Abstraction over a write destination so tests can capture CLI output.
public struct CLIWriter: Sendable {
    private let writeImpl: @Sendable (String) -> Void

    public init(write: @escaping @Sendable (String) -> Void) {
        self.writeImpl = write
    }

    public func write(_ string: String) {
        writeImpl(string)
    }

    public static let standardOutput = CLIWriter { s in
        FileHandle.standardOutput.write(Data(s.utf8))
    }

    public static let standardError = CLIWriter { s in
        FileHandle.standardError.write(Data(s.utf8))
    }
}
