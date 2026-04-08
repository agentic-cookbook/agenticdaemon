import Foundation
import os

public struct DaemonStatus: Codable, Sendable {
    public let uptimeSeconds: TimeInterval
    public let jobCount: Int
    public let lastTick: Date
    public let jobs: [JobStatus]

    public struct JobStatus: Codable, Sendable {
        public let name: String
        public let nextRun: Date
        public let consecutiveFailures: Int
        public let isRunning: Bool

        public init(name: String, nextRun: Date, consecutiveFailures: Int, isRunning: Bool) {
            self.name = name
            self.nextRun = nextRun
            self.consecutiveFailures = consecutiveFailures
            self.isRunning = isRunning
        }
    }

    public init(uptimeSeconds: TimeInterval, jobCount: Int, lastTick: Date, jobs: [JobStatus]) {
        self.uptimeSeconds = uptimeSeconds
        self.jobCount = jobCount
        self.lastTick = lastTick
        self.jobs = jobs
    }
}

public struct StatusWriter: Sendable {
    private let logger = Logger(
        subsystem: "com.agentic-cookbook.daemon",
        category: "StatusWriter"
    )
    private let statusURL: URL

    public init(statusURL: URL) {
        self.statusURL = statusURL
    }

    public func write(status: DaemonStatus) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        do {
            let data = try encoder.encode(status)
            try data.write(to: statusURL, options: .atomic)
        } catch {
            logger.error("Failed to write status file: \(error)")
        }
    }
}
