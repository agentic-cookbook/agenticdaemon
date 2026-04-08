import Testing
import Foundation
@testable import AgenticDaemonLib

@Suite("Scheduler", .serialized)
struct SchedulerTests {

    @Test("syncJobs adds new enabled jobs")
    func addsEnabledJobs() async {
        let tmpDir = makeTempDir(prefix: "sched")
        createJobDir(in: tmpDir, name: "job-a", swiftSource: validJobSource())
        let descriptor = makeDescriptor(in: tmpDir, name: "job-a")
        let scheduler = Scheduler(buildDir: findBuildDir())

        await scheduler.syncJobs(discovered: [descriptor])

        let count = await scheduler.jobCount
        let names = await scheduler.jobNames
        #expect(count == 1)
        #expect(names.contains("job-a"))
        cleanupTempDir(tmpDir)
    }

    @Test("syncJobs skips disabled jobs")
    func skipsDisabledJobs() async {
        let tmpDir = makeTempDir(prefix: "sched")
        createJobDir(in: tmpDir, name: "disabled", swiftSource: validJobSource())
        let config = JobConfig(enabled: false)
        let descriptor = makeDescriptor(in: tmpDir, name: "disabled", config: config)
        let scheduler = Scheduler(buildDir: findBuildDir())

        await scheduler.syncJobs(discovered: [descriptor])

        let empty = await scheduler.isEmpty
        #expect(empty)
        cleanupTempDir(tmpDir)
    }

    @Test("syncJobs removes jobs no longer discovered")
    func removesDeletedJobs() async {
        let tmpDir = makeTempDir(prefix: "sched")
        createJobDir(in: tmpDir, name: "ephemeral", swiftSource: validJobSource())
        let descriptor = makeDescriptor(in: tmpDir, name: "ephemeral")
        let scheduler = Scheduler(buildDir: findBuildDir())

        await scheduler.syncJobs(discovered: [descriptor])
        let count1 = await scheduler.jobCount
        #expect(count1 == 1)

        await scheduler.syncJobs(discovered: [])
        let empty = await scheduler.isEmpty
        #expect(empty)
        cleanupTempDir(tmpDir)
    }

    @Test("tick dispatches jobs whose nextRun is past")
    func dispatchesPastJobs() async {
        let tmpDir = makeTempDir(prefix: "sched")
        createJobDir(in: tmpDir, name: "ready", swiftSource: validJobSource())
        let descriptor = makeDescriptor(in: tmpDir, name: "ready")
        let scheduler = Scheduler(buildDir: findBuildDir())

        await scheduler.syncJobs(discovered: [descriptor])
        await scheduler.tick()

        try? await Task.sleep(for: .seconds(1))

        let count = await scheduler.jobCount
        #expect(count == 1)
        cleanupTempDir(tmpDir)
    }
}
