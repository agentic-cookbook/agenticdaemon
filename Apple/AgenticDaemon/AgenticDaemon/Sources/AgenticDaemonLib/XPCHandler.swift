import Foundation
import os

/// Implements AgenticDaemonXPC by delegating each operation to an injected closure.
/// This design keeps XPCHandler testable without a running XPC server or real Scheduler.
final class XPCHandler: NSObject, AgenticDaemonXPC, @unchecked Sendable {

    struct Dependencies: Sendable {
        /// Returns the current daemon status.
        let getStatus: @Sendable () async -> DaemonStatus
        /// Returns all stored crash reports.
        let getCrashReports: @Sendable () -> [CrashReport]
        /// Enables the named job. Returns false if the job is not found.
        let enableJob: @Sendable (String) async -> Bool
        /// Disables the named job. Returns false if the job is not found.
        let disableJob: @Sendable (String) async -> Bool
        /// Sets the named job's next run time to now. Returns false if not found.
        let triggerJob: @Sendable (String) async -> Bool
        /// Clears the crash blacklist for the named job.
        let clearBlocklist: @Sendable (String) -> Bool
        /// Shuts the daemon down.
        let onShutdown: @Sendable () -> Void
    }

    private let deps: Dependencies
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    init(dependencies: Dependencies) {
        self.deps = dependencies
    }

    func getDaemonStatus(reply: @escaping @Sendable (Data) -> Void) {
        Task {
            let status = await deps.getStatus()
            reply((try? encoder.encode(status)) ?? Data())
        }
    }

    func getCrashReports(reply: @escaping @Sendable (Data) -> Void) {
        let reports = deps.getCrashReports()
        reply((try? encoder.encode(reports)) ?? Data())
    }

    func enableJob(_ name: String, reply: @escaping @Sendable (Bool) -> Void) {
        Task { reply(await deps.enableJob(name)) }
    }

    func disableJob(_ name: String, reply: @escaping @Sendable (Bool) -> Void) {
        Task { reply(await deps.disableJob(name)) }
    }

    func triggerJob(_ name: String, reply: @escaping @Sendable (Bool) -> Void) {
        Task { reply(await deps.triggerJob(name)) }
    }

    func clearBlocklist(_ name: String, reply: @escaping @Sendable (Bool) -> Void) {
        reply(deps.clearBlocklist(name))
    }

    func shutdown(reply: @escaping @Sendable () -> Void) {
        deps.onShutdown()
        reply()
    }
}
