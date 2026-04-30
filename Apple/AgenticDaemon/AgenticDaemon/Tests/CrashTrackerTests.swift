import Testing
import Foundation
@testable import AgenticDaemonLib

@Suite("CrashTracker")
struct CrashTrackerTests {
    let tmpDir: URL

    init() {
        tmpDir = makeTempDir(prefix: "crash")
    }

    @Test("No crash detected on fresh start")
    func noCrashOnFreshStart() {
        let tracker = CrashTracker(stateDir: tmpDir, subsystem: "test")
        #expect(tracker.checkForCrash() == nil)
        cleanupTempDir(tmpDir)
    }

    @Test("Detects crash when running state file exists")
    func detectsCrash() {
        let tracker = CrashTracker(stateDir: tmpDir, subsystem: "test")
        tracker.markRunning(taskName: "bad-job")

        // Simulate daemon restart — new tracker reads state
        let tracker2 = CrashTracker(stateDir: tmpDir, subsystem: "test")
        #expect(tracker2.checkForCrash() == "bad-job")
        cleanupTempDir(tmpDir)
    }

    @Test("clearRunning removes state file")
    func clearRunning() {
        let tracker = CrashTracker(stateDir: tmpDir, subsystem: "test")
        tracker.markRunning(taskName: "ok-job")
        tracker.clearRunning()

        let tracker2 = CrashTracker(stateDir: tmpDir, subsystem: "test")
        #expect(tracker2.checkForCrash() == nil)
        cleanupTempDir(tmpDir)
    }

    @Test("Blacklists a crashed job")
    func blocklistsJob() {
        let tracker = CrashTracker(stateDir: tmpDir, subsystem: "test")
        tracker.blocklist(taskName: "crasher")

        #expect(tracker.isBlocklisted(taskName: "crasher"))
        #expect(!tracker.isBlocklisted(taskName: "other"))
        cleanupTempDir(tmpDir)
    }

    @Test("Blacklist persists across instances")
    func blocklistPersists() {
        let tracker = CrashTracker(stateDir: tmpDir, subsystem: "test")
        tracker.blocklist(taskName: "crasher")

        let tracker2 = CrashTracker(stateDir: tmpDir, subsystem: "test")
        #expect(tracker2.isBlocklisted(taskName: "crasher"))
        cleanupTempDir(tmpDir)
    }

    @Test("clearBlacklist removes a specific job")
    func clearBlocklist() {
        let tracker = CrashTracker(stateDir: tmpDir, subsystem: "test")
        tracker.blocklist(taskName: "job-a")
        tracker.blocklist(taskName: "job-b")

        tracker.clearBlocklist(taskName: "job-a")

        #expect(!tracker.isBlocklisted(taskName: "job-a"))
        #expect(tracker.isBlocklisted(taskName: "job-b"))
        cleanupTempDir(tmpDir)
    }

    @Test("crashedJobName returns name without clearing state")
    func crashedJobNameDoesNotClear() {
        let tracker = CrashTracker(stateDir: tmpDir, subsystem: "test")
        tracker.markRunning(taskName: "bad-job")

        let tracker2 = CrashTracker(stateDir: tmpDir, subsystem: "test")
        #expect(tracker2.crashedTaskName() == "bad-job")

        // Should still be readable — not cleared
        let tracker3 = CrashTracker(stateDir: tmpDir, subsystem: "test")
        #expect(tracker3.crashedTaskName() == "bad-job")
        cleanupTempDir(tmpDir)
    }

    @Test("crashedJobName returns nil on fresh start")
    func crashedJobNameNilOnFresh() {
        let tracker = CrashTracker(stateDir: tmpDir, subsystem: "test")
        #expect(tracker.crashedTaskName() == nil)
        cleanupTempDir(tmpDir)
    }

    @Test("checkForCrash clears the running state")
    func checkClearsState() {
        let tracker = CrashTracker(stateDir: tmpDir, subsystem: "test")
        tracker.markRunning(taskName: "bad-job")

        let tracker2 = CrashTracker(stateDir: tmpDir, subsystem: "test")
        _ = tracker2.checkForCrash()

        // After checking, the state should be cleared
        let tracker3 = CrashTracker(stateDir: tmpDir, subsystem: "test")
        #expect(tracker3.checkForCrash() == nil)
        cleanupTempDir(tmpDir)
    }
}
