import Foundation

struct JobDescriptor: Sendable {
    let name: String
    let directory: URL
    let sourceURL: URL
    let binaryURL: URL
    let config: JobConfig
}
