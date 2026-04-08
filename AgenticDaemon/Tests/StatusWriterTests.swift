import Testing
import Foundation
@testable import AgenticDaemonLib

@Suite("StatusWriter")
struct StatusWriterTests {

    @Test("Writes valid JSON status file")
    func writesValidJSON() throws {
        let tmpDir = makeTempDir(prefix: "status")
        let statusURL = tmpDir.appending(path: "status.json")
        let writer = StatusWriter(statusURL: statusURL)

        let snapshot = DaemonStatus(
            uptimeSeconds: 120,
            jobCount: 2,
            lastTick: Date.now,
            jobs: [
                DaemonStatus.JobStatus(
                    name: "job-a",
                    nextRun: Date.now.addingTimeInterval(60),
                    consecutiveFailures: 0,
                    isRunning: false
                ),
                DaemonStatus.JobStatus(
                    name: "job-b",
                    nextRun: Date.now.addingTimeInterval(30),
                    consecutiveFailures: 2,
                    isRunning: true
                )
            ]
        )

        writer.write(status: snapshot)

        let data = try Data(contentsOf: statusURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(DaemonStatus.self, from: data)

        #expect(decoded.uptimeSeconds == 120)
        #expect(decoded.jobCount == 2)
        #expect(decoded.jobs.count == 2)
        #expect(decoded.jobs[0].name == "job-a")
        #expect(decoded.jobs[1].consecutiveFailures == 2)
        #expect(decoded.jobs[1].isRunning == true)
        cleanupTempDir(tmpDir)
    }

    @Test("Status file contains expected fields")
    func containsExpectedFields() throws {
        let tmpDir = makeTempDir(prefix: "status")
        let statusURL = tmpDir.appending(path: "status.json")
        let writer = StatusWriter(statusURL: statusURL)

        let snapshot = DaemonStatus(
            uptimeSeconds: 60,
            jobCount: 0,
            lastTick: Date.now,
            jobs: []
        )

        writer.write(status: snapshot)

        let data = try Data(contentsOf: statusURL)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        #expect(json["uptimeSeconds"] != nil)
        #expect(json["jobCount"] != nil)
        #expect(json["lastTick"] != nil)
        #expect(json["jobs"] != nil)
        cleanupTempDir(tmpDir)
    }

    @Test("Overwrites previous status file")
    func overwritesPrevious() throws {
        let tmpDir = makeTempDir(prefix: "status")
        let statusURL = tmpDir.appending(path: "status.json")
        let writer = StatusWriter(statusURL: statusURL)

        let first = DaemonStatus(uptimeSeconds: 10, jobCount: 1, lastTick: Date.now, jobs: [])
        writer.write(status: first)

        let second = DaemonStatus(uptimeSeconds: 20, jobCount: 3, lastTick: Date.now, jobs: [])
        writer.write(status: second)

        let data = try Data(contentsOf: statusURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(DaemonStatus.self, from: data)

        #expect(decoded.uptimeSeconds == 20)
        #expect(decoded.jobCount == 3)
        cleanupTempDir(tmpDir)
    }
}
