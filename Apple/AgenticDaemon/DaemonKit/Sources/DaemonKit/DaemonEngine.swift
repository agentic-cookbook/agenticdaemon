import Foundation
import os

/// The composition root for a DaemonKit-based daemon.
///
/// The engine owns cross-cutting infrastructure — crash tracking, crash
/// report collection, launchd-friendly signal plumbing, XPC server, HTTP
/// server — and delegates *when* and *what* work happens to a
/// ``DaemonStrategy``. Clients compose one or more strategies
/// (``TimingStrategy``, ``EventStrategy``, ``CompositeStrategy``) and hand
/// the engine the composition plus any domain-specific wire objects.
///
///     let strategy = TimingStrategy(taskSource: mySource)
///     let engine = DaemonEngine(
///         configuration: config,
///         strategy: strategy,
///         analytics: LogAnalyticsProvider(subsystem: config.identifier)
///     )
///     await engine.run(xpcExportedObject: handler, xpcInterface: interface)
///
/// The engine never branches on strategy type.
public final class DaemonEngine: @unchecked Sendable {
    private let logger: Logger
    private let configuration: DaemonConfiguration
    private let analytics: any AnalyticsProvider
    private let _running = OSAllocatedUnfairLock(initialState: true)

    /// The crash tracker. Exposed so clients can query blacklist state.
    public let crashTracker: CrashTracker
    private let crashReportCollector: CrashReportCollector
    /// The crash report store. Exposed so clients can query crash history.
    public let crashReportStore: CrashReportStore

    /// The strategy this engine drives. Typed as `any DaemonStrategy` —
    /// clients holding a concrete reference (e.g. ``TimingStrategy``) for
    /// rich introspection should capture it at construction time rather
    /// than downcasting here.
    public let strategy: any DaemonStrategy

    /// When the engine was created. Useful for uptime reporting.
    public let startDate = Date.now

    private var xpcServer: XPCServer?
    private var httpServer: HTTPServer?

    public init(
        configuration: DaemonConfiguration,
        strategy: any DaemonStrategy,
        analytics: any AnalyticsProvider
    ) {
        let subsystem = configuration.identifier
        self.logger = Logger(subsystem: subsystem, category: "DaemonEngine")
        self.configuration = configuration
        self.strategy = strategy
        self.analytics = analytics

        crashTracker = CrashTracker(stateDir: configuration.supportDirectory, subsystem: subsystem)
        crashReportCollector = CrashReportCollector(
            supportDirectory: configuration.supportDirectory,
            processName: configuration.crashReportProcessName,
            subsystem: subsystem
        )
        crashReportStore = CrashReportStore(
            crashesDirectory: configuration.crashesDirectory,
            subsystem: subsystem
        )
    }

    /// Start the daemon. Blocks until ``shutdown()`` is called.
    ///
    /// - Parameters:
    ///   - xpcExportedObject: An NSObject to export over XPC. Required if
    ///     `configuration.machServiceName` is set.
    ///   - xpcInterface: The ``NSXPCInterface`` describing the protocol.
    ///   - httpRouter: Optional HTTP router. Required if
    ///     `configuration.httpPort` is set.
    public func run(
        xpcExportedObject: AnyObject? = nil,
        xpcInterface: NSXPCInterface? = nil,
        httpRouter: (any DaemonHTTPRouter)? = nil
    ) async {
        logger.info("Starting daemon: \(self.configuration.identifier)")

        createDirectories()

        do {
            try crashReportCollector.installCrashHandler()
        } catch {
            logger.error("Failed to install crash handler: \(error)")
        }

        processPreviousCrashIfAny()
        crashReportStore.cleanup(retentionDays: configuration.crashRetentionDays)

        let context = DaemonContext(
            crashTracker: crashTracker,
            analytics: analytics,
            subsystem: configuration.identifier,
            supportDirectory: configuration.supportDirectory
        )
        do {
            try await strategy.start(context: context)
        } catch {
            logger.error("Strategy \"\(self.strategy.name)\" failed to start: \(error)")
            return
        }

        if let machServiceName = configuration.machServiceName,
           let exportedObject = xpcExportedObject,
           let interface = xpcInterface {
            let server = XPCServer(
                machServiceName: machServiceName,
                interface: interface,
                exportedObject: exportedObject,
                subsystem: configuration.identifier
            )
            server.start()
            self.xpcServer = server
        }

        if let httpPort = configuration.httpPort, let router = httpRouter {
            let server = HTTPServer(port: httpPort, router: router, subsystem: configuration.identifier)
            do {
                try server.start()
                self.httpServer = server
            } catch {
                logger.error("Failed to start HTTP server: \(error)")
            }
        }

        logger.info("Daemon running with strategy \"\(self.strategy.name)\"")

        while _running.withLock({ $0 }) {
            try? await Task.sleep(for: .seconds(configuration.tickInterval))
        }

        await strategy.stop()
        httpServer?.stop()
        logger.info("Daemon stopped")
    }

    public func shutdown() {
        logger.info("Shutdown requested")
        _running.withLock { $0 = false }
    }

    // MARK: - Private

    private func processPreviousCrashIfAny() {
        guard let crashedTask = crashTracker.crashedTaskName() else { return }
        let reports = crashReportCollector.collectPendingReports(crashedTaskName: crashedTask)
        for report in reports {
            analytics.track(.taskCrashed(
                name: report.taskName,
                signal: report.signal,
                exceptionType: report.exceptionType
            ))
            do {
                try crashReportStore.save(report)
            } catch {
                logger.error("Failed to save crash report: \(error)")
            }
        }
        if reports.isEmpty {
            logger.info("Crash detected for \(crashedTask) but no crash reports found")
        }
    }

    private func createDirectories() {
        let fileManager = FileManager.default
        let dirs = [
            configuration.supportDirectory,
            configuration.crashesDirectory
        ]
        for dir in dirs {
            let path = dir.path(percentEncoded: false)
            guard !fileManager.fileExists(atPath: path) else { continue }
            do {
                try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
                logger.info("Created directory: \(path)")
            } catch {
                logger.error("Failed to create directory \(path): \(error)")
            }
        }
    }
}
