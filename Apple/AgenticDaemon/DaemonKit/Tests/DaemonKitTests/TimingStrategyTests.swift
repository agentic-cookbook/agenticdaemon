import Testing
import Foundation
@testable import DaemonKit

// MARK: - Test doubles

private struct StubTask: DaemonTask {
    let name: String
    let schedule: TaskSchedule
    var executeBlock: @Sendable (TaskContext) async throws -> TaskResult = { _ in .empty }

    func execute(context: TaskContext) async throws -> TaskResult {
        try await executeBlock(context)
    }
}

private final class StubSource: TaskSource, @unchecked Sendable {
    private let lock = NSLock()
    private var _tasks: [any DaemonTask]
    private var _watchDirectory: URL?
    private var _shouldClearBlacklist: @Sendable (String) -> Bool

    init(
        tasks: [any DaemonTask] = [],
        watchDirectory: URL? = nil,
        shouldClearBlacklist: @escaping @Sendable (String) -> Bool = { _ in false }
    ) {
        self._tasks = tasks
        self._watchDirectory = watchDirectory
        self._shouldClearBlacklist = shouldClearBlacklist
    }

    func discoverTasks() -> [any DaemonTask] {
        lock.withLock { _tasks }
    }

    var watchDirectory: URL? {
        lock.withLock { _watchDirectory }
    }

    func shouldClearBlacklist(taskName: String) -> Bool {
        lock.withLock { _shouldClearBlacklist(taskName) }
    }

    /// Allow tests to mutate the discovered task list at runtime, then trigger
    /// a re-sync (via the directory watcher path, or by calling syncTasks()).
    func setTasks(_ tasks: [any DaemonTask]) {
        lock.withLock { _tasks = tasks }
    }
}

private func makeContext(in tmp: URL, subsystem: String = "timing.test") -> (DaemonContext, CrashTracker, RecordingAnalytics) {
    let tracker = CrashTracker(stateDir: tmp, subsystem: subsystem)
    let analytics = RecordingAnalytics()
    let context = DaemonContext(
        crashTracker: tracker,
        analytics: analytics,
        subsystem: subsystem,
        supportDirectory: tmp
    )
    return (context, tracker, analytics)
}

