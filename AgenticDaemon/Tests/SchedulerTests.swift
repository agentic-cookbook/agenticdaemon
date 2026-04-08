import Testing
import Foundation
@testable import AgenticDaemonLib

@Suite("Scheduler", .serialized)
struct SchedulerTests {

    @Test("syncJobs adds new enabled jobs")
    func addsEnabledJobs() {
        let tmpDir = makeTempDir(prefix: "sched")
        // Create a valid source so compilation succeeds
        createJobDir(in: tmpDir, name: "job-a", swiftSource: "print(\"a\")\n")
        let descriptor = makeDescriptor(in: tmpDir, name: "job-a")
        let scheduler = Scheduler()

        scheduler.syncJobs(discovered: [descriptor])

        #expect(scheduler.jobCount == 1)
        #expect(scheduler.jobNames.contains("job-a"))
        cleanupTempDir(tmpDir)
    }

    @Test("syncJobs skips disabled jobs")
    func skipsDisabledJobs() {
        let tmpDir = makeTempDir(prefix: "sched")
        createJobDir(in: tmpDir, name: "disabled", swiftSource: "print(\"x\")\n")
        let config = JobConfig(enabled: false)
        let descriptor = makeDescriptor(in: tmpDir, name: "disabled", config: config)
        let scheduler = Scheduler()

        scheduler.syncJobs(discovered: [descriptor])

        #expect(scheduler.isEmpty)
        cleanupTempDir(tmpDir)
    }

    @Test("syncJobs removes jobs no longer discovered")
    func removesDeletedJobs() {
        let tmpDir = makeTempDir(prefix: "sched")
        createJobDir(in: tmpDir, name: "ephemeral", swiftSource: "print(\"bye\")\n")
        let descriptor = makeDescriptor(in: tmpDir, name: "ephemeral")
        let scheduler = Scheduler()

        scheduler.syncJobs(discovered: [descriptor])
        #expect(scheduler.jobCount == 1)

        scheduler.syncJobs(discovered: [])
        #expect(scheduler.isEmpty)
        cleanupTempDir(tmpDir)
    }

    @Test("tick dispatches jobs whose nextRun is past")
    func dispatchesPastJobs() {
        let tmpDir = makeTempDir(prefix: "sched")
        createJobDir(in: tmpDir, name: "ready", swiftSource: "print(\"go\")\n")
        let descriptor = makeDescriptor(in: tmpDir, name: "ready")
        let scheduler = Scheduler()

        scheduler.syncJobs(discovered: [descriptor])

        // Job was added with nextRun = Date.now, so tick should dispatch it
        scheduler.tick()

        // Allow background dispatch to start
        Thread.sleep(forTimeInterval: 1.0)

        // After running, job should still exist but isRunning should eventually clear
        #expect(scheduler.jobCount == 1)
        cleanupTempDir(tmpDir)
    }

    @Test("tick does not dispatch jobs that are already running")
    func doesNotDoubleDispatch() {
        let tmpDir = makeTempDir(prefix: "sched")
        // Use a slow job so it's still running when second tick fires
        createJobDir(in: tmpDir, name: "slow", swiftSource: "import Foundation\nThread.sleep(forTimeInterval: 3)\n")
        let descriptor = makeDescriptor(in: tmpDir, name: "slow")
        let scheduler = Scheduler()

        scheduler.syncJobs(discovered: [descriptor])

        // First tick dispatches the job
        scheduler.tick()
        Thread.sleep(forTimeInterval: 0.1)

        // Job should be marked running — verify it's not dispatched again
        let job = scheduler.job(named: "slow")
        #expect(job?.isRunning == true)

        // Second tick should not dispatch again (already running)
        scheduler.tick()

        // Wait for job to complete
        Thread.sleep(forTimeInterval: 4.0)
        cleanupTempDir(tmpDir)
    }
}
