import Testing
import Foundation
@testable import DaemonKit

// MARK: - Test doubles

private final class CapturedOutput: @unchecked Sendable {
    private let lock = NSLock()
    private var _stdout: String = ""
    private var _stderr: String = ""

    var stdout: String { lock.withLock { _stdout } }
    var stderr: String { lock.withLock { _stderr } }

    func makeWriters() -> (CLIWriter, CLIWriter) {
        let out = CLIWriter { [weak self] text in
            guard let self else { return }
            self.lock.withLock { self._stdout += text }
        }
        let err = CLIWriter { [weak self] text in
            guard let self else { return }
            self.lock.withLock { self._stderr += text }
        }
        return (out, err)
    }
}

private struct TestExtension: DaemonCLIExtension {
    let commands: [CLICommand]
}

private func makeContext(
    output: CapturedOutput,
    http: DaemonHTTPClient = DaemonHTTPClient(baseURL: "http://127.0.0.1:1")
) -> CLIContext {
    let (out, err) = output.makeWriters()
    return CLIContext(http: http, xpc: nil, stdout: out, stderr: err)
}

// MARK: - Tests

@Suite("DaemonCLI dispatch", .serialized)
struct DaemonCLIDispatchTests {

    @Test("runs known command")
    func runsKnownCommand() async {
        let captured = CapturedOutput()
        let invoked = LockIsolatedInt()
        let cli = DaemonCLI(
            programName: "test",
            extensions: [TestExtension(commands: [
                CLICommand(name: "ping", description: "ping") { _, ctx in
                    invoked.increment()
                    ctx.stdout.write("pong\n")
                    return 0
                }
            ])],
            contextProvider: { makeContext(output: captured) }
        )
        let code = await cli.run(["prog", "ping"])
        #expect(code == 0)
        #expect(invoked.value == 1)
        #expect(captured.stdout == "pong\n")
    }

    @Test("unknown command returns exit 2 and prints usage")
    func unknownCommand() async {
        let captured = CapturedOutput()
        let cli = DaemonCLI(
            programName: "test",
            extensions: [TestExtension(commands: [])],
            contextProvider: { makeContext(output: captured) }
        )
        let code = await cli.run(["prog", "bogus"])
        #expect(code == 2)
        #expect(captured.stderr.contains("unknown command \"bogus\""))
    }

    @Test("no command returns exit 2 and prints usage")
    func noCommand() async {
        let captured = CapturedOutput()
        let cli = DaemonCLI(
            programName: "test",
            extensions: [],
            contextProvider: { makeContext(output: captured) }
        )
        let code = await cli.run(["prog"])
        #expect(code == 2)
    }

    @Test("--help prints usage and returns 0")
    func helpReturnsZero() async {
        let captured = CapturedOutput()
        let cli = DaemonCLI(
            programName: "test",
            extensions: [TestExtension(commands: [
                CLICommand(name: "ping", description: "ping") { _, _ in 0 }
            ])],
            contextProvider: { makeContext(output: captured) }
        )
        let code = await cli.run(["prog", "--help"])
        #expect(code == 0)
        #expect(captured.stdout.contains("Usage: test"))
        #expect(captured.stdout.contains("ping"))
    }

    @Test("command errors propagate as exit 1")
    func commandErrorExits1() async {
        let captured = CapturedOutput()
        let cli = DaemonCLI(
            programName: "test",
            extensions: [TestExtension(commands: [
                CLICommand(name: "boom", description: "d") { _, _ in
                    throw NSError(domain: "x", code: 7)
                }
            ])],
            contextProvider: { makeContext(output: captured) }
        )
        let code = await cli.run(["prog", "boom"])
        #expect(code == 1)
        #expect(captured.stderr.contains("error:"))
    }

    @Test("extensions merge; first registration wins on name collision")
    func extensionMerge() async {
        let captured = CapturedOutput()
        let cli = DaemonCLI(
            programName: "test",
            extensions: [
                TestExtension(commands: [
                    CLICommand(name: "ping", description: "first") { _, ctx in
                        ctx.stdout.write("first\n")
                        return 0
                    }
                ]),
                TestExtension(commands: [
                    CLICommand(name: "ping", description: "second") { _, ctx in
                        ctx.stdout.write("second\n")
                        return 0
                    }
                ])
            ],
            contextProvider: { makeContext(output: captured) }
        )
        let code = await cli.run(["prog", "ping"])
        #expect(code == 0)
        #expect(captured.stdout == "first\n")
    }
}

// MARK: - EventStrategyCLI helpers

@Suite("EventStrategyCLI helpers")
struct EventStrategyCLIHelperTests {

    @Test("parseBaseURL extracts host and port")
    func parseBaseURL() {
        let parsed = EventStrategyCLI.parseBaseURL("http://127.0.0.1:22847")
        #expect(parsed?.0 == "127.0.0.1")
        #expect(parsed?.1 == 22847)
    }

