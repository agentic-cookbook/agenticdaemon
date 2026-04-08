import Foundation
import Testing
@testable import AgenticDaemonLib

@Suite("CrashReport Model")
struct CrashReportTests {

    @Test("CrashReport round-trip encode/decode")
    func roundTrip() throws {
        let report = CrashReport(
            jobName: "my-job",
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            signal: "SIGABRT",
            exceptionType: "EXC_CRASH",
            faultingThread: 7,
            stackTrace: [
                CrashReport.StackFrame(
                    symbol: "JobRunner.run(job:)",
                    imageOffset: 85516,
                    sourceFile: "JobRunner.swift",
                    sourceLine: 47
                )
            ],
            source: .diagnosticReport
        )

        let data = try JSONEncoder().encode(report)
        let decoded = try JSONDecoder().decode(CrashReport.self, from: data)

        #expect(decoded.jobName == "my-job")
        #expect(decoded.signal == "SIGABRT")
        #expect(decoded.exceptionType == "EXC_CRASH")
        #expect(decoded.faultingThread == 7)
        #expect(decoded.source == .diagnosticReport)
        #expect(decoded.stackTrace?.count == 1)
        #expect(decoded.stackTrace?[0].symbol == "JobRunner.run(job:)")
        #expect(decoded.stackTrace?[0].sourceFile == "JobRunner.swift")
        #expect(decoded.stackTrace?[0].sourceLine == 47)
    }

    @Test("CrashReport with nil optional fields")
    func nilOptionals() throws {
        let report = CrashReport(
            jobName: "bare-job",
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            signal: nil,
            exceptionType: nil,
            faultingThread: nil,
            stackTrace: nil,
            source: .plcrash
        )

        let data = try JSONEncoder().encode(report)
        let decoded = try JSONDecoder().decode(CrashReport.self, from: data)

        #expect(decoded.jobName == "bare-job")
        #expect(decoded.signal == nil)
        #expect(decoded.exceptionType == nil)
        #expect(decoded.faultingThread == nil)
        #expect(decoded.stackTrace == nil)
        #expect(decoded.source == .plcrash)
    }

    @Test("StackFrame round-trip encode/decode")
    func stackFrameRoundTrip() throws {
        let frame = CrashReport.StackFrame(
            symbol: "abort",
            imageOffset: 497744,
            sourceFile: nil,
            sourceLine: nil
        )

        let data = try JSONEncoder().encode(frame)
        let decoded = try JSONDecoder().decode(CrashReport.StackFrame.self, from: data)

        #expect(decoded.symbol == "abort")
        #expect(decoded.imageOffset == 497744)
        #expect(decoded.sourceFile == nil)
        #expect(decoded.sourceLine == nil)
    }

    @Test("CrashReportCollector returns empty when no crash data")
    func collectorEmptyWhenNoCrash() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "crash-report-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let collector = CrashReportCollector(
            supportDirectory: tempDir,
            diagnosticReportsDirectory: tempDir.appending(path: "empty-diag"),
            processName: "agentic-daemon"
        )

        let reports = collector.collectPendingReports(crashedJobName: "some-job")
        #expect(reports.isEmpty)
    }

    @Test("Crash report is persisted to disk as JSON")
    func persistsReport() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "crash-persist-test-\(UUID().uuidString)")
        let crashesDir = tempDir.appending(path: "crashes")
        try FileManager.default.createDirectory(at: crashesDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let report = CrashReport(
            jobName: "bad-plugin",
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            signal: "SIGSEGV",
            exceptionType: "EXC_BAD_ACCESS",
            faultingThread: 3,
            stackTrace: [
                CrashReport.StackFrame(symbol: "abort", imageOffset: 100, sourceFile: nil, sourceLine: nil)
            ],
            source: .plcrash
        )

        let store = CrashReportStore(crashesDirectory: crashesDir)
        try store.save(report)

        let files = try FileManager.default.contentsOfDirectory(
            at: crashesDir, includingPropertiesForKeys: nil
        ).filter { $0.pathExtension == "json" }
        #expect(files.count == 1)
    }

    @Test("Persisted crash report is readable back")
    func readsPersistedReport() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "crash-read-test-\(UUID().uuidString)")
        let crashesDir = tempDir.appending(path: "crashes")
        try FileManager.default.createDirectory(at: crashesDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let report = CrashReport(
            jobName: "bad-plugin",
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            signal: "SIGABRT",
            exceptionType: "EXC_CRASH",
            faultingThread: 7,
            stackTrace: nil,
            source: .diagnosticReport
        )

        let store = CrashReportStore(crashesDirectory: crashesDir)
        try store.save(report)

        let loaded = store.loadAll()
        #expect(loaded.count == 1)
        #expect(loaded[0].jobName == "bad-plugin")
        #expect(loaded[0].signal == "SIGABRT")
        #expect(loaded[0].source == .diagnosticReport)
    }

    @Test("Cleanup removes reports older than retention period")
    func cleansUpOldReports() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "crash-cleanup-test-\(UUID().uuidString)")
        let crashesDir = tempDir.appending(path: "crashes")
        try FileManager.default.createDirectory(at: crashesDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Write a report file manually with an old timestamp in the name
        let oldFile = crashesDir.appending(path: "crash-2020-01-01T000000Z.json")
        let report = CrashReport(
            jobName: "ancient",
            timestamp: Date(timeIntervalSince1970: 1_577_836_800),
            signal: nil, exceptionType: nil, faultingThread: nil,
            stackTrace: nil, source: .plcrash
        )
        let data = try JSONEncoder().encode(report)
        try data.write(to: oldFile)

        // Write a recent one
        let store = CrashReportStore(crashesDirectory: crashesDir)
        let recentReport = CrashReport(
            jobName: "recent",
            timestamp: Date.now,
            signal: "SIGABRT", exceptionType: nil, faultingThread: nil,
            stackTrace: nil, source: .plcrash
        )
        try store.save(recentReport)

        store.cleanup(retentionDays: 30)

        let remaining = store.loadAll()
        #expect(remaining.count == 1)
        #expect(remaining[0].jobName == "recent")
    }
}
