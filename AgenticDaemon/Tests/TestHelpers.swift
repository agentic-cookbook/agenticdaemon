import Foundation
@testable import AgenticDaemonLib

/// Creates a temporary directory for test isolation. Caller must clean up.
func makeTempDir(prefix: String = "agenticd-test") -> URL {
    let tmp = FileManager.default.temporaryDirectory
        .appending(path: "\(prefix)-\(UUID().uuidString)")
    try! FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    return tmp
}

/// Creates a job directory with an optional job.swift and config.json.
@discardableResult
func createJobDir(
    in parent: URL,
    name: String,
    swiftSource: String? = "import Foundation\nprint(\"hello\")\n",
    configJSON: String? = nil
) -> URL {
    let jobDir = parent.appending(path: name)
    try! FileManager.default.createDirectory(at: jobDir, withIntermediateDirectories: true)

    if let source = swiftSource {
        let sourceURL = jobDir.appending(path: "job.swift")
        try! source.write(to: sourceURL, atomically: true, encoding: .utf8)
    }

    if let config = configJSON {
        let configURL = jobDir.appending(path: "config.json")
        try! config.write(to: configURL, atomically: true, encoding: .utf8)
    }

    return jobDir
}

/// Builds a JobDescriptor pointing at a real job directory.
func makeDescriptor(
    in parent: URL,
    name: String,
    config: JobConfig = .default
) -> JobDescriptor {
    let dir = parent.appending(path: name)
    return JobDescriptor(
        name: name,
        directory: dir,
        sourceURL: dir.appending(path: "job.swift"),
        binaryURL: dir.appending(path: ".job-bin"),
        config: config
    )
}

/// Removes a temporary directory.
func cleanupTempDir(_ url: URL) {
    try? FileManager.default.removeItem(at: url)
}
