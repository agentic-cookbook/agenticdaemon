import Testing
import Foundation
@testable import AgenticDaemonLib

@Suite("SwiftCompiler", .serialized)
struct SwiftCompilerTests {
    let compiler = SwiftCompiler()
    let tmpDir: URL

    init() {
        tmpDir = makeTempDir(prefix: "compiler")
    }

    @Test("needsCompile returns true when no binary exists")
    func needsCompileNoBinary() {
        createJobDir(in: tmpDir, name: "fresh")
        let descriptor = makeDescriptor(in: tmpDir, name: "fresh")

        #expect(compiler.needsCompile(job: descriptor) == true)
        cleanupTempDir(tmpDir)
    }

    @Test("needsCompile returns false when binary is newer than source")
    func needsCompileBinaryNewer() throws {
        createJobDir(in: tmpDir, name: "cached")
        let descriptor = makeDescriptor(in: tmpDir, name: "cached")

        try compiler.compile(job: descriptor)

        #expect(compiler.needsCompile(job: descriptor) == false)
        cleanupTempDir(tmpDir)
    }

    @Test("needsCompile returns true when source is newer than binary")
    func needsCompileSourceNewer() throws {
        createJobDir(in: tmpDir, name: "updated")
        let descriptor = makeDescriptor(in: tmpDir, name: "updated")

        try compiler.compile(job: descriptor)

        // Touch source to make it newer
        Thread.sleep(forTimeInterval: 1.0)
        let newSource = "import Foundation\nprint(\"updated\")\n"
        try newSource.write(to: descriptor.sourceURL, atomically: true, encoding: .utf8)

        #expect(compiler.needsCompile(job: descriptor) == true)
        cleanupTempDir(tmpDir)
    }

    @Test("compile produces executable binary from valid source")
    func compilesValidSource() throws {
        createJobDir(in: tmpDir, name: "valid", swiftSource: "import Foundation\nprint(\"ok\")\n")
        let descriptor = makeDescriptor(in: tmpDir, name: "valid")

        try compiler.compile(job: descriptor)

        let binaryPath = descriptor.binaryURL.path(percentEncoded: false)
        #expect(FileManager.default.fileExists(atPath: binaryPath))
        #expect(FileManager.default.isExecutableFile(atPath: binaryPath))
        cleanupTempDir(tmpDir)
    }

    @Test("compile throws for invalid source")
    func compilesInvalidSource() throws {
        createJobDir(in: tmpDir, name: "broken", swiftSource: "this is not valid swift }{}{")
        let descriptor = makeDescriptor(in: tmpDir, name: "broken")

        var didThrow = false
        do {
            try compiler.compile(job: descriptor)
        } catch is CompileError {
            didThrow = true
        }
        #expect(didThrow)
        cleanupTempDir(tmpDir)
    }
}
