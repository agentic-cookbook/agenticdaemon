import Foundation
import os

/// A ``DaemonStrategy`` that schedules ``DaemonTask`` units on a tick loop.
///
/// Wraps the lower-level ``Scheduler`` actor, a ``TaskSource``, and an
/// optional ``DirectoryWatcher`` that re-syncs the source when its watch
/// directory changes. Owns its own tick loop internally — the engine
/// never ticks the strategy.
///
///     let strategy = TimingStrategy(taskSource: mySource)
///     let engine = DaemonEngine(configuration: cfg, strategy: strategy, analytics: a)
///     await engine.run(xpcExportedObject: handler, xpcInterface: iface)
///
/// Concrete clients that need rich scheduler access (e.g. to build XPC
/// handlers exposing enable/disable/trigger) hold the ``TimingStrategy``
/// directly and query it through its public convenience methods.
public final class TimingStrategy: DaemonStrategy, @unchecked Sendable {
    public let name: String

    private let taskSource: any TaskSource
    private let tickInterval: TimeInterval

    private let state = OSAllocatedUnfairLock(initialState: State())

    private struct State {
        var scheduler: Scheduler?
        var watcher: DirectoryWatcher?
        var tickTask: Task<Void, Never>?
        var running: Bool = false
        var logger: Logger?
        var crashTracker: CrashTracker?
    }

    public init(
        name: String = "timing",
        taskSource: any TaskSource,
        tickInterval: TimeInterval = 1.0
    ) {
        self.name = name
        self.taskSource = taskSource
        self.tickInterval = tickInterval
    }

    public func start(context: DaemonContext) async throws {
        let logger = Logger(subsystem: context.subsystem, category: "TimingStrategy")
        let scheduler = Scheduler(
            crashTracker: context.crashTracker,
            analytics: context.analytics,
            subsystem: context.subsystem
        )

        state.withLock {
            guard !$0.running else { return }
            $0.scheduler = scheduler
            $0.logger = logger
            $0.crashTracker = context.crashTracker
            $0.running = true
        }

        await scheduler.recoverFromCrash()
        await scheduler.syncTasks(from: taskSource)

        if let watchDir = taskSource.watchDirectory {
            let source = taskSource
            let watcher = DirectoryWatcher(directory: watchDir, subsystem: context.subsystem) { [weak self] in
                guard let self else { return }
                Task { [weak self] in
                    guard let scheduler = self?.currentScheduler else { return }
                    await scheduler.syncTasks(from: source)
                }
            }
            watcher.start()
            state.withLock { $0.watcher = watcher }
        }

        let tickInterval = self.tickInterval
        let tickTask = Task.detached(priority: .utility) { [weak self] in
            while let self, self.isRunning, !Task.isCancelled {
                if let scheduler = self.currentScheduler {
                    await scheduler.tick()
                }
                try? await Task.sleep(for: .seconds(tickInterval))
            }
        }
        state.withLock { $0.tickTask = tickTask }

        logger.info("TimingStrategy \"\(self.name)\" started (tick: \(self.tickInterval)s)")
    }

    public func stop() async {
        let (tickTask, watcher, logger) = state.withLock { state -> (Task<Void, Never>?, DirectoryWatcher?, Logger?) in
            guard state.running else { return (nil, nil, state.logger) }
            state.running = false
            let result = (state.tickTask, state.watcher, state.logger)
            state.tickTask = nil
            state.watcher = nil
            return result
        }

        watcher?.stop()
        tickTask?.cancel()
        _ = await tickTask?.value

        state.withLock {
            $0.scheduler = nil
            $0.crashTracker = nil
        }
        logger?.info("TimingStrategy \"\(self.name)\" stopped")
    }

    public func snapshot() async -> StrategySnapshot {
        let (scheduler, crashTracker) = state.withLock { ($0.scheduler, $0.crashTracker) }
        guard let scheduler, let crashTracker else {
            return StrategySnapshot(name: name, kind: Self.kind, workUnits: [])
        }
        let names = await scheduler.taskNames
        var units: [WorkUnitSnapshot] = []
        for taskName in names.sorted() {
            guard let scheduled = await scheduler.scheduledTask(named: taskName) else { continue }
            let isBlacklisted = crashTracker.isBlacklisted(taskName: taskName)
            let unitState: WorkUnitSnapshot.WorkUnitState
            if isBlacklisted {
                unitState = .blacklisted
            } else if !scheduled.task.schedule.enabled {
                unitState = .disabled
            } else if scheduled.isRunning {
                unitState = .running
            } else {
                unitState = .idle
            }
            units.append(WorkUnitSnapshot(
                name: taskName,
                state: unitState,
                nextActivation: scheduled.nextRun,
                consecutiveFailures: scheduled.consecutiveFailures,
                isBlacklisted: isBlacklisted
            ))
        }
        return StrategySnapshot(name: name, kind: Self.kind, workUnits: units)
    }

    /// Canonical kind string for TimingStrategy instances.
    public static let kind = "timing"

    // MARK: - Rich access for concrete daemon clients
    //
    // These forward to the underlying Scheduler when the strategy is running.
    // Callers querying before start() or after stop() get a benign empty
    // result (mirrors the pre-refactor DaemonEngine.scheduler exposure).

    /// The set of task names currently scheduled. Empty before start / after stop.
    public var taskNames: Set<String> {
        get async {
            guard let scheduler = currentScheduler else { return [] }
            return await scheduler.taskNames
        }
    }

    /// Number of currently scheduled tasks. Zero before start / after stop.
    public var taskCount: Int {
        get async {
            guard let scheduler = currentScheduler else { return 0 }
            return await scheduler.taskCount
        }
    }

    /// Look up a scheduled task by name. Nil before start or if absent.
    public func scheduledTask(named taskName: String) async -> Scheduler.ScheduledTask? {
        guard let scheduler = currentScheduler else { return nil }
        return await scheduler.scheduledTask(named: taskName)
    }

    /// Trigger a task to run at the next tick.
    public func triggerTask(name taskName: String) async {
        guard let scheduler = currentScheduler else { return }
        await scheduler.triggerTask(name: taskName)
    }

    /// Re-sync tasks from the source. Typically called after a config change
    /// flips a task's enabled flag.
    public func syncTasks() async {
        guard let scheduler = currentScheduler else { return }
        await scheduler.syncTasks(from: taskSource)
    }

    // MARK: - Private

    private var currentScheduler: Scheduler? {
        state.withLock { $0.scheduler }
    }

    private var isRunning: Bool {
        state.withLock { $0.running }
    }
}
