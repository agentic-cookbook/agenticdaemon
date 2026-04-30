import Testing
import Foundation
@testable import DaemonKit

@Suite("DaemonStrategy types")
struct DaemonStrategyTypesTests {

    @Test("StrategySnapshot round-trips through Codable")
    func strategySnapshotCodable() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let snapshot = StrategySnapshot(
            name: "timing",
            kind: "timing",
            workUnits: [
                WorkUnitSnapshot(
                    name: "job-a",
                    state: .idle,
                    nextActivation: now,
                    consecutiveFailures: 2,
                    isBlocklisted: false,
                    lastMessage: "ok"
                ),
                WorkUnitSnapshot(
                    name: "job-b",
                    state: .running,
                    nextActivation: nil,
                    consecutiveFailures: 0,
                    isBlocklisted: true,
                    lastMessage: nil
                )
            ]
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(snapshot)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(StrategySnapshot.self, from: data)

        #expect(decoded.name == "timing")
        #expect(decoded.kind == "timing")
        #expect(decoded.workUnits.count == 2)
        #expect(decoded.workUnits[0].name == "job-a")
        #expect(decoded.workUnits[0].state == .idle)
        #expect(decoded.workUnits[0].consecutiveFailures == 2)
        #expect(decoded.workUnits[0].nextActivation == now)
        #expect(decoded.workUnits[1].state == .running)
        #expect(decoded.workUnits[1].isBlocklisted == true)
        #expect(decoded.workUnits[1].nextActivation == nil)
    }

    @Test("WorkUnitState raw values are stable wire strings")
    func workUnitStateRawValues() {
        #expect(WorkUnitSnapshot.WorkUnitState.idle.rawValue == "idle")
        #expect(WorkUnitSnapshot.WorkUnitState.running.rawValue == "running")
        #expect(WorkUnitSnapshot.WorkUnitState.disabled.rawValue == "disabled")
        #expect(WorkUnitSnapshot.WorkUnitState.blocklisted.rawValue == "blacklisted")
    }

    @Test("DaemonContext captures dependencies without copying them needlessly")
    func daemonContextCapturesDependencies() {
        let tmp = FileManager.default.temporaryDirectory
            .appending(path: "ctx-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let tracker = CrashTracker(stateDir: tmp, subsystem: "test")
        let analytics = RecordingAnalytics()
        let context = DaemonContext(
            crashTracker: tracker,
            analytics: analytics,
            subsystem: "com.example",
            supportDirectory: tmp
        )

        #expect(context.subsystem == "com.example")
        #expect(context.supportDirectory == tmp)

        // Verify analytics reference is preserved (same instance)
        context.analytics.track(.taskStarted(name: "x"))
        #expect(analytics.events.count == 1)
    }
}

// MARK: - Test doubles

final class RecordingAnalytics: AnalyticsProvider, @unchecked Sendable {
    private var _events: [AnalyticsEvent] = []
    private let lock = NSLock()
    var events: [AnalyticsEvent] { lock.withLock { _events } }
    func track(_ event: AnalyticsEvent) { lock.withLock { _events.append(event) } }
}