    @Test("parseBaseURL returns nil for invalid URL")
    func parseBaseURLInvalid() {
        #expect(EventStrategyCLI.parseBaseURL("not-a-url") == nil)
    }

    @Test("parseFilters extracts key=value pairs from --filter flags")
    func parseFilters() {
        let args = ["--filter", "session_id=abc", "--filter", "scope=b"]
        let filters = EventStrategyCLI.parseFilters(args)
        #expect(filters["session_id"] == "abc")
        #expect(filters["scope"] == "b")
    }

    @Test("parseFilters ignores flags without values")
    func parseFiltersIgnoresMalformed() {
        let args = ["--filter", "no_equals_here"]
        let filters = EventStrategyCLI.parseFilters(args)
        #expect(filters.isEmpty)
    }

    @Test("encodeQuery sorts keys for stable output")
    func encodeQuerySorted() {
        let encoded = EventStrategyCLI.encodeQuery(["scope": "b", "session_id": "abc"])
        #expect(encoded == "scope=b&session_id=abc")
    }

    @Test("encodeQuery percent-escapes special characters")
    func encodeQueryPercentEscapes() {
        let encoded = EventStrategyCLI.encodeQuery(["filter": "has space"])
        #expect(encoded.contains("has%20space") || encoded.contains("has+space"))
    }
}

// MARK: - SSE parser

@Suite("SSEParser")
struct SSEParserTests {

    @Test("skips HTTP response headers before parsing events")
    func skipsHeaders() {
        let parser = SSEParser()
        let httpResp = Data("HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\n\r\n".utf8)
        var msgs = parser.feed(httpResp)
        #expect(msgs.isEmpty)

        let event = Data("event: greeting\ndata: hello\n\n".utf8)
        msgs = parser.feed(event)
        #expect(msgs.count == 1)
        #expect(msgs[0].eventType == "greeting")
        #expect(msgs[0].data == "hello")
    }

    @Test("handles multi-line data")
    func multiLineData() {
        let parser = SSEParser()
        let headers = Data("HTTP/1.1 200 OK\r\n\r\n".utf8)
        _ = parser.feed(headers)

        let event = Data("data: line1\ndata: line2\n\n".utf8)
        let msgs = parser.feed(event)
        #expect(msgs.count == 1)
        #expect(msgs[0].data == "line1\nline2")
        #expect(msgs[0].eventType == nil)
    }

    @Test("parses id field")
    func parsesId() {
        let parser = SSEParser()
        _ = parser.feed(Data("HTTP/1.1 200 OK\r\n\r\n".utf8))
        let msgs = parser.feed(Data("id: 42\nevent: tick\ndata: {}\n\n".utf8))
        #expect(msgs.count == 1)
        #expect(msgs[0].id == "42")
        #expect(msgs[0].eventType == "tick")
    }

    @Test("handles messages split across multiple feeds")
    func splitAcrossFeeds() {
        let parser = SSEParser()
        _ = parser.feed(Data("HTTP/1.1 200 OK\r\n\r\n".utf8))

        let partial1 = Data("event: tick\ndata: one".utf8)
        var msgs = parser.feed(partial1)
        #expect(msgs.isEmpty)

        let partial2 = Data("\n\nevent: tock\ndata: two\n\n".utf8)
        msgs = parser.feed(partial2)
        #expect(msgs.count == 2)
        #expect(msgs[0].data == "one")
        #expect(msgs[1].data == "two")
    }

    @Test("ignores comment lines")
    func ignoresComments() {
        let parser = SSEParser()
        _ = parser.feed(Data("HTTP/1.1 200 OK\r\n\r\n".utf8))
        let msgs = parser.feed(Data(": keepalive\n\nevent: tick\ndata: {}\n\n".utf8))
        #expect(msgs.count == 1)
        #expect(msgs[0].eventType == "tick")
    }
}

// MARK: - End-to-end CLI against a real HTTPServer

@Suite("CLI end-to-end against live server", .serialized)
struct DaemonCLIEndToEndTests {

    @Test("health command renders status from GET /health")
    func healthCommandReadsServer() async throws {
        let strategy = TimingStrategy(name: "e2e", taskSource: StubCLITaskSource(tasks: []))
        let tmp = FileManager.default.temporaryDirectory.appending(path: "cli-e2e-\(UUID())")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let context = DaemonContext(
            crashTracker: CrashTracker(stateDir: tmp, subsystem: "cli.e2e"),
            analytics: RecordingAnalytics(),
            subsystem: "cli.e2e",
            supportDirectory: tmp
        )
        try await strategy.start(context: context)
        defer { Task { await strategy.stop() } }

        let router = DaemonHealthRouter(strategy: strategy, version: "test-1.0", startDate: Date())
        let server = HTTPServer(port: 0, router: router, subsystem: "cli.e2e")
        let port = try server.startAndWait()
        defer { server.stop() }

        let captured = CapturedOutput()
        let http = DaemonHTTPClient(baseURL: "http://127.0.0.1:\(port)")
        let cli = DaemonCLI(
            programName: "test",
            extensions: [HealthCLI(), TimingStrategyCLI()],
            contextProvider: {
                let (out, err) = captured.makeWriters()
                return CLIContext(http: http, stdout: out, stderr: err)
            }
        )
        let code = await cli.run(["test", "health"])
        #expect(code == 0)
        #expect(captured.stdout.contains("status:   ok"))
        #expect(captured.stdout.contains("version:  test-1.0"))
        #expect(captured.stdout.contains("strategy: timing \"e2e\""))
    }

