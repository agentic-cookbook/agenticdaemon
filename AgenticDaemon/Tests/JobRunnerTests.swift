import Testing
import Foundation
@testable import AgenticDaemonLib

@Suite("JobRunner", .serialized)
struct JobRunnerTests {
    let runner = JobRunner()
    let compiler = SwiftCompiler()
    let tmpDir: URL

    init() {
        tmpDir = makeTempDir(prefix: "runner")
    }

    @Test("Runs compiled binary successfully")
    func runsSuccessfully() throws {
        createJobDir(in: tmpDir, name: "hello", swiftSource: "print(\"hello\")\n")
        let descriptor = makeDescriptor(in: tmpDir, name: "hello")
        try compiler.compile(job: descriptor)

        runner.run(job: descriptor)
        cleanupTempDir(tmpDir)
    }

    @Test("Handles missing binary gracefully")
    func handlesMissingBinary() {
        createJobDir(in: tmpDir, name: "no-bin", swiftSource: "print(\"hi\")\n")
        let descriptor = makeDescriptor(in: tmpDir, name: "no-bin")

        runner.run(job: descriptor)
        cleanupTempDir(tmpDir)
    }

    @Test("Terminates job that exceeds timeout")
    func terminatesOnTimeout() throws {
        let sleepSource = """
        import Foundation
        Thread.sleep(forTimeInterval: 60)
        """
        createJobDir(in: tmpDir, name: "sleeper", swiftSource: sleepSource)
        let config = JobConfig(timeout: 2)
        let descriptor = JobDescriptor(
            name: "sleeper",
            directory: tmpDir.appending(path: "sleeper"),
            sourceURL: tmpDir.appending(path: "sleeper/job.swift"),
            binaryURL: tmpDir.appending(path: "sleeper/.job-bin"),
            config: config
        )
        try compiler.compile(job: descriptor)

        let start = Date.now
        runner.run(job: descriptor)
        let elapsed = Date.now.timeIntervalSince(start)

        #expect(elapsed < 10)
        cleanupTempDir(tmpDir)
    }
}
