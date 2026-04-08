import Foundation

struct JobConfig: Codable, Sendable {
    let intervalSeconds: TimeInterval
    let enabled: Bool
    let timeout: TimeInterval
    let runAtWake: Bool
    let backoffOnFailure: Bool

    init(
        intervalSeconds: TimeInterval = 60,
        enabled: Bool = true,
        timeout: TimeInterval = 30,
        runAtWake: Bool = true,
        backoffOnFailure: Bool = true
    ) {
        self.intervalSeconds = intervalSeconds
        self.enabled = enabled
        self.timeout = timeout
        self.runAtWake = runAtWake
        self.backoffOnFailure = backoffOnFailure
    }

    static let `default` = JobConfig()
}