    @Test("jobs command renders TimingJobSummary list")
    func jobsCommand() async throws {
        let strategy = TimingStrategy(taskSource: StubCLITaskSource(tasks: [
            StubCLITask(name: "alpha", schedule: .default),
            StubCLITask(name: "beta", schedule: .default)
        ]))
        let tmp = FileManager.default.temporaryDirectory.appending(path: "cli-jobs-\(UUID())")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let context = DaemonContext(
            crashTracker: CrashTracker(stateDir: tmp, subsystem: "cli.jobs"),
            analytics: RecordingAnalytics(),
            subsystem: "cli.jobs",
            supportDirectory: tmp
        )
        try await strategy.start(context: context)
        defer { Task { await strategy.stop() } }

        let router = DaemonHealthRouter(strategy: strategy, version: "1.0", startDate: Date())
        let server = HTTPServer(port: 0, router: router, subsystem: "cli.jobs")
        let port = try server.startAndWait()
        defer { server.stop() }

        let captured = CapturedOutput()
        let http = DaemonHTTPClient(baseURL: "http://127.0.0.1:\(port)")
        let cli = DaemonCLI(
            programName: "test",
            extensions: [TimingStrategyCLI()],
            contextProvider: {
                let (out, err) = captured.makeWriters()
                return CLIContext(http: http, stdout: out, stderr: err)
            }
        )
        let code = await cli.run(["test", "jobs"])
        #expect(code == 0)
        #expect(captured.stdout.contains("alpha"))
        #expect(captured.stdout.contains("beta"))
        #expect(captured.stdout.contains("NAME"))
        #expect(captured.stdout.contains("FAILURES"))
    }

    @Test("job <name> command renders single job detail")
    func jobDetailCommand() async throws {
        let strategy = TimingStrategy(taskSource: StubCLITaskSource(tasks: [
            StubCLITask(name: "specific", schedule: .default)
        ]))
        let tmp = FileManager.default.temporaryDirectory.appending(path: "cli-job-\(UUID())")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let context = DaemonContext(
            crashTracker: CrashTracker(stateDir: tmp, subsystem: "cli.job"),
            analytics: RecordingAnalytics(),
            subsystem: "cli.job",
            supportDirectory: tmp
        )
        try await strategy.start(context: context)
        defer { Task { await strategy.stop() } }

        let router = DaemonHealthRouter(strategy: strategy, version: "1.0", startDate: Date())
        let server = HTTPServer(port: 0, router: router, subsystem: "cli.job")
        let port = try server.startAndWait()
        defer { server.stop() }

        let captured = CapturedOutput()
        let http = DaemonHTTPClient(baseURL: "http://127.0.0.1:\(port)")
        let cli = DaemonCLI(
            programName: "test",
            extensions: [TimingStrategyCLI()],
            contextProvider: {
                let (out, err) = captured.makeWriters()
                return CLIContext(http: http, stdout: out, stderr: err)
            }
        )
        let code = await cli.run(["test", "job", "specific"])
        #expect(code == 0)
        #expect(captured.stdout.contains("name:"))
        #expect(captured.stdout.contains("specific"))
    }

    @Test("job without name returns usage error")
    func jobCommandRequiresName() async {
        let captured = CapturedOutput()
        let cli = DaemonCLI(
            programName: "test",
            extensions: [TimingStrategyCLI()],
            contextProvider: {
                let (out, err) = captured.makeWriters()
                return CLIContext(http: DaemonHTTPClient(baseURL: "http://127.0.0.1:1"), stdout: out, stderr: err)
            }
        )
        let code = await cli.run(["test", "job"])
        #expect(code == 2)
        #expect(captured.stderr.contains("usage: job <name>"))
    }
}

// MARK: - Test helpers

private struct StubCLITask: DaemonTask {
    let name: String
    let schedule: TaskSchedule
    func execute(context: TaskContext) async throws -> TaskResult { .empty }
}

private final class StubCLITaskSource: TaskSource, @unchecked Sendable {
    let tasks: [any DaemonTask]
    var watchDirectory: URL? { nil }
    init(tasks: [any DaemonTask]) { self.tasks = tasks }
    func discoverTasks() -> [any DaemonTask] { tasks }
    func shouldClearBlocklist(taskName: String) -> Bool { false }
}

private final class LockIsolatedInt: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: Int = 0
    var value: Int { lock.withLock { _value } }
    func increment() { lock.withLock { _value += 1 } }
}