private func makeTempDir(prefix: String = "timing") -> URL {
    let url = FileManager.default.temporaryDirectory
        .appending(path: "\(prefix)-\(UUID().uuidString)")
    try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

// MARK: - Tests

@Suite("TimingStrategy lifecycle", .serialized)
struct TimingStrategyLifecycleTests {

    @Test("snapshot before start returns empty workUnits")
    func snapshotBeforeStartIsEmpty() async {
        let source = StubSource(tasks: [StubTask(name: "t", schedule: .default)])
        let strategy = TimingStrategy(taskSource: source)

        let snap = await strategy.snapshot()
        #expect(snap.name == "timing")
        #expect(snap.kind == "timing")
        #expect(snap.workUnits.isEmpty)
    }

    @Test("taskNames is empty before start")
    func taskNamesEmptyBeforeStart() async {
        let source = StubSource(tasks: [StubTask(name: "t", schedule: .default)])
        let strategy = TimingStrategy(taskSource: source)
        let names = await strategy.taskNames
        #expect(names.isEmpty)
    }

    @Test("start registers tasks from the source")
    func startRegistersTasks() async throws {
        let tmp = makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let source = StubSource(tasks: [
            StubTask(name: "a", schedule: .default),
            StubTask(name: "b", schedule: .default)
        ])
        let strategy = TimingStrategy(taskSource: source)
        let (ctx, _, _) = makeContext(in: tmp)

        try await strategy.start(context: ctx)
        defer { Task { await strategy.stop() } }

        let names = await strategy.taskNames
        #expect(names == ["a", "b"])
    }

    @Test("snapshot reflects task state after initial run settles to idle")
    func snapshotReflectsIdleStateAfterFirstRun() async throws {
        let tmp = makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        // Task that completes quickly and schedules itself far in the future,
        // so after one run we can observe a stable .idle state.
        let task = StubTask(name: "enabled", schedule: TaskSchedule(intervalSeconds: 3600)) { _ in
            TaskResult(nextRunSeconds: 3600)
        }
        let source = StubSource(tasks: [task])
        let strategy = TimingStrategy(taskSource: source, tickInterval: 0.05)
        let (ctx, _, _) = makeContext(in: tmp)

        try await strategy.start(context: ctx)
        defer { Task { await strategy.stop() } }

        // Poll until the first execution completes and state settles.
        var observed: WorkUnitSnapshot?
        for _ in 0..<60 {
            let snap = await strategy.snapshot()
            if let unit = snap.workUnits.first, unit.state == .idle {
                observed = unit
                break
            }
            try? await Task.sleep(for: .milliseconds(50))
        }
        let unit = try #require(observed, "task never settled to idle")
        #expect(unit.name == "enabled")
        #expect(unit.state == .idle)
        #expect(unit.isBlacklisted == false)
        #expect(unit.nextActivation != nil)
    }

    @Test("snapshot marks disabled tasks distinctly from idle")
    func snapshotMarksDisabledTasks() async throws {
        let tmp = makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        // Disabled tasks aren't scheduled (syncTasks skips them), so they
        // don't appear in the snapshot at all — verify the empty case.
        let task = StubTask(name: "off", schedule: TaskSchedule(enabled: false))
        let source = StubSource(tasks: [task])
        let strategy = TimingStrategy(taskSource: source, tickInterval: 0.05)
        let (ctx, _, _) = makeContext(in: tmp)

        try await strategy.start(context: ctx)
        defer { Task { await strategy.stop() } }

        let snap = await strategy.snapshot()
        #expect(snap.workUnits.isEmpty)
    }

    @Test("snapshot marks blacklisted tasks")
    func snapshotMarksBlacklistedTasks() async throws {
        let tmp = makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        // Blacklisted tasks are skipped by syncTasks unless shouldClearBlacklist
        // returns true. But snapshots reflect only what the scheduler holds —
        // so to observe .blacklisted we need the task to be scheduled AND
        // blacklisted, which can happen if blacklist is set after sync.
        let task = StubTask(name: "bl", schedule: TaskSchedule(intervalSeconds: 3600))
        let source = StubSource(tasks: [task])
        let strategy = TimingStrategy(taskSource: source, tickInterval: 0.05)
        let (ctx, tracker, _) = makeContext(in: tmp)

        try await strategy.start(context: ctx)
        defer { Task { await strategy.stop() } }

        tracker.blacklist(taskName: "bl")
        let snap = await strategy.snapshot()
        let unit = try #require(snap.workUnits.first)
        #expect(unit.state == .blacklisted)
        #expect(unit.isBlacklisted == true)
    }

    @Test("tick loop executes tasks without external ticking")
    func tickLoopRunsTasks() async throws {
        let tmp = makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let executed = LockIsolatedInt(0)
        let counter = executed
        let task = StubTask(name: "self-runner", schedule: TaskSchedule(intervalSeconds: 10)) { _ in
            counter.increment()
            return TaskResult(nextRunSeconds: 999)
        }
        let source = StubSource(tasks: [task])
        let strategy = TimingStrategy(taskSource: source, tickInterval: 0.05)
        let (ctx, _, _) = makeContext(in: tmp)

        try await strategy.start(context: ctx)

        // Poll rather than a single sleep so this doesn't flake under load.
        var attempts = 0
        while executed.value < 1 && attempts < 60 {
            try? await Task.sleep(for: .milliseconds(50))
            attempts += 1
        }

        await strategy.stop()

        #expect(executed.value >= 1)
    }

    @Test("stop halts further scheduling (tick loop exits)")
    func stopHaltsScheduling() async throws {
        let tmp = makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let executed = LockIsolatedInt(0)
        let counter = executed
        // Task immediately reschedules itself ~tick-interval later, so if the
        // tick loop is still running, executed will keep climbing.
        let task = StubTask(name: "stop-test", schedule: TaskSchedule(intervalSeconds: 10)) { _ in
            counter.increment()
            return TaskResult(nextRunSeconds: 0.05)
        }
        let source = StubSource(tasks: [task])
        let strategy = TimingStrategy(taskSource: source, tickInterval: 0.05)
        let (ctx, _, _) = makeContext(in: tmp)

        try await strategy.start(context: ctx)

        // Let it run a few times.
        var attempts = 0
        while executed.value < 3 && attempts < 60 {
            try? await Task.sleep(for: .milliseconds(50))
            attempts += 1
        }
        await strategy.stop()

        // After stop, wait long enough for any in-flight detached tasks to
        // drain (Scheduler dispatches task execution via Task.detached), then
        // measure the rate. The stop contract is "scheduling halts" — a
        // single in-flight completion is OK, but the counter must not keep
        // climbing at the running cadence.
        try? await Task.sleep(for: .milliseconds(300))
        let afterDrain = executed.value
        try? await Task.sleep(for: .milliseconds(500))
        #expect(executed.value == afterDrain, "tick loop still scheduling after stop")
    }

    @Test("start is idempotent — second call is a no-op")
    func startIsIdempotent() async throws {
        let tmp = makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let source = StubSource(tasks: [StubTask(name: "t", schedule: .default)])
        let strategy = TimingStrategy(taskSource: source)
        let (ctx, _, _) = makeContext(in: tmp)

        try await strategy.start(context: ctx)
        try await strategy.start(context: ctx)  // should not throw, should not duplicate state
        defer { Task { await strategy.stop() } }

        let names = await strategy.taskNames
        #expect(names.count == 1)
    }

    @Test("stop is idempotent — second call is a no-op")
    func stopIsIdempotent() async throws {
        let tmp = makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let source = StubSource(tasks: [StubTask(name: "t", schedule: .default)])
        let strategy = TimingStrategy(taskSource: source)
        let (ctx, _, _) = makeContext(in: tmp)

        try await strategy.start(context: ctx)
        await strategy.stop()
        await strategy.stop()  // should not crash

        let names = await strategy.taskNames
        #expect(names.isEmpty)
    }

    @Test("triggerTask forwards to scheduler")
    func triggerTaskForwards() async throws {
        let tmp = makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let source = StubSource(tasks: [
            StubTask(name: "pending", schedule: TaskSchedule(intervalSeconds: 3600))
        ])
        let strategy = TimingStrategy(taskSource: source, tickInterval: 1.0)
        let (ctx, _, _) = makeContext(in: tmp)

        try await strategy.start(context: ctx)
        defer { Task { await strategy.stop() } }

        // Give syncTasks time to register.
        try? await Task.sleep(for: .milliseconds(50))

        await strategy.triggerTask(name: "pending")
        let scheduled = await strategy.scheduledTask(named: "pending")
        #expect(scheduled?.nextRun.timeIntervalSinceNow ?? 999 <= 0.5)
        #expect(scheduled?.pendingRunReason == .triggered)
    }

    @Test("syncTasks picks up source changes while running")
    func syncTasksPicksUpChanges() async throws {
        let tmp = makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let source = StubSource(tasks: [StubTask(name: "a", schedule: .default)])
        let strategy = TimingStrategy(taskSource: source)
        let (ctx, _, _) = makeContext(in: tmp)

        try await strategy.start(context: ctx)
        defer { Task { await strategy.stop() } }

        source.setTasks([
            StubTask(name: "a", schedule: .default),
            StubTask(name: "b", schedule: .default)
        ])
        await strategy.syncTasks()

        let names = await strategy.taskNames
        #expect(names == ["a", "b"])
    }

    @Test("directory watcher triggers re-sync on file changes")
    func directoryWatcherSyncs() async throws {
        let tmp = makeTempDir(prefix: "watch")
        defer { try? FileManager.default.removeItem(at: tmp) }

        let watchDir = tmp.appending(path: "watched")
        try FileManager.default.createDirectory(at: watchDir, withIntermediateDirectories: true)

        let source = StubSource(
            tasks: [StubTask(name: "initial", schedule: .default)],
            watchDirectory: watchDir
        )
        let strategy = TimingStrategy(taskSource: source)
        let (ctx, _, _) = makeContext(in: tmp)

        try await strategy.start(context: ctx)
        defer { Task { await strategy.stop() } }

        // Change the source and touch the watched directory
        source.setTasks([
            StubTask(name: "initial", schedule: .default),
            StubTask(name: "added", schedule: .default)
        ])
        let marker = watchDir.appending(path: "marker.txt")
        try "hello".write(to: marker, atomically: true, encoding: .utf8)

        // Watcher debounces for 1s, so poll up to ~3s
        var names = Set<String>()
        var attempts = 0
        while !names.contains("added") && attempts < 60 {
            try? await Task.sleep(for: .milliseconds(100))
            names = await strategy.taskNames
            attempts += 1
        }
        #expect(names.contains("added"))
    }

    @Test("snapshot after stop returns empty workUnits")
    func snapshotAfterStopIsEmpty() async throws {
        let tmp = makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let source = StubSource(tasks: [StubTask(name: "t", schedule: .default)])
        let strategy = TimingStrategy(taskSource: source)
        let (ctx, _, _) = makeContext(in: tmp)

        try await strategy.start(context: ctx)
        await strategy.stop()

        let snap = await strategy.snapshot()
        #expect(snap.workUnits.isEmpty)
    }

    @Test("custom strategy name appears in snapshot")
    func customNameInSnapshot() async {
        let source = StubSource(tasks: [])
        let strategy = TimingStrategy(name: "my-timer", taskSource: source)

        let snap = await strategy.snapshot()
        #expect(snap.name == "my-timer")
        #expect(snap.kind == "timing")
    }
}

// MARK: - Lock-protected counter for test assertions

private final class LockIsolatedInt: @unchecked Sendable {
    private var _value: Int
    private let lock = NSLock()
    init(_ value: Int) { _value = value }
    var value: Int { lock.withLock { _value } }
    func increment() { lock.withLock { _value += 1 } }
}
